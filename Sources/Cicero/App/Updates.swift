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
    private(set) var switching: Switching?
    var switchFailure: (release: Release, message: String)?

    var checksAutomatically: Bool {
        didSet { updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically: Bool {
        didSet { updater.automaticallyDownloadsUpdates = installsAutomatically }
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

    @ObservationIgnored private let channels: Channels
    @ObservationIgnored private let driver: UserDriver
    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var checkWhenReady = false
    @ObservationIgnored private var checkTrackWhenReady = false
    @ObservationIgnored private var installReady: (() -> Void)?
    @ObservationIgnored private var latest: [Track: Release] = [:]
    @ObservationIgnored private var checkingNewTrack = false
    @ObservationIgnored private var removedInstaller = false

    init() {
        let channels = Channels()
        let driver = UserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: channels)
        self.channels = channels
        self.driver = driver
        self.updater = updater
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsAutomatically = updater.automaticallyDownloadsUpdates
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
        do {
            try updater.start()
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        if checksAutomatically {
            status = .checking
            updater.checkForUpdatesInBackground()
        }
        let changed: (SPUUpdater, Any) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.canCheckForUpdates = self.updater.canCheckForUpdates
                self.checkIfWaiting()
            }
        }
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new], changeHandler: changed),
            updater.observe(\.sessionInProgress, options: [.new], changeHandler: changed),
        ]
    }

    func checkForUpdates() {
        checkWhenReady = true
        checkIfWaiting()
    }

    func installReadyUpdate() {
        guard canQuitNow() else { return }
        installReady?()
    }

    func restartToUpdate() {
        guard canQuitNow() else { return }
        if let installReady { return installReady() }
        guard let available, switching == nil, track == .nightly || !available.isNightly else { return }
        Task {
            do { try await replace(with: available) } catch { checkForUpdates() }
        }
    }

    private func canQuitNow() -> Bool {
        guard let model = AppDelegate.launchModel, let message = model.quitWaitMessage else { return true }
        model.showToast(message)
        return false
    }

    private func checkIfWaiting() {
        guard updater.canCheckForUpdates else { return }
        if checkWhenReady {
            checkWhenReady = false
            checkTrackWhenReady = false
            status = .checking
            updater.checkForUpdates()
        } else if checkTrackWhenReady, !updater.sessionInProgress {
            checkTrackWhenReady = false
            checkingNewTrack = true
            status = .checking
            updater.checkForUpdateInformation()
        }
    }

    private func trackChanged() {
        switchOffer = nil
        if track == .stable {
            driver.endNightlySession()
            if let readyVersion, Channels.isNightly(readyVersion) { dropReadyUpdate() }
            if available?.isNightly == true {
                available = nil
                availableNotes = nil
                if case .available = status { status = .idle }
            }
        }
        guard readyVersion == nil else { return }
        checkTrackWhenReady = true
        checkIfWaiting()
    }

    // MARK: Sparkle's answers

    fileprivate func loaded(_ latest: [Track: Release]) {
        self.latest = latest
    }

    fileprivate func found(_ version: String, release: Release?, notes: ReleaseNotes?) {
        guard track == .nightly || release?.isNightly != true else { return }
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
        guard readyVersion == nil, switching == nil else { return }
        if let release = latest[track], Channels.isOlder(release.build, than: build) { switchOffer = release }
    }

    fileprivate func ready(_ version: String, notes: ReleaseNotes?, install: @escaping () -> Void) {
        guard switching == nil, track == .nightly || !Channels.isNightly(version) else { return dropReadyUpdate() }
        readyVersion = version
        readyNotes = notes
        installReady = install
    }

    fileprivate func finished(error: Error?) {
        checkingNewTrack = false
        let removedInstaller = self.removedInstaller
        self.removedInstaller = false
        guard let error = error as NSError? else { return }
        if removedInstaller, error.domain == SUSparkleErrorDomain, error.code == Int(SUError.installationError.rawValue) { return }
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) {
            if status == .checking { status = .upToDate }
            return
        }
        switch status {
        case .available: break
        case .idle, .checking, .upToDate, .failed: status = .failed(error.localizedDescription)
        }
    }

    private func dropReadyUpdate() {
        readyVersion = nil
        readyNotes = nil
        installReady = nil
        showsReadyNotes = false
        removedInstaller = true
        let remove = Process()
        remove.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        remove.arguments = ["remove", "\(Bundle.main.bundleIdentifier ?? "")-sparkle-updater"]
        try? remove.run()
        remove.waitUntilExit()
    }

    // MARK: Switching

    struct Switching {
        let step: String
        let version: String
        var short: String { "\(step)…" }
        var full: String { "\(step) Cicero \(version)" }
    }

    func switchTo(_ release: Release) async {
        guard readyVersion == nil, switching == nil else { return }
        do {
            try await replace(with: release)
        } catch {
            switchFailure = (release, error.localizedDescription)
        }
    }

    private func replace(with release: Release) async throws {
        switching = Switching(step: "Downloading", version: release.version)
        var staged: URL?
        do {
            let copied = try await VersionSwitch.stage(release) { [weak self] step in self?.switching = Switching(step: step, version: release.version) }
            staged = copied
            guard track == .nightly || !release.isNightly else {
                try? FileManager.default.removeItem(at: copied)
                switching = nil
                return trackChanged()
            }
            switching = Switching(step: "Opening", version: release.version)
            try VersionSwitch.replaceAfterQuit(current: Bundle.main.bundleURL, with: copied)
            NSApp.terminateFromRunLoop(ifCancelled: { [weak self] in
                VersionSwitch.cancelReplace()
                try? FileManager.default.removeItem(at: copied)
                self?.switching = nil
            })
        } catch {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            switching = nil
            guard track == .nightly || !release.isNightly else { return trackChanged() }
            throw error
        }
    }
}

private final class UserDriver: SPUStandardUserDriver {
    private var showsNightly = false
    private var end: (() -> Void)?

    func endNightlySession() {
        guard showsNightly, let end else { return }
        end()
    }

    private func once<T>(_ reply: @escaping (T) -> Void, ending value: T) -> (T) -> Void {
        var replied = false
        let wrapped: (T) -> Void = { [weak self] answer in
            guard !replied else { return }
            replied = true
            self?.end = nil
            reply(answer)
        }
        end = { wrapped(value) }
        return wrapped
    }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        showsNightly = appcastItem.channel == "nightly"
        super.showUpdateFound(with: appcastItem, state: state, reply: once(reply, ending: .dismiss))
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        let cancel = once({ (_: Void) in cancellation() }, ending: ())
        super.showDownloadInitiated(cancellation: { cancel(()) })
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showReady(toInstallAndRelaunch: once(reply, ending: .skip))
    }

    override func dismissUpdateInstallation() {
        end = nil
        showsNightly = false
        super.dismissUpdateInstallation()
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
