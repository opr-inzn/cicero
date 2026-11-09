import AppKit

enum TextEditingKeys {
    private static var monitor: Any?
    static weak var mainWindow: NSWindow?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, in: NSApp.keyWindow)
        }
    }

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
