import AppKit
import CoreText
import Observation
import PointCore

/// The app's state: the current library snapshot, the user's data and what the windows show.
/// Work happens in PointCore off the main thread; this class applies the results.
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

    // MARK: User data

    var data: UserData {
        didSet {
            guard data != oldValue else { return }
            store.save(data)
            dataRevision &+= 1
            if data.foundryOverrides != oldValue.foundryOverrides || data.foundryRenames != oldValue.foundryRenames
                || data.showSystemFonts != oldValue.showSystemFonts {
                refreshGroups()
            }
            if data.customCharacterSets != oldValue.customCharacterSets { characterSetLookup.reset() }
        }
    }
    /// Bumped on every change to `data`; cached lists depend on it.
    private(set) var dataRevision = 0

    // MARK: Navigation

    var selection: SidebarItem? = .all {
        didSet {
            guard oldValue != selection else { return }
            selectedIDs = []
            openFamilyID = nil
        }
    }
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
    @ObservationIgnored var visibleCache: (key: VisibleKey, families: [Family])?
    @ObservationIgnored let characterSetLookup = CharacterSetLookup()

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
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastScan) > 10 else { return }
                self.rescan()
            }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareToQuit() }
        }
        center.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan(after: 0.5) }
        }
        enqueue { model in
            model.data.records = await model.engine.reconcileTemporary(model.data.records)
        }
        addAppFontFolders()
        rescan()
    }

    /// Adds the folders Adobe apps load fonts from by themselves (found on this Mac), unless they're
    /// already watched or the user removed them before.
    private func addAppFontFolders() {
        let watched = Set(data.folders.map(\.path))
        let new = WatchedFolder.appFontFolders().filter { !watched.contains($0.path) && !data.dismissedFolders.contains($0.path) }
        if !new.isEmpty { data.folders += new }
    }

    private func prepareToQuit() {
        data.records = engine.endUntilQuit(data.records)
        store.flush()
    }

    // MARK: Scanning

    func rescan() {
        scanTask?.cancel()
        lastScan = Date()
        scanProgress = .finding
        let input = ScanInput(folders: data.folders, records: data.records)
        let scanner = scanner
        let report: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                if self.scanProgress != nil { self.scanProgress = progress }
            }
        }
        scanTask = Task { [weak self] in
            do {
                let library = try await scanner.scan(input, progress: report)
                self?.apply(library)
            } catch is CancellationError {
            } catch {
                self?.scanProgress = nil
            }
        }
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

    private func apply(_ new: Library) {
        scanProgress = nil
        hasScanned = true
        guard new.fingerprint != library.fingerprint else { return }
        let old = library
        library = new
        refreshGroups()
        selectedIDs = selectedIDs.filter { new.family($0) != nil }
        if let open = openFamilyID, new.family(open) == nil { openFamilyID = nil }
        FontLoader.shared.invalidate(paths: Self.changedPaths(from: old, to: new))
        FontLoader.shared.prefetch(new.families.map(\.regular.face))
        updateCoverage()
        updateProblems()
    }

    private static func changedPaths(from old: Library, to new: Library) -> Set<String> {
        func faces(_ library: Library) -> [String: [FontFace]] {
            var result: [String: [FontFace]] = [:]
            for family in library.families {
                for face in family.faces { result[face.face.path, default: []].append(face.face) }
            }
            return result
        }
        let before = faces(old)
        let after = faces(new)
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
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
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
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
        for family in library.families where data.showSystemFonts || family.state != .system {
            if let name = foundryName(of: family) { names.insert(name) }
            classifications.insert(family.classification)
        }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if sorted != foundryNames { foundryNames = sorted }
        let present = Classification.allCases.filter(classifications.contains)
        if present != presentClassifications { presentClassifications = present }
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
