import AppKit

/// Menu shortcuts come before the focused view, so ⌘⌫ (Deactivate) and ⌘↓ (Open) would act on the
/// selected fonts while the user types. While an editable text view or field has the focus, the text
/// system's own ⌘ shortcuts go to the text instead, as in any Mac app: ⌘⌫ deletes to the start of the
/// line, ⌘↑ and ⌘↓ move to the start and end of the text, ⌘← and ⌘→ to the ends of the line (⇧
/// selects). Everywhere else the menus get them as before.
enum TextEditingKeys {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, in: NSApp.keyWindow)
        }
    }

    /// Gives the event to the window's text view and swallows it when it's one of those shortcuts.
    static func handle(_ event: NSEvent, in window: NSWindow?) -> NSEvent? {
        guard isTextShortcut(event), let text = window?.firstResponder as? NSTextView, text.isEditable else { return event }
        text.keyDown(with: event)
        return nil
    }

    /// ⌘⌫, and ⌘ or ⇧⌘ with an arrow key: the standard key bindings that have ⌘ in them.
    private static func isTextShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.specialKey {
        case .delete: return modifiers == .command
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return modifiers == .command || modifiers == [.command, .shift]
        default: return false
        }
    }
}
