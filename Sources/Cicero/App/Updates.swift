import Foundation
import Observation
import Sparkle

/// Updates through Sparkle. While the user leaves it on (Settings → General), Sparkle reads the appcast
/// on GitHub once a day (SUFeedURL in Info.plist); Cicero → Check for Updates… reads it now. Nothing
/// else is sent: Sparkle's system profile is off. Updates are checked against SUPublicEDKey.
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
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
