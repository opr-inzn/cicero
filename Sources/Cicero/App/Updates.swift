import Foundation
import Observation
import Sparkle

/// Updates through Sparkle. While the user leaves it on (Settings → General), Sparkle reads the appcast
/// on GitHub as Cicero opens and once a day while it stays open (SUFeedURL in Info.plist); Cicero →
/// Check for Updates reads it now. Nothing else is sent: Sparkle's system profile is off. Updates are
/// checked against SUPublicEDKey.
///
/// The appcast lists the latest stable version and, while there's a newer one, the latest beta, in Sparkle's "beta"
/// channel (see scripts/make-appcast.sh). Only a user who turns on `getsBetas` is offered it.
@Observable
final class Updates {
    /// False while a check is under way, and when the updater couldn't start.
    private(set) var canCheckForUpdates = false
    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// Whether to be offered beta versions. On at first in a beta, so that its user gets the next one; off in a stable
    /// version. Turning it off doesn't go back: Sparkle never offers an older build, so a beta stays until the next
    /// stable version.
    var getsBetas: Bool {
        didSet {
            UserDefaults.standard.set(getsBetas, forKey: Channels.key)
            if getsBetas, checksAutomatically, canCheckForUpdates { controller.updater.checkForUpdatesInBackground() }
        }
    }

    @ObservationIgnored private let channels = Channels()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // The controller keeps its delegate weakly; `channels` keeps it alive.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: channels, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        getsBetas = Channels.getsBetas
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

/// Tells Sparkle which channels besides the default one to offer updates from. It asks at each check, so a change to
/// the setting counts from the next check.
private nonisolated final class Channels: NSObject, SPUUpdaterDelegate {
    static let key = "getsBetaUpdates"

    /// The setting, or, before the user sets it, whether this version is a beta ("0.12.0b1"). Read with `bool(forKey:)`,
    /// which also takes "YES" and "NO", as given on the command line (`-getsBetaUpdates YES`).
    static var getsBetas: Bool {
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return version.wholeMatch(of: /[0-9.]+b[0-9]+/) != nil
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.getsBetas ? ["beta"] : []
    }
}
