import AppKit
import CiceroCore

/// Cicero's lock (`AppLock`) at launch, waited for as long as something else holds it: a `cicero` command making a
/// change while Cicero was closed, or another Cicero that uses the same data. Opening without it would make two
/// writers. After a moment, a message says what Cicero waits for, with Quit.
@MainActor
enum LaunchWait {
    /// How long Cicero waits before it says so: most commands are done by then.
    static let quietly: Duration = .seconds(1)
    /// Whether the message showed. Then SwiftUI doesn't open the Library window at launch by itself, and Cicero opens it.
    /// (The app answers Accessibility only once it has finished launching, so VoiceOver can't read the message;
    /// finishing the launch early for it makes the app miss its own launch.)
    private(set) static var showedMessage = false

    /// nil only when the lock file can't be made at all; then Cicero opens without it, as it can't share anyway.
    static func lock(support: URL) -> AppLock? {
        let holder = AppLock.Holder.app(name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cicero")
        let deadline = ContinuousClock.now + quietly
        while ContinuousClock.now < deadline {
            switch AppLock.attempt(support: support, holder: holder) {
            case .taken(let lock): return lock
            case .unavailable: return nil
            case .held: Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return showingMessage(support: support, holder: holder)
    }

    private final class Outcome {
        var lock: AppLock?
        var shown: AppLock.Holder?
    }

    private static func showingMessage(support: URL, holder: AppLock.Holder) -> AppLock? {
        showedMessage = true
        let app = NSApplication.shared
        let alert = NSAlert()
        alert.addButton(withTitle: "Quit")
        let outcome = Outcome()
        func show(_ other: AppLock.Holder) {
            guard other != outcome.shown else { return }
            outcome.shown = other
            (alert.messageText, alert.informativeText) = message(other)
            alert.layout()
        }
        show(AppLock.holder(support: support))
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                switch AppLock.attempt(support: support, holder: holder) {
                case .taken(let lock):
                    outcome.lock = lock
                    app.abortModal()
                case .unavailable:
                    app.abortModal()
                case .held:
                    show(AppLock.holder(support: support))
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        app.activate()
        let response = alert.runModal()
        timer.invalidate()
        alert.window.close()
        if response == .alertFirstButtonReturn { exit(0) }
        return outcome.lock
    }

    private static func message(_ holder: AppLock.Holder) -> (String, String) {
        switch holder {
        case .command:
            ("Waiting for the Cicero CLI", "The Cicero CLI is making a change. Cicero opens as soon as it’s done.")
        case .app(let name):
            ("Another Cicero Is Open", "“\(name)” uses the same fonts and data. Quit it, and this Cicero opens.")
        }
    }
}
