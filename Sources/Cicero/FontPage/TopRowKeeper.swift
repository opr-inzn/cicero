import SwiftUI

@MainActor
final class TopRowKeeper {
    static let space = "fontPageContent"
    var scrollTo: ((CGFloat) -> Void)?
    var visibleTop: CGFloat = 0
    private var frames: [Int: CGRect] = [:]
    private var held: Held?
    private var settling: Task<Void, Never>?

    private struct Held {
        let key: Int
        var fraction: CGFloat?
        var gap: CGFloat?
    }

    private var isResizing: Bool { settling != nil }

    func moved(_ key: Int, to frame: CGRect) {
        // A row as wide as it was not: the page is changing width, and rows say so before the page does.
        if let before = frames[key], abs(before.width - frame.width) >= 0.5 { resizing() }
        frames[key] = frame
        if let held, held.key == key, isResizing { keep(held, at: frame) }
    }

    func gone(_ key: Int) {
        frames[key] = nil
    }

    private func resizing() {
        if !isResizing { held = top() }
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            if let held, let frame = frames[held.key] { keep(held, at: frame) }
            settling = nil
        }
    }

    private func keep(_ held: Held, at frame: CGRect) {
        scrollTo?(held.gap.map { frame.minY - $0 } ?? frame.minY + (held.fraction ?? 0) * frame.height)
    }

    private func top() -> Held? {
        guard visibleTop > 0.5,
              let (key, frame) = frames.filter({ $0.value.maxY > visibleTop }).min(by: { $0.value.minY < $1.value.minY })
        else { return nil }
        return frame.minY <= visibleTop ? Held(key: key, fraction: (visibleTop - frame.minY) / max(frame.height, 1))
            : Held(key: key, gap: frame.minY - visibleTop)
    }
}

extension EnvironmentValues {
    @Entry var topRowKeeper: TopRowKeeper?
}
