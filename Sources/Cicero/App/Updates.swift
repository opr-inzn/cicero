import AppKit
import Foundation
import Observation
import Sparkle

@Observable
final class Updates {
    enum Track: String, CaseIterable, Identifiable {
        case stable, nightly
        var id: Self { self }
        var title: String { self == .stable ? "Stable" : "Nightly" }
    }

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(String)
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let build: String
        let url: URL
        let signature: String
        var isNightly: Bool { Channels.isNightly(version) }
    }

    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"
    private(set) var canCheckForUpdates = false
    private(set) var status: Status = .idle
    private(set) var readyVersion: String?
    private(set) var readyNotes: ReleaseNotes?
    private(set) var available: Release?
    private(set) var availableNotes: ReleaseNotes?
    var offeredVersion: String? { readyVersion ?? available?.version }
    var offeredNotes: ReleaseNotes? { readyVersion != nil ? readyNotes : availableNotes }
    var showsReadyNotes = false
    var switchOffer: Release?
    private(set) var switching: String?
    var switchFailure: (release: Release, message: String)?

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }
    var track: Track {
        didSet {
            guard track != oldValue else { return }
            UserDefaults.standard.set(track == .nightly, forKey: Channels.key)
            trackChanged()
        }
    }

    let version = Channels.version
    let build = Channels.build
    var isNightly: Bool { Channels.isNightly(version) }

    @ObservationIgnored private let channels = Channels()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var checkWhenReady = false
    @ObservationIgnored private var checkTrackWhenReady = false
    @ObservationIgnored private var installReady: (() -> Void)?
    @ObservationIgnored private var latest: [Track: Release] = [:]
    @ObservationIgnored private var checkingNewTrack = false

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: channels, userDriverDelegate: nil)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
        if UserDefaults.standard.object(forKey: Channels.key) == nil {
            UserDefaults.standard.set(Channels.getsNightlies, forKey: Channels.key)
        }
        track = Channels.getsNightlies ? .nightly : .stable
        channels.owner = self
        #if CICERO_DEV
        if let preview = ProcessInfo.processInfo.environment["CICERO_PREVIEW_UPDATE"], !preview.isEmpty {
            readyVersion = preview
            readyNotes = ReleaseNotes.bundled?.first?.notes
        }
        #endif
        guard isAvailable else { return }
        controller.startUpdater()
        if checksAutomatically {
            status = .checking
            controller.updater.checkForUpdatesInBackground()
        }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
                self.checkIfWaiting()
            }
        }
    }

    func checkForUpdates() {
        checkWhenReady = true
        checkIfWaiting()
    }

    func installReadyUpdate() {
        installReady?()
    }

    func restartToUpdate() {
        if let installReady { return installReady() }
        guard let available, switching == nil else { return }
        Task {
            do { try await replace(with: available) } catch { checkForUpdates() }
        }
    }

    private func checkIfWaiting() {
        guard controller.updater.canCheckForUpdates else { return }
        if checkWhenReady {
            checkWhenReady = false
            checkTrackWhenReady = false
            status = .checking
            controller.checkForUpdates(nil)
        } else if checkTrackWhenReady {
            checkTrackWhenReady = false
            checkingNewTrack = true
            status = .checking
            controller.updater.checkForUpdateInformation()
        }
    }

    private func trackChanged() {
        switchOffer = nil
        guard readyVersion == nil else { return }
        checkTrackWhenReady = true
        checkIfWaiting()
    }

    // MARK: Sparkle's answers

    fileprivate func loaded(_ latest: [Track: Release]) {
        self.latest = latest
    }

    fileprivate func found(_ version: String, release: Release?, notes: ReleaseNotes?) {
        status = .available(version)
        available = release
        availableNotes = notes
        checkingNewTrack = false
    }

    fileprivate func foundNone() {
        status = .upToDate
        available = nil
        availableNotes = nil
        guard checkingNewTrack else { return }
        checkingNewTrack = false
        guard readyVersion == nil else { return }
        if let release = latest[track], Channels.isOlder(release.build, than: build) { switchOffer = release }
    }

    fileprivate func ready(_ version: String, notes: ReleaseNotes?, install: @escaping () -> Void) {
        readyVersion = version
        readyNotes = notes
        installReady = install
    }

    fileprivate func finished(error: Error?) {
        checkingNewTrack = false
        guard let error = error as NSError?, status == .checking else { return }
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) {
            status = .upToDate
            return
        }
        status = .failed(error.localizedDescription)
    }

    // MARK: Switching

    func switchTo(_ release: Release) async {
        guard readyVersion == nil else { return }
        do {
            try await replace(with: release)
        } catch {
            switchFailure = (release, error.localizedDescription)
        }
    }

    private func replace(with release: Release) async throws {
        switching = "Downloading Cicero \(release.version)"
        var staged: URL?
        do {
            let copied = try await VersionSwitch.stage(release) { [weak self] step in self?.switching = step }
            staged = copied
            switching = "Opening Cicero \(release.version)"
            try VersionSwitch.replaceAfterQuit(current: Bundle.main.bundleURL, with: copied)
            NSApp.terminate(nil)
        } catch {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            switching = nil
            throw error
        }
    }
}

private final class Channels: NSObject, SPUUpdaterDelegate {
    static let key = "getsNightlyUpdates"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    weak var owner: Updates?

    static func isNightly(_ version: String) -> Bool {
        version.wholeMatch(of: /[0-9.]+-nightly\.[0-9]+/) != nil
    }

    static func isOlder(_ a: String, than b: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(a, toVersion: b) == .orderedAscending
    }

    static var getsNightlies: Bool {
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        return isNightly(version)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.getsNightlies ? ["nightly"] : []
    }

    static func baseVersion(_ version: String) -> String {
        version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard Self.getsNightlies else { return nil }
        let currentBase = Self.baseVersion(Self.version)
        let eligible = appcast.items.filter { item in
            guard Self.isOlder(Self.build, than: item.versionString) else { return false }
            if item.channel == "nightly" { return true }
            return item.channel == nil && !Self.isOlder(item.displayVersionString, than: currentBase)
        }
        return eligible.max { Self.isOlder($0.versionString, than: $1.versionString) } ?? SUAppcastItem.empty()
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        var latest: [Updates.Track: Updates.Release] = [:]
        for item in appcast.items where item.minimumOperatingSystemVersionIsOK {
            guard let release = Self.release(item) else { continue }
            let track: Updates.Track = item.channel == "nightly" ? .nightly : .stable
            if let known = latest[track], !Self.isOlder(known.build, than: release.build) { continue }
            latest[track] = release
        }
        owner?.loaded(latest)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = "\(item.displayVersionString) (\(item.versionString))"
        owner?.found(version, release: Self.release(item), notes: Self.notes(item))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        owner?.foundNone()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        owner?.ready(item.displayVersionString, notes: Self.notes(item), install: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        owner?.finished(error: error)
    }

    private static func notes(_ item: SUAppcastItem) -> ReleaseNotes? {
        item.itemDescription.flatMap { ReleaseNotes.sources("## \(item.displayVersionString)\n\($0)").first?.notes }
    }

    private static func release(_ item: SUAppcastItem) -> Updates.Release? {
        guard let url = item.fileURL, let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
              let signature = enclosure["sparkle:edSignature"] as? String else { return nil }
        return Updates.Release(version: item.displayVersionString, build: item.versionString, url: url, signature: signature)
    }
}
