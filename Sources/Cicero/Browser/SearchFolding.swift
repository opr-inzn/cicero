import AppKit

enum SearchFolding {
    private static let narrowest: CGFloat = 300
    private static let minimumKey = "minimumWidthForSearchFieldRepresentation"
    private static let setExpanded = NSSelectorFromString("_setExpanded:animated:")
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification, object: nil, queue: .main) { note in
            guard let item = note.userInfo?["item"] as? NSSearchToolbarItem else { return }
            MainActor.assumeIsolated { setMinimum(item) }
        }
        for case let item as NSSearchToolbarItem in NSApp.windows.flatMap({ $0.toolbar?.items ?? [] }) {
            setMinimum(item)
        }
        NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: nil, queue: .main) { note in
            guard let field = note.object as? NSSearchField, field.stringValue.isEmpty else { return }
            MainActor.assumeIsolated {
                let items = field.window?.toolbar?.items ?? []
                guard let item = items.first(where: { ($0 as? NSSearchToolbarItem)?.searchField === field }) as? NSSearchToolbarItem else { return }
                refold(item)
            }
        }
    }

    private static func setMinimum(_ item: NSSearchToolbarItem) {
        guard item.responds(to: NSSelectorFromString(minimumKey)), item.responds(to: NSSelectorFromString("setMinimumWidthForSearchFieldRepresentation:")) else { return }
        item.setValue(narrowest, forKey: minimumKey)
        // Never under the minimum: a field folded for want of room then stays folded when clicked.
        item.preferredWidthForSearchField = max(item.preferredWidthForSearchField, narrowest)
    }

    private static func refold(_ item: NSSearchToolbarItem) {
        guard item.responds(to: setExpanded) else { return }
        typealias SetExpanded = @convention(c) (NSSearchToolbarItem, Selector, Bool, Bool) -> Void
        // Folded first, then fitted to the room: an open field squeezes the title, so the toolbar always finds room for it and never folds it again by itself.
        unsafeBitCast(item.method(for: setExpanded), to: SetExpanded.self)(item, setExpanded, false, false)
        item.endSearchInteraction()
    }
}
