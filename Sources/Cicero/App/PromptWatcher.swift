import AppKit
import SwiftUI

final class PromptWatcher {
    var openWindow: OpenWindowAction?

    private let model: AppModel
    private var isStarted = false

    init(model: AppModel) {
        self.model = model
    }

    func connect(openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        watchPrompts()
    }

    private func watchPrompts() {
        withObservationTracking {
            _ = model.isShowingPrompt
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.watchPrompts()
                if self.model.isShowingPrompt { self.showLibraryForPrompt() }
            }
        }
    }

    private func showLibraryForPrompt() {
        guard model.earlierImportPrompt == nil else { return }
        let front = NSApp.keyWindow.map { $0.sheetParent ?? $0 }
        guard !NSApp.isActive || front?.identifier?.rawValue != WindowID.main else { return }
        NSApp.bringForward { openWindow?(id: WindowID.main) }
    }
}

extension NSApplication {
    func terminateFromRunLoop(ifCancelled: @escaping () -> Void = {}) {
        // Not from a task on the main actor: there, terminate waits for a later reply that only another main-actor task can send, and Cicero hangs.
        RunLoop.main.perform {
            NSApp.terminate(nil)
            ifCancelled()
        }
    }

    func bringForward(opening open: () -> Void = {}) {
        unhide(nil)
        activate()
        open()
        // macOS 26 turns down an app's own request to come forward, so Cicero also asks Launch Services, as the Dock does.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }
}
