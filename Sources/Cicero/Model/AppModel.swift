import AppKit
import CoreText
import Observation
import CiceroCore

/// The app's state: the current library snapshot, the user's data and what the windows show.
/// Work happens in CiceroCore off the main thread; this class applies the results.
@Observable
final class AppModel {
    // MARK: Services

    @ObservationIgnored let locations = Locations.standard
    @ObservationIgnored let scanner: LibraryScanner
    @ObservationIgnored let store: UserDataStore
    @ObservationIgnored let engine: ActivationEngine
    @ObservationIgnored let languages: LanguageCatalog
    @ObservationIgnored let characterSetCatalog: CharacterSetCatalog
    @ObservationIgnored let coverage: CoverageIndex
    @ObservationIgnored let appSets = AppSetWatcher()

    // MARK: Library

    private(set) var library = Library.empty
    private(set) var hasScanned = false
    /// nil when not scanning.
    private(set) var scanProgress: ScanProgress?
    private(set) var problems: [Problem] = []
    /// Bumped whenever coverage results arrive; anything showing coverage depends on it.
    private(set) var coverageRevision = 0
    /// nil when coverage is up to date.
    private(set) var coverageProgress: CoverageProgress?
    private(set) var foundryNames: [String] = []
    private(set) var presentClassifications: [Classification] = []
    /// Cicero's own folder items that have fonts now (Adobe Apps, Deactivated): the sidebar lists them.
    private(set) var ownFoldersWithFonts: Set<UUID> = []
    /// Where operations in progress will put switches, shown from the click until the scan after the
    /// operation confirms it (see `expect`).
    private(set) var expectedFamilyPositions: [String: SwitchPosition] = [:]
    private(set) var expectedFacePositions: [FaceID: SwitchPosition] = [:]

    // MARK: User data

    var data: UserData {
        didSet {
            guard data != oldValue else { return }
            store.save(data)
            // No list of families depends on the sidebar's choices: opening a section, or moving or hiding a
            // row, leaves the browser's list as it is instead of making and sorting it again.
            if data.sidebar == oldValue.sidebar || data.differs(besidesSidebar: oldValue) { dataRevision &+= 1 }
            if data.foundryOverrides != oldValue.foundryOverrides || data.foundryRenames != oldValue.foundryRenames
                || data.showSystemFonts != oldValue.showSystemFonts {
                refreshGroups()
            }
            if !data.showSystemFonts { deselect { $0 == .system } }
            if data.customCharacterSets != oldValue.customCharacterSets { characterSetLookup.reset() }
            if data.showAdobeFonts != oldValue.showAdobeFonts { rescan() }
        }
    }
    /// Bumped on every change to `data` but the sidebar's choices; cached lists depend on it.
    private(set) var dataRevision = 0

    // MARK: Navigation

    /// The sidebar item the browser's title and empty states follow. Setting it selects just that item.
    var selection: SidebarItem? = .all {
        didSet {
            let items: Set<SidebarItem> = selection.map { [$0] } ?? []
            if selectedItems != items { selectedItems = items }
            guard oldValue != selection else { return }
            selectedIDs = []
            openFamilyID = nil
        }
    }
    /// Every selected sidebar item, `selection` among them; the browser shows the fonts in any of them.
    /// Change it with `selectSidebarItems`, which keeps several to one list of the sidebar.
    var selectedItems: Set<SidebarItem> = [.all]
    var selectedIDs: Set<String> = []
    /// The family whose page is pushed over the browser.
    var openFamilyID: String?
    var searchText = "" {
        didSet { scheduleSearch() }
    }
    /// The search lists filter by: follows `searchText` after a short pause.
    private(set) var appliedSearch = ""
    var isEditingSidebar = false
    var isInfoPresented = false
    var infoTab: InfoTab = .info
    /// OpenType features chosen in the Info panel, per family, applied wherever it's previewed.
    var familyFeatures: [String: [FeatureSetting]] = [:]

    // MARK: Prompts

    var activationPrompt: ActivationPrompt?
    var deactivationPrompt: DeactivationPrompt?
    var trashPlan: TrashPlan?
    var textPrompt: TextPrompt?
    var editingSmartSet: SmartSet?
    /// The set whose apps the application set sheet shows.
    var editingAppsForSet: UUID?
    var editingCharacterSet: CustomCharacterSet?
    var isClearingCaches = false
    private(set) var toast: String?

    // MARK: Compare

    var compareIDs: [String] = []

    // MARK: Private

    @ObservationIgnored private var started = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var coverageTask: Task<Void, Never>?
    @ObservationIgnored private var problemsTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Activation, deactivation and trashing run one at a time, so their record changes never overwrite each other.
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var lastScan = Date.distantPast
    /// Numbers scans as they start, so results and expectations can tell which came first.
    @ObservationIgnored private var scanCount = 0
    @ObservationIgnored private var revealProgress: Task<Void, Never>?
    /// The last progress a scan reported, shown once the scan has taken long enough to mention.
    @ObservationIgnored private var latestProgress: ScanProgress?
    @ObservationIgnored private var runningOperations = 0
    /// The scan that was the latest when a font change came in during an operation; the change is left to a
    /// scan that starts after it, which the operation usually starts itself.
    @ObservationIgnored private var changeSeenBeforeScan: Int?
    @ObservationIgnored private var operationCount = 0
    @ObservationIgnored private var expectations: [Expectation] = []
    @ObservationIgnored private lazy var folderWatcher = FolderWatcher { [weak self] in
        MainActor.assumeIsolated { self?.fontsChanged() }
    }
    @ObservationIgnored var visibleCache: (key: VisibleKey, families: [Family])?
    @ObservationIgnored var fontRowsCache: (key: FontRowsKey, rows: [FontRow])?
    @ObservationIgnored let characterSetLookup = CharacterSetLookup()
    @ObservationIgnored var customSetsCache: (sets: [CustomCharacterSet], definitions: [CharacterSetDefinition])?

    init() {
        let locations = Locations.standard
        scanner = LibraryScanner(locations: locations)
        store = UserDataStore(locations: locations)
        engine = ActivationEngine(locations: locations)
        languages = LanguageCatalog(contentsOf: Bundle.main.url(forResource: "Languages", withExtension: "json"))
        characterSetCatalog = CharacterSetCatalog(contentsOf: Bundle.main.url(forResource: "CharacterSets", withExtension: "json"))
        coverage = CoverageIndex(caches: locations.caches, languages: languages)
        data = store.load()
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        // Font changes and the watched folders are followed as they happen; this catches anything they miss,
        // like folders on network disks.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastScan) > 60 else { return }
                self.rescan()
            }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareToQuit() }
        }
        // Posted to this process's own center when any app, Cicero included, changes the registered fonts.
        center.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fontsChanged() }
        }
        enqueue { model in
            model.data.records = await model.engine.reconcileTemporary(model.data.records)
        }
        dropAdobeFolders()
        rescan()
    }

    /// Adobe's font folders used to be added to the user's folders; the Adobe Apps switch covers them now.
    private func dropAdobeFolders() {
        data.folders.removeAll { WatchedFolder.detectAppName(forPath: $0.path) != nil }
    }

    private func prepareToQuit() {
        data.records = engine.endUntilQuit(data.records)
        store.flush()
    }

    // MARK: Scanning

    /// Returns the scan's number.
    @discardableResult
    func rescan() -> Int {
        scanTask?.cancel()
        lastScan = Date()
        scanCount += 1
        let id = scanCount
        let input = ScanInput(folders: data.scannedFolders(), records: data.records)
        folderWatcher.watch(input.folders.map(\.path))
        // Most scans take a fraction of a second; the capsule only shows for one that takes longer.
        latestProgress = .finding
        revealProgress?.cancel()
        revealProgress = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.scanCount == id else { return }
            self.scanProgress = self.latestProgress
        }
        let scanner = scanner
        let report: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard self.scanCount == id else { return }
                self.latestProgress = progress
                if self.scanProgress != nil { self.scanProgress = progress }
            }
        }
        scanTask = Task { [weak self] in
            do {
                let library = try await scanner.scan(input, progress: report)
                self?.apply(library, scan: id)
            } catch is CancellationError {
            } catch {
                self?.endScan(id)
            }
        }
        return id
    }

    private func endScan(_ id: Int) {
        if scanCount == id {
            revealProgress?.cancel()
            scanProgress = nil
        }
        dropExpectations(confirmedBy: id)
        mergeExpectations()
    }

    /// CoreText's fonts-changed notification, or font files coming or going in a watched folder.
    /// During an operation (whose own changes set these off) they wait for the scan the operation starts
    /// when it finishes; `enqueue` scans afterwards when it started none.
    private func fontsChanged() {
        if runningOperations > 0 {
            if changeSeenBeforeScan == nil { changeSeenBeforeScan = scanCount }
            return
        }
        scheduleRescan(after: 0.3)
    }

    func scheduleRescan(after delay: Double) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    /// Re-reads every font file instead of using cached details.
    func rebuildFontList() {
        scanner.clearCache()
        coverage.clearCache()
        rescan()
    }

    private func apply(_ new: Library, scan id: Int) {
        let signpost = Signposts.library.beginInterval("Apply")
        defer { Signposts.library.endInterval("Apply", signpost) }
        hasScanned = true
        guard new.fingerprint != library.fingerprint else { return endScan(id) }
        library = new
        endScan(id)
        refreshGroups()
        selectedIDs = selectedIDs.filter { new.family($0) != nil }
        if let open = openFamilyID, new.family(open) == nil { openFamilyID = nil }
        FontLoader.shared.invalidate(paths: new.changedPaths)
        // What the browser shows first, then everything else.
        FontLoader.shared.prefetch((visibleFamilies + new.families).map(\.regular.face))
        updateCoverage()
        updateProblems()
    }

    private func updateCoverage() {
        coverageTask?.cancel()
        let families = library.families
        let coverage = coverage
        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            guard let self else { return }
            Task { @MainActor in
                self.coverageProgress = CoverageProgress(done: done, total: total)
                // Lists that depend on coverage refill as results arrive, not on every face.
                if done == total || done % 200 == 0 { self.coverageRevision &+= 1 }
            }
        }
        coverageTask = Task { [weak self] in
            await coverage.update(families, progress: report)
            guard !Task.isCancelled, let self else { return }
            self.coverageProgress = nil
            self.coverageRevision &+= 1
            self.characterSetLookup.reset()
        }
    }

    func updateProblems() {
        problemsTask?.cancel()
        let library = library
        let data = data
        let locations = locations
        problemsTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                ProblemDetector.detect(in: library, data: data, locations: locations)
            }.value
            guard !Task.isCancelled, let self, found != self.problems else { return }
            self.problems = found
        }
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !searchText.isEmpty else {
            appliedSearch = ""
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.appliedSearch != self.searchText else { return }
            self.appliedSearch = self.searchText
        }
    }

    // MARK: Operations

    /// Runs an activation-type operation after the previous one has finished.
    func enqueue(_ work: @escaping (AppModel) async -> Void) {
        let previous = operation
        runningOperations += 1
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
            self.runningOperations -= 1
            if let seen = self.changeSeenBeforeScan, self.runningOperations == 0 {
                self.changeSeenBeforeScan = nil
                if self.scanCount == seen { self.rescan() }
            }
        }
    }

    // MARK: Expected positions

    private struct Expectation {
        var operation: Int
        var faces: [FaceID: SwitchPosition]
        var families: Set<String>
        /// The scan the operation started when it finished; nil while it runs.
        var scan: Int?
    }

    /// Moves the switches of these faces and their families to `position` at once, ahead of the
    /// operation that puts them there. Returns the number `finish` takes to have the next scan confirm it.
    func expect(_ faces: [LibraryFace], at position: SwitchPosition) -> Int {
        operationCount += 1
        expectations.append(Expectation(
            operation: operationCount, faces: Dictionary(faces.map { ($0.id, position) }) { a, _ in a },
            families: Set(faces.map(\.face.familyName))
        ))
        mergeExpectations()
        return operationCount
    }

    /// The operation is done; the scan `id` shows what it did.
    func settle(_ operation: Int, after id: Int) {
        for index in expectations.indices where expectations[index].operation == operation {
            expectations[index].scan = id
        }
    }

    private func dropExpectations(confirmedBy id: Int) {
        expectations.removeAll { ($0.scan ?? .max) <= id }
    }

    /// The faces' expected positions, latest operation last, and their families' positions worked out
    /// from the current library: an earlier operation that failed doesn't linger in a later one's family.
    private func mergeExpectations() {
        var faces: [FaceID: SwitchPosition] = [:]
        var names = Set<String>()
        for expectation in expectations {
            faces.merge(expectation.faces) { _, new in new }
            names.formUnion(expectation.families)
        }
        var families: [String: SwitchPosition] = [:]
        for name in names {
            if let family = library.family(name) { families[name] = family.position(overriding: faces) }
        }
        if families != expectedFamilyPositions { expectedFamilyPositions = families }
        if faces != expectedFacePositions { expectedFacePositions = faces }
    }

    func position(of family: Family) -> SwitchPosition {
        expectedFamilyPositions[family.id] ?? family.position
    }

    func position(of face: LibraryFace) -> SwitchPosition {
        expectedFacePositions[face.id] ?? face.position
    }

    // MARK: Toasts

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Groups

    private func refreshGroups() {
        var names = Set<String>()
        var classifications = Set<Classification>()
        var ownFolders = Set<UUID>()
        let foundryName = foundryNamer()
        for family in library.families {
            if family.folderIDs.contains(WatchedFolder.adobeAppsID) { ownFolders.insert(WatchedFolder.adobeAppsID) }
            if family.folderIDs.contains(WatchedFolder.deactivatedID) { ownFolders.insert(WatchedFolder.deactivatedID) }
            guard data.showSystemFonts || family.state != .system else { continue }
            if let name = foundryName(family) { names.insert(name) }
            classifications.insert(family.classification)
        }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if sorted != foundryNames { foundryNames = sorted }
        let present = Classification.allCases.filter(classifications.contains)
        if present != presentClassifications { presentClassifications = present }
        if ownFolders != ownFoldersWithFonts { ownFoldersWithFonts = ownFolders }
    }
}

struct CoverageProgress: Equatable {
    var done: Int
    var total: Int
}

enum InfoTab: String, CaseIterable {
    case info = "Info"
    case features = "Features"
}

struct ActivationPrompt: Identifiable {
    let id = UUID()
    var title: String
    var faces: [LibraryFace]
}

struct DeactivationPrompt: Identifiable {
    let id = UUID()
    var faces: [LibraryFace]
    var unmanagedCount: Int
}

struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var initialText: String
    var confirmTitle: String
    var action: (String) -> Void
}
