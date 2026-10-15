import AppKit

/// Menu shortcuts come before the focused view, so ⌫ (Deactivate), ⌘⌫ (Move to Trash) and ⌘↓ (Open)
/// would act on the selected fonts while the user types. While an editable text view or field has the
/// focus, the text system's own keys go to the text instead, as in any Mac app: ⌫ deletes a character,
/// ⌘⌫ to the start of the line, ⌘↑ and ⌘↓ move to the start and end of the text, ⌘← and ⌘→ to the ends
/// of the line (⇧ selects). ⌫ and ⌘⌫ act on the fonts selected in the main window, so in other windows
/// (Compare, the Character Toolbox, Settings, sheets) they go to the window rather than the menus.
/// Everywhere else the menus get them as before.
enum TextEditingKeys {
    private static var monitor: Any?
    /// The browser's window, where ⌫ and ⌘⌫ turn off and trash the fonts selected in it.
    static weak var mainWindow: NSWindow?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, in: NSApp.keyWindow)
        }
    }

    /// Gives the event to the window's text view, or ⌫ and ⌘⌫ outside the main window to that window, and
    /// swallows it so the menus don't get it.
    static func handle(_ event: NSEvent, in window: NSWindow?) -> NSEvent? {
        if isTextShortcut(event), let text = window?.firstResponder as? NSTextView, text.isEditable {
            text.keyDown(with: event)
            return nil
        }
        if isDelete(event), let window, window !== mainWindow {
            window.sendEvent(event)
            return nil
        }
        return event
    }

    /// ⌫ and ⌘⌫, and ⌘ or ⇧⌘ with an arrow key: the standard key bindings menu shortcuts here would take.
    private static func isTextShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.specialKey {
        case .delete: return isDelete(event)
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return modifiers == .command || modifiers == [.command, .shift]
        default: return false
        }
    }

    private static func isDelete(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.specialKey == .delete && (modifiers.isEmpty || modifiers == .command)
    }
}
