import Foundation
import Observation
import Sparkle

/// Updates through Sparkle. While the user leaves it on (Settings → General), Sparkle reads the appcast
/// on GitHub as Cicero opens and once a day while it stays open (SUFeedURL in Info.plist); Cicero →
/// Check for Updates reads it now. Nothing else is sent: Sparkle's system profile is off. Updates are
/// checked against SUPublicEDKey.
@Observable
final class Updates {
    /// False while a check is under way, and when the updater couldn't start.
    private(set) var canCheckForUpdates = false
    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        // A binary run from .build (swift run) has no Info.plist to say where updates are.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.startUpdater()
        // Sparkle counts its day from the last check, so opening Cicero within a day of one wouldn't check.
        // Checking before its first scheduling pass, a run loop turn after startUpdater, makes it skip that
        // pass and count the next day from this check.
        if checksAutomatically { controller.updater.checkForUpdatesInBackground() }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
