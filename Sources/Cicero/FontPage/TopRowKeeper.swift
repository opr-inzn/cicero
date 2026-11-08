import SwiftUI

/// Keeps the glyph row at the top of a font page where it is while the page changes width, as the Info panel or the
/// sidebar slides: the squares then change size (see `GlyphGridRow.side`), every row above with them, and the page,
/// scrolled as far as it was, showed rows further down. As the width starts to change it notes the row at the top edge,
/// below the toolbar, and how far into it the edge is, or how far below the edge the next row starts; while the width
/// changes it scrolls so that row is there again, as far in. Rows say where they are in the page's content (`moved`),
/// which scrolling doesn't change, so where to scroll to comes from one layout, not from where they were on screen and
/// how far the page was scrolled, which came a frame apart.
@MainActor
final class TopRowKeeper {
    /// The page's content, which rows say where they are in.
    static let space = "fontPageContent"
    /// Shows this point of the page's content at the top edge, below the toolbar (`ScrollPosition.scrollTo(y:)`).
    var scrollTo: ((CGFloat) -> Void)?
    /// The point of the page's content at the top edge now.
    var visibleTop: CGFloat = 0
    /// Where each row on screen is in the page's content, by its key.
    private var frames: [Int: CGRect] = [:]
    /// The row at the top edge as the width started to change, and how it sat there: `fraction` of it above the edge,
    /// or `gap` between the edge and it.
    private var held: Held?
    private var settling: Task<Void, Never>?

    private struct Held {
        let key: Int
        var fraction: CGFloat?
        var gap: CGFloat?
    }

    private var isResizing: Bool { settling != nil }

    func moved(_ key: Int, to frame: CGRect) {
        // A row as wide as it was not: the page is changing width. Rows say so before the page does; the row at the top
        // is noted from where the rows were until now.
        if let before = frames[key], abs(before.width - frame.width) >= 0.5 { resizing() }
        frames[key] = frame
        if let held, held.key == key, isResizing { keep(held, at: frame) }
    }

    func gone(_ key: Int) {
        frames[key] = nil
    }

    /// The width changed: rows are held until it hasn't for a moment.
    private func resizing() {
        if !isResizing { held = top() }
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            // Once more where the last layout put the row.
            if let held, let frame = frames[held.key] { keep(held, at: frame) }
            settling = nil
        }
    }

    private func keep(_ held: Held, at frame: CGRect) {
        scrollTo?(held.gap.map { frame.minY - $0 } ?? frame.minY + (held.fraction ?? 0) * frame.height)
    }

    /// The row the top edge is in, or else the first below it; none at the page's top, which stays there.
    private func top() -> Held? {
        guard visibleTop > 0.5,
              let (key, frame) = frames.filter({ $0.value.maxY > visibleTop }).min(by: { $0.value.minY < $1.value.minY })
        else { return nil }
        return frame.minY <= visibleTop ? Held(key: key, fraction: (visibleTop - frame.minY) / max(frame.height, 1))
            : Held(key: key, gap: frame.minY - visibleTop)
    }
}

extension EnvironmentValues {
    /// The open font page's (see `TopRowKeeper`); nil elsewhere.
    @Entry var topRowKeeper: TopRowKeeper?
}
