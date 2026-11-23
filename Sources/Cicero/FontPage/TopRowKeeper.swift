import SwiftUI

@MainActor
final class TopRowKeeper {
    static let space = "fontPageContent"
    var scrollTo: ((CGFloat) -> Void)?
    var visibleTop: CGFloat = 0
    private var rows: [UUID: Row] = [:]
    private var held: Held?
    private var settling: Task<Void, Never>?

    private struct Row {
        var frame: CGRect
        var cells: [GridCell]
    }

    private struct Held {
        let cell: GridCell
        var fraction: CGFloat?
        var gap: CGFloat?
    }

    private var isResizing: Bool { settling != nil }

    func moved(_ id: UUID, cells: [GridCell], to frame: CGRect) {
        // A row as wide as it was not: the page is changing width, and rows say so before the page does.
        if let before = rows[id], abs(before.frame.width - frame.width) >= 0.5 { resizing() }
        rows[id] = Row(frame: frame, cells: cells)
        if let held, isResizing, cells.contains(held.cell) { keep(held, at: frame) }
    }

    func update(_ id: UUID, cells: [GridCell]) {
        rows[id]?.cells = cells
    }

    func gone(_ id: UUID) {
        rows[id] = nil
    }

    private func resizing() {
        if !isResizing { held = top() }
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            if let held, let row = rows.values.first(where: { $0.cells.contains(held.cell) }) { keep(held, at: row.frame) }
            settling = nil
        }
    }

    private func keep(_ held: Held, at frame: CGRect) {
        scrollTo?(held.gap.map { frame.minY - $0 } ?? frame.minY + (held.fraction ?? 0) * frame.height)
    }

    private func top() -> Held? {
        guard visibleTop > 0.5,
              let row = rows.values.filter({ $0.frame.maxY > visibleTop && !$0.cells.isEmpty }).min(by: { $0.frame.minY < $1.frame.minY }),
              let cell = row.cells.first
        else { return nil }
        return row.frame.minY <= visibleTop ? Held(cell: cell, fraction: (visibleTop - row.frame.minY) / max(row.frame.height, 1))
            : Held(cell: cell, gap: row.frame.minY - visibleTop)
    }
}

extension EnvironmentValues {
    @Entry var topRowKeeper: TopRowKeeper?
}
