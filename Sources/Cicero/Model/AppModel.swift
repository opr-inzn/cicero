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
    @ObservationIgnored let pageContents: PageContents
    @ObservationIgnored let appSets = AppSetWatcher()
    @ObservationIgnored let quickLook = QuickLook()
    @ObservationIgnored let guesser: ClassificationGuesser

    // MARK: Library

    private(set) var library = Library.empty
    private(set) var hasScanned = false
    /// nil when not scanning.
    private(set) var scanProgress: ScanProgress?
    private(set) var problems: [Problem] = []
    /// Bumped whenever coverage results arrive; anything showing coverage depends on it.
    private(set) var coverageRevision = 0
    /// Family → the classification Apple Intelligence guessed from its name (see `ClassificationGuesser`);
    /// `.unclassified` where it couldn't tell.
    private(set) var classificationGuesses: [String: Classification] = [:]
    /// Bumped whenever guesses arrive or go; cached lists depend on it.
    private(set) var guessRevision = 0
    /// nil when coverage is up to date.
    private(set) var coverageProgress: CoverageProgress?
    private(set) var foundryNames: [String] = []
    /// The classifications the sidebar lists: built-in ones with fonts, and the user's.
    private(set) var presentClassifications: [String] = []
    /// Cicero's own folder items that have fonts now (Testing, Adobe Fonts while shown, Added Fonts, Deactivated): the sidebar
    /// lists them.
    private(set) var ownFoldersWithFonts: Set<UUID> = []
    /// Watched folders (and Added Fonts) whose online-only fonts are downloading, and how far along they are.
    var downloads: [UUID: DownloadProgress] = [:]
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
                || data.classifications != oldValue.classifications || data.classificationOverrides != oldValue.classificationOverrides
                || data.classificationRenames != oldValue.classificationRenames || data.showSystemFonts != oldValue.showSystemFonts
                || data.showCreativeCloudFonts != oldValue.showCreativeCloudFonts {
                refreshGroups()
            }
            if !data.showSystemFonts { deselect { $0 == .system } }
            if data.customCharacterSets != oldValue.customCharacterSets { characterSetLookup.reset() }
            if data.tags != oldValue.tags || data.familyTags != oldValue.familyTags || data.tagColors != oldValue.tagColors {
                refreshTagDots()
            }
            if data.showAdobeAppFolders != oldValue.showAdobeAppFolders { rescan() }
        }
    }
    /// Bumped on every change to `data` but the sidebar's choices; cached lists depend on it.
    private(set) var dataRevision = 0
    /// Settings → General → Guess classifications from names (see `ClassificationGuesser`). Saved in user defaults.
    var guessesClassifications: Bool {
        didSet {
            guard guessesClassifications != oldValue else { return }
            UserDefaults.standard.set(guessesClassifications, forKey: Self.guessesClassificationsKey)
            if guessesClassifications {
                guessClassifications()
            } else {
                // Turned on again, it asks again.
                guesser.forget()
                guessesChanged()
            }
        }
    }
    static let guessesClassificationsKey = "classification.guessesFromNames"
    /// Family → the colours of its tags, for the dots next to its name. Apart from `data`, so tiles and rows
    /// don't draw again for every change to it.
    private(set) var tagDots: [String: [TagColor]] = [:]

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
    /// Families for the browser to go to, as after installing fonts: it selects the first of them in the order it shows
    /// them, brings it into view, and clears this.
    var jumpTargets: Set<String>?
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
    /// A switch to other copies that turns off more styles than it moves, waiting for the user to agree.
    var copySwitchPrompt: CopySwitchRequest?
    var trashPlan: TrashPlan?
    var textPrompt: TextPrompt?
    var newTagRequest: NewTagRequest?
    var editingSmartSet: SmartSet?
    /// The set whose apps the application set sheet shows.
    var editingAppsForSet: UUID?
    var editingCharacterSet: CustomCharacterSet?
    /// The coverage set the sidebar asks about deleting.
    var deletingCharacterSet: CustomCharacterSet?
    var isClearingCaches = false
    /// The document whose fonts the Fonts in Document sheet shows.
    var documentFonts: DocumentFontsReport?
    @ObservationIgnored var documentMatchesCache: (report: UUID, fingerprint: Int, matches: [DocumentFontMatch])?
    private(set) var toast: String?

    // MARK: Compare

    /// What Compare shows, in order: families, each in a style, some more than once in other styles.
    var compareEntries: [CompareEntry] = []

    // MARK: Opening files

    /// Files and folders opened or dropped, gathered for a moment so several arriving one by one are added together.
    @ObservationIgnored var openQueue: (urls: [URL], set: UUID?, task: Task<Void, Never>?) = ([], nil, nil)
    /// Files the browser shows once the scan that lists them is done.
    @ObservationIgnored var awaitingScan: OpenedFiles?

    // MARK: Private

    @ObservationIgnored private(set) var started = false
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
    @ObservationIgnored private lazy var folderWatcher = FolderWatcher { [weak self] changed in
        MainActor.assumeIsolated { self?.fontsChanged(changed) }
    }
    /// The files that changed since the last scan started, for the next one to look at instead of every folder;
    /// nil when it has to look at everything.
    @ObservationIgnored private var pendingChanges: Set<String>? = []
    /// The running scan's number and the files it looks at, nil for all of them.
    @ObservationIgnored private var runningScan: (id: Int, changes: Set<String>?)?
    /// Files a watched folder said changed while a scan of everything was running, looked at again once it's done
    /// (see `rescan`).
    @ObservationIgnored private var changedDuringScan: Set<String> = []
    /// A scan of everything a while after a file came or went in a Fonts folder, to see what macOS made of it.
    @ObservationIgnored private var fontsFolderCheck: Task<Void, Never>?
    @ObservationIgnored var visibleCache: (key: VisibleKey, families: [Family])?
    @ObservationIgnored var fontRowsCache: (key: FontRowsKey, rows: [FontRow], families: [Family])?
    @ObservationIgnored let characterSetLookup = CharacterSetLookup()
    @ObservationIgnored var customSetsCache: (sets: [CustomCharacterSet], definitions: [CharacterSetDefinition])?
    /// The sidebar items the last scan found, as saved for the next launch.
    @ObservationIgnored private var savedGroups: ScannedGroups?

    init() {
        let locations = Locations.standard
        scanner = LibraryScanner(locations: locations)
        store = UserDataStore(locations: locations)
        engine = ActivationEngine(locations: locations)
        languages = LanguageCatalog(contentsOf: Bundle.main.url(forResource: "Languages", withExtension: "json"))
        characterSetCatalog = CharacterSetCatalog(contentsOf: Bundle.main.url(forResource: "CharacterSets", withExtension: "json"))
        coverage = CoverageIndex(caches: locations.caches, languages: languages)
        pageContents = PageContents(coverage: coverage)
        guesser = ClassificationGuesser(caches: locations.caches)
        guessesClassifications = UserDefaults.standard.object(forKey: Self.guessesClassificationsKey) as? Bool ?? true
        data = store.load()
        if guessesClassifications { classificationGuesses = guesser.guesses }
        refreshTagDots()
        restoreGroups()
        restoreLibrary()
        begin()
    }

    // MARK: Lifecycle

    /// At launch, before the window is made: the first scan runs meanwhile, and the window shows the library the
    /// last one found until it's done.
    private func begin() {
        let center = NotificationCenter.default
        // Font changes and the watched folders are followed as they happen; this catches anything they miss,
        // like folders on network disks.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Not while a scan of everything is running, which would start over (a long one never finishing).
                guard let self, Date().timeIntervalSince(self.lastScan) > 60, self.runningScan.map({ $0.changes != nil }) ?? true else { return }
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

    /// Once the main window is there: files opened before it are added now.
    func start() {
        guard !started else { return }
        started = true
        openWaitingFiles()
    }

    /// The library as the last scan found it, so the window opens with the fonts in it rather than empty until
    /// this launch's first scan, which replaces it (see `apply`).
    private func restoreLibrary() {
        guard let saved = scanner.savedLibrary(records: data.records) else { return }
        library = saved
        // What the browser shows first, then everything else.
        FontLoader.shared.prefetch((visibleFamilies + saved.families).map(\.regular.face))
    }

    /// Adobe's font folders used to be added to the user's folders; the Testing switch covers them now.
    private func dropAdobeFolders() {
        data.folders.removeAll { WatchedFolder.detectAppName(forPath: $0.path) != nil }
    }

    private func prepareToQuit() {
        data.records = engine.endUntilQuit(data.records)
        store.flush()
    }

    // MARK: Scanning

    /// Returns the scan's number. With `changes`, only those files are looked at again (see `LibraryScanner.scan`).
    @discardableResult
    func rescan(changes: Set<String>? = nil) -> Int {
        // Files that change while a scan of everything runs are looked at once it's done, rather than starting it over:
        // a long one would never finish while a folder kept changing, and it may not have got to them yet.
        if let changes, let running = runningScan, running.changes == nil {
            pendingChanges = []
            changedDuringScan.formUnion(changes)
            return running.id
        }
        // A scan this one replaces is cancelled, so this one looks at whatever that one would have.
        var changes = changes.map { $0.union(changedDuringScan) }
        changedDuringScan = []
        if let running = runningScan { changes = running.changes.flatMap { looked in changes?.union(looked) } }
        pendingChanges = []
        scanTask?.cancel()
        if changes == nil { lastScan = Date() }
        scanCount += 1
        let id = scanCount
        runningScan = (id, changes)
        let input = ScanInput(folders: data.scannedFolders(), files: data.fontFiles, records: data.records)
        // The Fonts folders too, so a font dropped into one shows without waiting for macOS to register it.
        let fontsFolders = [locations.userFonts.path, locations.allUsersFonts.path]
        folderWatcher.watch(fontsFolders + input.folders.map(\.path), files: input.files, hidden: [locations.adobeFontsInAdobeApps?.path].compactMap { $0 })
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
                let library = try await scanner.scan(input, changes: changes, progress: report)
                // A scan that was replaced can finish anyway, even after the one that replaced it: what it found is out of date.
                guard !Task.isCancelled else { return }
                self?.finishScan(id)
                self?.apply(library, scan: id)
            } catch is CancellationError {
            } catch {
                self?.finishScan(id)
                self?.endScan(id)
            }
        }
        return id
    }

    private func finishScan(_ id: Int) {
        guard runningScan?.id == id else { return }
        runningScan = nil
        if !changedDuringScan.isEmpty { scheduleRescan(after: 0) }
    }

    private func endScan(_ id: Int) {
        if scanCount == id {
            revealProgress?.cancel()
            scanProgress = nil
        }
        dropExpectations(confirmedBy: id)
        mergeExpectations()
        showOpenedFiles(after: id)
    }

    /// CoreText's fonts-changed notification, or font files coming or going in a watched folder.
    /// During an operation (whose own changes set these off) they wait for the scan the operation starts
    /// when it finishes; `enqueue` scans afterwards when it started none.
    /// `changed` are the files a watched folder says changed, nil for anything. Those few are looked at again
    /// almost at once; anything else waits a little, as CoreText's notifications tend to come in bursts.
    private func fontsChanged(_ changed: Set<String>? = nil) {
        if runningOperations > 0 {
            if changeSeenBeforeScan == nil { changeSeenBeforeScan = scanCount }
            return
        }
        if let changed, let pending = pendingChanges { pendingChanges = pending.union(changed) } else { pendingChanges = nil }
        scheduleRescan(after: pendingChanges == nil ? 0.3 : 0.05)
        // A font put in a Fonts folder shows as on at once, though macOS takes a few seconds to turn it on and
        // says so with a notification that scans everything; this scan comes in case it says nothing, as
        // when it doesn't take the font.
        let fontsFolders = [locations.userFonts.path + "/", locations.allUsersFonts.path + "/"]
        if let changed, changed.contains(where: { path in fontsFolders.contains { path.hasPrefix($0) } }) {
            fontsFolderCheck?.cancel()
            fontsFolderCheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.fontsChanged()
            }
        }
    }

    /// The scan looks only at the files changed meanwhile, if it can.
    private func scheduleRescan(after delay: Double) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.rescan(changes: self.pendingChanges)
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
        // The library restored at launch always gives way to the first scan's, and prefetches, coverage and problems
        // start from that one.
        let first = !hasScanned
        hasScanned = true
        // Also when nothing changed, in case Apple Intelligence was turned on meanwhile.
        defer { guessClassifications() }
        // Added files that are gone leave the library: nothing would show them, and looking for them every time
        // touches their folder, which may be one macOS asks about, like Downloads.
        if !new.goneFiles.isEmpty { data.fontFiles.removeAll(where: new.goneFiles.contains) }
        guard first || new.fingerprint != library.fingerprint else { return endScan(id) }
        let known = Set(library.families.lazy.flatMap(\.faces).map(\.face.path))
        let offline = library.offlinePaths
        library = new
        activateAddedFonts(knowing: known, offline: offline)
        endScan(id)
        refreshGroups()
        selectedIDs = selectedIDs.filter { new.family($0) != nil }
        if let open = openFamilyID, new.family(open) == nil { openFamilyID = nil }
        FontLoader.shared.invalidate(paths: new.changedPaths)
        pageContents.forget(paths: new.changedPaths)
        // What the browser shows first, then everything else.
        FontLoader.shared.prefetch((visibleFamilies + new.families).map(\.regular.face))
        updateCoverage()
        updateProblems()
    }

    /// Fonts in Active folders that weren't in the library before this scan, like files just put in one. Those that were
    /// only out of reach, on a disk that was ejected say, are back as they were: on if Cicero had them on, off if they were
    /// turned off. With nothing to compare against (no saved library at launch), none: a font turned off by hand would
    /// come back on.
    private func activateAddedFonts(knowing known: Set<String>, offline: Set<String>) {
        let active = data.folders.filter(\.isActive)
        guard !active.isEmpty, !known.isEmpty || !offline.isEmpty else { return }
        keepOn(faces(in: active).filter { face in
            let path = face.face.path
            return !known.contains(path) && (!offline.contains(path) || data.records.inPlace.contains(path))
        })
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

    private func refreshTagDots() {
        var dots: [String: [TagColor]] = [:]
        for family in data.familyTags.keys {
            let colors = data.tags(of: family).compactMap { data.tagColors[$0] }
            if !colors.isEmpty { dots[family] = colors }
        }
        if dots != tagDots { tagDots = dots }
    }

    /// Asks Apple Intelligence about the families nothing classifies, when it's on and the setting is.
    private func guessClassifications() {
        guard guessesClassifications else { return }
        // A family whose letters disagree is unclassified for a reason the name can't undo.
        let open = library.families.filter { $0.classification == .unclassified && !$0.mixesSerifAndSans }
        guesser.guess(open) { [weak self] in self?.guessesChanged() }
    }

    private func guessesChanged() {
        classificationGuesses = guesser.guesses
        guessRevision &+= 1
        refreshGroups()
    }

    private func refreshGroups() {
        // Until the first scan, the sidebar lists what the last one found (see `restoreGroups`).
        guard hasScanned else { return }
        var names = Set<String>()
        var classifications = Set<String>()
        var ownFolders = Set<UUID>()
        let foundryName = foundryNamer()
        let classificationName = classificationNamer()
        for family in library.families {
            if family.folderIDs.contains(WatchedFolder.adobeAppsID) { ownFolders.insert(WatchedFolder.adobeAppsID) }
            if data.showCreativeCloudFonts, family.folderIDs.contains(WatchedFolder.adobeFontsID) { ownFolders.insert(WatchedFolder.adobeFontsID) }
            if family.folderIDs.contains(WatchedFolder.deactivatedID) { ownFolders.insert(WatchedFolder.deactivatedID) }
            if family.folderIDs.contains(WatchedFolder.addedFilesID) { ownFolders.insert(WatchedFolder.addedFilesID) }
            guard data.lists(family) else { continue }
            if let name = foundryName(family) { names.insert(name) }
            classifications.insert(classificationName(family))
        }
        // Added fonts that are all online only still have their item, to download them from.
        if library.onlineOnlyFiles[WatchedFolder.addedFilesID] != nil { ownFolders.insert(WatchedFolder.addedFilesID) }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if sorted != foundryNames { foundryNames = sorted }
        // Built-in ones with fonts and the user's, even without; Unclassified, what's left, last.
        let builtIn = Classification.allCases.filter { $0 != .unclassified }.map(name(of:)).filter(classifications.contains)
        let present = builtIn + data.classifications + [name(of: .unclassified)].filter(classifications.contains)
        if present != presentClassifications { presentClassifications = present }
        if ownFolders != ownFoldersWithFonts {
            // One that's emptied, like Added Fonts once its fonts are installed, leaves the sidebar; shown, All Fonts
            // takes its place.
            let emptied = ownFoldersWithFonts.subtracting(ownFolders)
            ownFoldersWithFonts = ownFolders
            deselect { if case .folder(let id) = $0 { emptied.contains(id) } else { false } }
        }
        let groups = ScannedGroups(ownFolders: ownFolders, foundries: sorted, classifications: present)
        if groups != savedGroups {
            savedGroups = groups
            UserDefaults.standard.set(try? JSONEncoder().encode(groups), forKey: ScannedGroups.defaultsKey)
        }
    }

    /// The sidebar items a scan finds (Cicero's own folders, foundries and classifications) as the last scan
    /// found them, so the window opens with them in place rather than having them appear a moment later.
    private func restoreGroups() {
        guard let saved = UserDefaults.standard.data(forKey: ScannedGroups.defaultsKey),
              let groups = try? JSONDecoder().decode(ScannedGroups.self, from: saved) else { return }
        savedGroups = groups
        ownFoldersWithFonts = groups.ownFolders
        foundryNames = groups.foundries
        presentClassifications = groups.classifications
    }
}

/// What `refreshGroups` last found, kept for the next launch.
private struct ScannedGroups: Codable, Equatable {
    static let defaultsKey = "sidebar.scannedGroups"
    var ownFolders: Set<UUID>
    var foundries: [String]
    var classifications: [String]
}

struct CoverageProgress: Equatable {
    var done: Int
    var total: Int
}

struct DownloadProgress: Equatable {
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
    /// Set when the faces are copies taking over from others.
    var switching: CopySwitchRequest?
}

/// Using a place's copies of some styles (see `AppModel.useCopies`).
struct CopySwitchRequest: Identifiable {
    let id = UUID()
    /// The place's name: "Acme".
    var source: String
    /// What the activation sheet calls it: "Helvetica from Acme".
    var title: String
    var plan: CopySwitchPlan
}

struct DeactivationPrompt: Identifiable {
    let id = UUID()
    var faces: [LibraryFace]
    var unmanagedCount: Int
}

/// New Tag…: the families that get the tag, and the colour the sheet starts with.
struct NewTagRequest: Identifiable {
    let id = UUID()
    var families: [Family]
    var color: TagColor?
}

struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var initialText: String
    var confirmTitle: String
    var action: (String) -> Void
}
