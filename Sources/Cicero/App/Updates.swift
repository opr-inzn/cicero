import AppKit
import Foundation
import Observation
import Sparkle

/// Updates through Sparkle. While the user leaves it on (Settings → General), Sparkle reads the appcast
/// on GitHub as Cicero opens and once a day while it stays open (SUFeedURL in Info.plist); Cicero →
/// Check for Updates reads it now. Nothing else is sent: Sparkle's system profile is off. Updates are
/// checked against SUPublicEDKey.
///
/// The appcast lists the latest stable version and, while there's a newer one, the latest beta, in Sparkle's "beta"
/// channel (see scripts/make-appcast.sh). Only the beta track is offered it. Sparkle never installs an older build, so
/// moving a beta to the stable track when no stable version is newer offers going back to the latest one instead
/// (`stableToGoBackTo`, see GoingBack.swift).
@Observable
final class Updates {
    enum Track: String, CaseIterable, Identifiable {
        case stable, beta
        var id: Self { self }
        var title: String { self == .stable ? "Stable" : "Beta" }
    }

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(String)
        case failed(String)
    }

    /// A stable version in the appcast, with what going back to it needs.
    struct StableVersion: Equatable {
        let version: String
        let build: Int
        let url: URL
        let signature: String
    }

    /// False while a check is under way, and when the updater couldn't start.
    private(set) var canCheckForUpdates = false
    private(set) var status: Status = .idle
    /// The newest stable version in the appcast last read.
    private(set) var latestStable: StableVersion?
    /// Set when moving this beta to the stable track found no stable version newer than it; the settings ask whether to
    /// go back to this one.
    var stableToGoBackTo: StableVersion?
    /// What going back is doing, while it does.
    private(set) var goingBack: String?
    /// Why going back failed, with the version, so the settings can offer its download instead.
    var goingBackFailure: (stable: StableVersion, message: String)?

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// The beta track is offered betas. At first it's the beta track in a beta and the stable one otherwise.
    var track: Track {
        didSet {
            guard track != oldValue else { return }
            UserDefaults.standard.set(track == .beta, forKey: Channels.key)
            trackChanged()
        }
    }

    let version = Channels.version
    let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    var isBeta: Bool { Channels.isBeta(version) }

    @ObservationIgnored private let channels = Channels()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Whether the check under way answers a move to the stable track.
    @ObservationIgnored private var checkingForStable = false

    init() {
        // The controller keeps its delegate weakly; `channels` keeps it alive.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: channels, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        track = Channels.getsBetas ? .beta : .stable
        channels.owner = self
        // A binary run from .build (swift run) has no Info.plist to say where updates are.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.startUpdater()
        // Sparkle counts its day from the last check, so opening Cicero within a day of one wouldn't check.
        // Checking before its first scheduling pass, a run loop turn after startUpdater, makes it skip that
        // pass and count the next day from this check.
        if checksAutomatically {
            status = .checking
            controller.updater.checkForUpdatesInBackground()
        }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Checks now, with Sparkle's window: it says when Cicero is up to date, and offers an update it finds.
    func checkForUpdates() {
        status = .checking
        controller.checkForUpdates(nil)
    }

    /// A beta on the stable track updates to the next stable version; when there's none newer yet, the user is asked
    /// whether to go back to the latest. That check reads the appcast without Sparkle's window. Moving to the beta
    /// track checks in the background, as at launch, so a newer beta is found now rather than tomorrow.
    private func trackChanged() {
        guard canCheckForUpdates else { return }
        if track == .stable, isBeta {
            checkingForStable = true
            status = .checking
            controller.updater.checkForUpdateInformation()
        } else if checksAutomatically {
            status = .checking
            controller.updater.checkForUpdatesInBackground()
        }
    }

    // MARK: Sparkle's answers (from Channels, on the main thread)

    fileprivate func loaded(stable: StableVersion?) {
        latestStable = stable
    }

    fileprivate func found(_ version: String) {
        status = .available(version)
        checkingForStable = false
    }

    fileprivate func foundNone() {
        status = .upToDate
        guard checkingForStable else { return }
        checkingForStable = false
        if track == .stable, let latestStable, latestStable.build < build { stableToGoBackTo = latestStable }
    }

    fileprivate func finished(error: Error?) {
        checkingForStable = false
        guard let error = error as NSError?, status == .checking else { return }
        // Not finding an update ends a cycle with an error too.
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) { return status = .upToDate }
        status = .failed(error.localizedDescription)
    }

    // MARK: Going back

    /// Replaces this beta with `stable` once Cicero quits, and quits; the caller saves the setup first. On failure,
    /// says why in `goingBackFailure`, and Cicero stays as it is.
    func goBack(to stable: StableVersion) async {
        goingBack = "Downloading Cicero \(stable.version)…"
        do {
            let staged = try await GoingBack.stage(stable) { [weak self] step in self?.goingBack = step }
            goingBack = "Opening Cicero \(stable.version)…"
            try GoingBack.replaceAfterQuit(current: Bundle.main.bundleURL, with: staged)
            NSApp.terminate(nil)
        } catch {
            goingBack = nil
            goingBackFailure = (stable, error.localizedDescription)
        }
    }
}

/// Tells Sparkle which channels besides the default one to offer updates from, and passes what it finds to `Updates`.
/// Sparkle asks for the channels at each check, so a change to the track counts from the next check. It calls all of
/// these on the main thread.
private nonisolated final class Channels: NSObject, SPUUpdaterDelegate {
    static let key = "getsBetaUpdates"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    nonisolated(unsafe) weak var owner: Updates?

    static func isBeta(_ version: String) -> Bool {
        version.wholeMatch(of: /[0-9.]+b[0-9]+/) != nil
    }

    /// The setting, or, before the user sets it, whether this version is a beta ("0.12.0b1"). Read with `bool(forKey:)`,
    /// which also takes "YES" and "NO", as given on the command line (`-getsBetaUpdates YES`).
    static var getsBetas: Bool {
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        return isBeta(version)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.getsBetas ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let stable = appcast.items.filter { $0.channel == nil }.compactMap(Self.stableVersion).max { $0.build < $1.build }
        MainActor.assumeIsolated { owner?.loaded(stable: stable) }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { owner?.found(version) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { owner?.foundNone() }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let error = error.map { $0 as NSError }
        MainActor.assumeIsolated { owner?.finished(error: error) }
    }

    /// The enclosure's EdDSA signature is in the item's properties, as the appcast has it.
    private static func stableVersion(_ item: SUAppcastItem) -> Updates.StableVersion? {
        guard let build = Int(item.versionString), let url = item.fileURL,
              let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
              let signature = enclosure["sparkle:edSignature"] as? String else { return nil }
        return Updates.StableVersion(version: item.displayVersionString, build: build, url: url, signature: signature)
    }
}
