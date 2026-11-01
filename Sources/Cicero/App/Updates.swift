import AppKit
import Foundation
import Observation
import Sparkle

/// Updates through Sparkle. While the user leaves it on (Settings → General), Sparkle reads the appcast
/// on GitHub as Cicero opens and once a day while it stays open (SUFeedURL in Info.plist); Cicero →
/// Check for Updates reads it now. Nothing else is sent: Sparkle's system profile is off. Updates are
/// checked against SUPublicEDKey.
///
/// Two tracks, each offered only its own versions: the appcast's stable versions (in no channel) and its betas (in
/// Sparkle's "beta" channel, see scripts/make-appcast.sh). The track is saved at the first launch and only the user
/// changes it, so an update never moves anyone to the other track. When the user does, and the new track has nothing
/// newer than this version, Sparkle, which never installs an older build, can't help: `switchOffer` asks whether to
/// switch to that track's latest version instead (VersionSwitch.swift).
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

    /// A version in the appcast, with what switching to it needs.
    struct Release: Equatable {
        let version: String
        /// A whole number for a stable version; a beta's is the stable build before it, a dot and its number (62.1).
        let build: String
        let url: URL
        let signature: String
        var isBeta: Bool { Channels.isBeta(version) }
    }

    /// False while a check is under way, and when the updater couldn't start.
    private(set) var canCheckForUpdates = false
    private(set) var status: Status = .idle
    /// Set when the user moved to a track with nothing newer than this version: the settings ask whether to switch to
    /// that track's latest version, though its build is older.
    var switchOffer: Release?
    /// What switching is doing, while it does.
    private(set) var switching: String?
    /// Why switching failed, with the version, so the settings can offer its download instead.
    var switchFailure: (release: Release, message: String)?

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// Chosen at the first launch, the beta track in a beta and the stable one otherwise, and saved then (`init`), so
    /// an update never changes it: a beta user stays on betas after the stable version of that beta comes out.
    var track: Track {
        didSet {
            guard track != oldValue else { return }
            UserDefaults.standard.set(track == .beta, forKey: Channels.key)
            trackChanged()
        }
    }

    let version = Channels.version
    let build = Channels.build
    var isBeta: Bool { Channels.isBeta(version) }

    @ObservationIgnored private let channels = Channels()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// The latest version of each track in the appcast last read.
    @ObservationIgnored private var latest: [Track: Release] = [:]
    /// Whether the check under way answers a move to another track.
    @ObservationIgnored private var checkingNewTrack = false

    init() {
        // The controller keeps its delegate weakly; `channels` keeps it alive.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: channels, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        if UserDefaults.standard.object(forKey: Channels.key) == nil {
            UserDefaults.standard.set(Channels.isBeta(version), forKey: Channels.key)
        }
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

    /// Reads the appcast without Sparkle's window: a newer version on the new track shows as available, as ever; with
    /// none, `foundNone` offers that track's latest version.
    private func trackChanged() {
        switchOffer = nil
        guard canCheckForUpdates else { return }
        checkingNewTrack = true
        status = .checking
        controller.updater.checkForUpdateInformation()
    }

    // MARK: Sparkle's answers (from Channels, on the main thread)

    fileprivate func loaded(_ latest: [Track: Release]) {
        self.latest = latest
    }

    fileprivate func found(_ version: String) {
        status = .available(version)
        checkingNewTrack = false
    }

    fileprivate func foundNone() {
        status = .upToDate
        guard checkingNewTrack else { return }
        checkingNewTrack = false
        if let release = latest[track], Channels.isOlder(release.build, than: build) { switchOffer = release }
    }

    fileprivate func finished(error: Error?) {
        checkingNewTrack = false
        guard let error = error as NSError?, status == .checking else { return }
        // Not finding an update ends a cycle with an error too.
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) { return status = .upToDate }
        status = .failed(error.localizedDescription)
    }

    // MARK: Switching

    /// Replaces this version with `release` once Cicero quits, and quits; the caller saves the setup first. On failure,
    /// says why in `switchFailure`, and Cicero stays as it is.
    func switchTo(_ release: Release) async {
        switching = "Downloading Cicero \(release.version)…"
        do {
            let staged = try await VersionSwitch.stage(release) { [weak self] step in self?.switching = step }
            switching = "Opening Cicero \(release.version)…"
            try VersionSwitch.replaceAfterQuit(current: Bundle.main.bundleURL, with: staged)
            NSApp.terminate(nil)
        } catch {
            switching = nil
            switchFailure = (release, error.localizedDescription)
        }
    }
}

/// Tells Sparkle which versions each track is offered, and passes what it finds to `Updates`. Sparkle asks at each
/// check, so a change to the track counts from the next check. It calls all of these on the main thread.
private nonisolated final class Channels: NSObject, SPUUpdaterDelegate {
    static let key = "getsBetaUpdates"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    nonisolated(unsafe) weak var owner: Updates?

    static func isBeta(_ version: String) -> Bool {
        version.wholeMatch(of: /[0-9.]+b[0-9]+/) != nil
    }

    /// Builds compared as Sparkle compares them, part by part: 62 < 62.1 < 62.2 < 63.
    static func isOlder(_ a: String, than b: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(a, toVersion: b) == .orderedAscending
    }

    /// The setting, saved at the first launch (see `Updates.track`); before that, whether this version is a beta
    /// ("0.12.0b1"). Read with `bool(forKey:)`, which also takes "YES" and "NO", as given on the command line
    /// (`-getsBetaUpdates YES`).
    static var getsBetas: Bool {
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        return isBeta(version)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.getsBetas ? ["beta"] : []
    }

    /// The beta track takes only betas: the newest one above this build. A stable version, even with a higher build (a
    /// fix published while the beta is out), would take the beta's new features away. Sparkle has already left out the
    /// items for other systems. The stable track is Sparkle's own choice (nil), from the items in no channel.
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard Self.getsBetas else { return nil }
        let betas = appcast.items.filter { $0.channel == "beta" && Self.isOlder(Self.build, than: $0.versionString) }
        return betas.max { Self.isOlder($0.versionString, than: $1.versionString) } ?? SUAppcastItem.empty()
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        var latest: [Updates.Track: Updates.Release] = [:]
        for item in appcast.items {
            guard let release = Self.release(item) else { continue }
            let track: Updates.Track = item.channel == "beta" ? .beta : .stable
            if let known = latest[track], !Self.isOlder(known.build, than: release.build) { continue }
            latest[track] = release
        }
        MainActor.assumeIsolated { owner?.loaded(latest) }
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
    private static func release(_ item: SUAppcastItem) -> Updates.Release? {
        guard let url = item.fileURL, let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
              let signature = enclosure["sparkle:edSignature"] as? String else { return nil }
        return Updates.Release(version: item.displayVersionString, build: item.versionString, url: url, signature: signature)
    }
}
