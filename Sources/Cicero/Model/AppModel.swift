import AppKit
import CoreText
import Observation
import CiceroCore

@Observable
final class AppModel {
    // MARK: Services

    @ObservationIgnored let locations = Locations.standard
    @ObservationIgnored let scanner: LibraryScanner
    @ObservationIgnored let store: UserDataStore
    @ObservationIgnored private let appLock: AppLock?
    @ObservationIgnored private var commandRequests: CommandRequests?
    @ObservationIgnored private(set) var lastEndedScan = 0
    @ObservationIgnored private let launchEngine: ActivationEngine
    @ObservationIgnored let languages: LanguageCatalog
    @ObservationIgnored let scriptSamples: ScriptSamples
    @ObservationIgnored let characterSetCatalog: CharacterSetCatalog
    @ObservationIgnored let coverage: CoverageIndex
    @ObservationIgnored let measurements: MeasurementIndex
    @ObservationIgnored let pageContents: PageContents
    @ObservationIgnored let pageFeatures = PageFeatures()
    @ObservationIgnored let appSets = AppSetWatcher()
    @ObservationIgnored let openDocumentFonts = DocumentFontWatcher()
    @ObservationIgnored let quickLook = QuickLook()
    @ObservationIgnored let guesser: ClassificationGuesser

    var engine: ActivationEngine {
        var engine = launchEngine
        engine.fontLibrary = data.fontLibrary?.url
        engine.installsIntoFontLibrary = data.installsIntoFontLibrary
        return engine
    }

    var importEngine: ActivationEngine {
        var engine = engine
        engine.appFontFolders = library.appFontFolders
        return engine
    }

    // MARK: Library

    private(set) var library: Library {
        get {
            access(keyPath: \.library)
            if restoring != nil { finishRestoring() }
            return storedLibrary
        }
        set {
            if restoring != nil { finishRestoring() }
            withMutation(keyPath: \.library) { storedLibrary = newValue }
        }
    }
    @ObservationIgnored private var storedLibrary = Library.empty
    @ObservationIgnored private var restoring: SavedLibraryRead?
    private(set) var hasScanned = false
    private(set) var scanProgress: ScanProgress?
    private(set) var problems: [Problem] = []
    private(set) var coverageRevision = 0
    private(set) var classificationGuesses: [String: Classification] = [:]
    private(set) var letterGuesses: [String: Classification] = [:]
    private(set) var guessRevision = 0
    private(set) var coverageProgress: CoverageProgress?
    private(set) var measurementRevision = 0
    private(set) var measurementProgress: CoverageProgress?
    private(set) var foundryNames: [String] = []
    private(set) var presentClassifications: [String] = []
    private(set) var ownFoldersWithFonts: Set<UUID> = []
    var downloads: [UUID: DownloadProgress] = [:]
    private(set) var expectedFamilyPositions: [String: SwitchPosition] = [:]
    private(set) var expectedFacePositions: [FaceID: SwitchPosition] = [:]

    // MARK: User data

    var data: UserData {
        didSet {
            guard data != oldValue else { return }
            // Kept as it was saved: a newer Cicero's data, written by this one, would lose what only the newer one knows.
            if store.isReadOnly {
                // Setting it here runs this observer again: an @Observable property's didSet isn't skipped for a set from inside it.
                guard !revertingData else { return }
                revertingData = true
                data = oldValue
                revertingData = false
                return showToast(store.readOnlyMessage)
            }
            store.save(data)
            // The activation records at once: macOS has the change already, and a Cicero that stopped in that moment (killed, crashed, the Mac switched off) would find fonts on that it didn't know it had turned on, and those on until it quits left on.
            if data.records != oldValue.records { store.flush() }
            if data.sidebar == oldValue.sidebar || data.differs(besidesSidebar: oldValue) { dataRevision &+= 1 }
            if data.foundryOverrides != oldValue.foundryOverrides || data.foundryRenames != oldValue.foundryRenames
                || data.classifications != oldValue.classifications || data.classificationOverrides != oldValue.classificationOverrides
                || data.classificationRenames != oldValue.classificationRenames || data.showSystemFonts != oldValue.showSystemFonts
                || data.showCreativeCloudFonts != oldValue.showCreativeCloudFonts {
                refreshGroups()
            }
            if !data.showSystemFonts, oldValue.showSystemFonts { deselect { $0 == .system } }
            if data.customCharacterSets != oldValue.customCharacterSets { characterSetLookup.reset() }
            if data.tags != oldValue.tags || data.familyTags != oldValue.familyTags || data.tagColors != oldValue.tagColors {
                refreshTagDots()
            }
            if data.showAdobeAppFolders != oldValue.showAdobeAppFolders { rescan() }
            if data.activatesDocumentFonts != oldValue.activatesDocumentFonts { openDocumentFonts.settingChanged() }
        }
    }
    private(set) var dataRevision = 0
    @ObservationIgnored private var revertingData = false
    var guessesClassifications: Bool {
        didSet {
            guard guessesClassifications != oldValue else { return }
            UserDefaults.standard.set(guessesClassifications, forKey: Self.guessesClassificationsKey)
            if asksAboutGuessing {
                UserDefaults.standard.removeObject(forKey: Self.asksAboutGuessingKey)
                asksAboutGuessing = false
                showsGuessingQuestion = false
            }
            if guessesClassifications {
                guessClassifications()
            } else {
                guesser.forget()
            }
            guessesChanged()
        }
    }
    static let guessesClassificationsKey = ClassificationGuesses.guessingKey
    private(set) var asksAboutGuessing = false
    var showsGuessingQuestion = false
    static let asksAboutGuessingKey = ClassificationGuesses.askingKey
    private(set) var tagDots: [String: [TagColor]] = [:]

    // MARK: Navigation

    var selection: SidebarItem? = .all {
        didSet {
            if selection != nil, similarFamilyID != nil { similarFamilyID = nil }
            if selection != nil, documentList != nil { documentList = nil }
            let items: Set<SidebarItem> = selection.map { [$0] } ?? []
            if selectedItems != items { selectedItems = items }
            guard oldValue != selection else { return }
            selectedIDs = []
            openFamilyID = nil
        }
    }
    var selectedItems: Set<SidebarItem> = [.all]
    var selectedIDs: Set<String> = []
    var openFamilyID: String? {
        didSet {
            if openFamilyID != oldValue {
                pageStyleID = nil
                pageFeatures.forget()
            }
        }
    }
    var pageStyleID: FaceID?
    var similarFamilyID: String? {
        didSet { if similarFamilyID != oldValue { similarStyleID = nil } }
    }
    var similarStyleID: FaceID?
    var documentList: DocumentList?
    var jumpTargets: Set<String>?
    var searchText = "" {
        didSet {
            scheduleSearch()
            if !searchText.isEmpty { lastTyped = searchText }
        }
    }
    private(set) var appliedSearch = ""
    private(set) var searchTokens: [SearchToken] = []
    @ObservationIgnored var lastTyped = ""
    var isEditingSidebar = false
    var isInfoPresented = false
    var infoTab: InfoTab = .info
    var shownInfoTab: InfoTab { infoTab == .axes && inspectedFamily?.isVariable != true ? .info : infoTab }
    var familyFeatures: [String: [FeatureSetting]] = [:]
    var familyAxes: [String: AdjustedAxes] = [:]

    // MARK: Prompts

    var installPrompt: InstallPrompt?
    var manyActivationPrompt: ManyActivationPrompt?
    var movingOutPrompt: MovingOutPrompt?
    var copySwitchPrompt: CopySwitchRequest?
    var duplicatePrompt: DuplicatePrompt?
    var replacePrompt: DuplicatePrompt?
    var openAppsReplacePrompt: OpenAppsReplacePrompt?
    var trashPlan: TrashPlan?
    var textPrompt: TextPrompt?
    var newTagRequest: NewTagRequest?
    var editingSmartSet: SmartSet?
    var editingAppsForSet: UUID?
    var editingCharacterSet: CustomCharacterSet?
    var deletingCharacterSets: [CustomCharacterSet] = []
    var isClearingCaches = false
    var documentFonts: DocumentFontsReport?
    var importing: ImportPrompt? {
        didSet {
            if let oldValue, oldValue.id != importing?.id { oldValue.library.discard() }
            showHeldToast()
        }
    }
    var showsBackupSheet = false
    var restorePrompt: BackupContents?
    private(set) var job: LibraryJob?
    var earlierImportPrompt: EarlierImportPrompt? {
        didSet { showHeldToast() }
    }
    var mayOfferEarlierImportCopy = false
    @ObservationIgnored var documentMatchesCache: (report: UUID, fingerprint: Int, matches: [DocumentFontMatch])?
    private(set) var toast: String?
    private(set) var toastUndo: (() -> Void)?
    @ObservationIgnored private var heldToast: String?

    // MARK: Compare

    var compareEntries: [CompareEntry] = []

    // MARK: Opening files

    @ObservationIgnored var openQueue: (batches: [(urls: [URL], target: SidebarItem?)], task: Task<Void, Never>?) = ([], nil)
    @ObservationIgnored var awaitingScan: [OpenedFiles] = []

    // MARK: Private

    @ObservationIgnored private(set) var started = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var coverageTask: Task<Void, Never>?
    @ObservationIgnored private var measurementTask: Task<Void, Never>?
    @ObservationIgnored private var coverageRun = 0
    @ObservationIgnored private var measurementRun = 0
    @ObservationIgnored private var problemsTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    // Operations run one at a time, or their changes to the records would overwrite each other.
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var lastScan = Date.distantPast
    @ObservationIgnored private var movingAtLaunch = false
    @ObservationIgnored private var scanCount = 0
    @ObservationIgnored private var revealProgress: Task<Void, Never>?
    @ObservationIgnored private var latestProgress: ScanProgress?
    @ObservationIgnored private var progressDue = false
    @ObservationIgnored private var runningOperations = 0
    @ObservationIgnored private var queuedOperations = 0
    @ObservationIgnored private var changeSeenBeforeScan: Int?
    @ObservationIgnored private var operationCount = 0
    @ObservationIgnored private var expectations: [Expectation] = []
    @ObservationIgnored private lazy var folderWatcher = FolderWatcher { [weak self] changed in
        self?.fontsChanged(changed.map(ScanScope.files) ?? .everything)
    }
    @ObservationIgnored private var pendingScope: ScanScope?
    @ObservationIgnored private var runningScan: (id: Int, scope: ScanScope, check: Bool)?
    @ObservationIgnored private var changedDuringScan: Set<String> = []
    @ObservationIgnored private var fontdChangedDuringScan = false
    @ObservationIgnored private var fontsFolderCheck: Task<Void, Never>?
    @ObservationIgnored var visibleCache: (key: VisibleKey, families: [Family], ids: Set<String>)?
    @ObservationIgnored var visibleCountsCache: (key: VisibleKey, active: Int, appOnly: [String])?
    @ObservationIgnored var fontRowsCache: (key: FontRowsKey, rows: [FontRow], families: [Family])?
    @ObservationIgnored let characterSetLookup = CharacterSetLookup()
    @ObservationIgnored var customSetsCache: (sets: [CustomCharacterSet], definitions: [CharacterSetDefinition])?
    @ObservationIgnored var similarCache: (key: SimilarKey, table: SimilarFonts)?
    @ObservationIgnored var listReturn: Set<SidebarItem>?
    @ObservationIgnored var listReturnPage: String?
    @ObservationIgnored private var savedGroups: ScannedGroups?
    #if CICERO_MEASURE
    @ObservationIgnored private(set) var measuredLibraries = 0
    @ObservationIgnored var searchApplies: (() -> Void)?
    @ObservationIgnored private(set) var endedScans = 0
    @ObservationIgnored var lastTrashed: [String: String] = [:]
    #endif

    init() {
        let locations = Locations.standard
        scanner = LibraryScanner(locations: locations)
        store = UserDataStore(locations: locations)
        appLock = LaunchWait.lock(support: locations.support)
        launchEngine = ActivationEngine(locations: locations)
        languages = LanguageCatalog(contentsOf: Bundle.main.url(forResource: "Languages", withExtension: "json"))
        scriptSamples = ScriptSamples(languages: languages)
        characterSetCatalog = CharacterSetCatalog(contentsOf: Bundle.main.url(forResource: "CharacterSets", withExtension: "json"))
        coverage = CoverageIndex(caches: locations.caches, languages: languages)
        measurements = MeasurementIndex(caches: locations.caches,
                                        embedder: LetterEmbedding(contentsOf: Bundle.main.url(forResource: "LetterEmbedding", withExtension: "mlmodelc")))
        pageContents = PageContents(coverage: coverage)
        guesser = ClassificationGuesser(caches: locations.caches)
        let defaults = UserDefaults.standard
        if !store.hasSavedData, defaults.object(forKey: Self.guessesClassificationsKey) == nil {
            defaults.set(true, forKey: Self.asksAboutGuessingKey)
        }
        let asks = defaults.bool(forKey: Self.asksAboutGuessingKey)
        asksAboutGuessing = asks
        guessesClassifications = !asks && defaults.object(forKey: Self.guessesClassificationsKey) as? Bool ?? true
        data = store.load()
        // Only with the lock: without it, the command may still be at work. `data`'s observer doesn't run in init.
        if appLock != nil, !store.isReadOnly, let journal = ActivationJournal.read(support: locations.support) {
            data.records = journal.repair(data.records, registrar: CoreTextRegistrar(), locations: locations)
            store.save(data)
            if store.flush(durably: true) { ActivationJournal.remove(support: locations.support) }
        }
        if appLock != nil, !store.isReadOnly, AppFolderMoves.exists(support: locations.support) {
            data.records = AppFolderMoves.recover(data.records, support: locations.support)
            store.save(data)
            if store.flush(durably: true) { AppFolderMoves.remove(support: locations.support) }
        }
        if data.fontLibraryPath.isEmpty { data.fontLibraryPath = locations.defaultFontLibrary.path }
        mayOfferEarlierImportCopy = FontExplorerImport.earlierImportLocation(in: data).map { !Self.declinedEarlierImport($0) } ?? false
        if guessesClassifications { classificationGuesses = guesser.guesses }
        refreshTagDots()
        restoreGroups()
        restoreLibrary()
        begin()
        commandRequests = CommandRequests(model: self)
        commandRequests?.start()
    }

    // MARK: Lifecycle

    private func begin() {
        store.onFailedWrite { [weak self] in
            Task { @MainActor in self?.showToast("Cicero couldn’t save the last change. Check that the disk has space and can be written to.") }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.movingAtLaunch, self.runningOperations == 0, Date().timeIntervalSince(self.lastScan) > 60,
                      self.runningScan.map({ $0.scope != .everything }) ?? true
                else { return }
                self.rescan(check: true)
            }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareToQuit() }
        }
        // Posted to this process's own center when any app, Cicero included, changes the registered fonts.
        center.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fontsChanged(.fontd(except: [])) }
        }
        if store.isReadOnly {
            showToast(store.readOnlyMessage)
            rescan(check: true)
            return
        }
        let migrating = needsFontLibraryMigration
        let renaming = launchEngine.hasFormerInactiveFolders
        let reassembling = launchEngine.hasLibraryMove
        movingAtLaunch = migrating || renaming || reassembling
        enqueue { model in
            if reassembling { await model.engine.finishLibraryMove(libraryPath: model.data.fontLibraryPath, records: model.data.records) }
            model.data.records = await model.engine.reconcileTemporary(model.data.records)
            if renaming { await model.moveFormerInactiveFolders() }
            await model.engine.finishTurningOff()
            model.engine.trashStagingLeftovers()
            let tidied = await model.engine.tidyInactiveFolder(model.data.records)
            model.data.records = tidied.records
            if migrating { await model.migrateFontLibrary() }
            let emptied = await model.engine.emptyInactiveFolder(model.data.records)
            model.data.records = emptied.records
            model.movingAtLaunch = false
            let renames = model.engine.renamesLater
            if !renames.isEmpty { model.renameBackLater(renames) }
            if migrating || renaming || reassembling || tidied.removed > 0 || emptied.moved > 0 { model.rescan(check: true) }
        }
        dropAdobeFolders()
        if !migrating && !renaming && !reassembling { rescan(check: true) }
    }

    private func moveFormerInactiveFolders() async {
        let moved = await engine.moveFormerInactiveFolders(data.records)
        data.records = moved.records
        data.fontFiles = ActivationEngine.paths(data.fontFiles, following: moved.moves)
        // The notes on the moves go only once they're saved, so a launch that stops in between, or a save that fails, still has them.
        if store.flush(durably: true) { engine.forgetInactiveFolderMoves() }
    }

    private var needsFontLibraryMigration: Bool {
        guard !data.fontLibraryPath.isEmpty else { return false }
        let path = URL(fileURLWithPath: data.fontLibraryPath).standardizedFileURL.path
        let former = path == locations.formerDefaultFontLibrary.standardizedFileURL.path && FileManager.default.fileExists(atPath: path)
        return former || !data.fontLibraryLocationChecked
    }

    private func migrateFontLibrary() async {
        var engine = self.engine
        engine.fontLibrary = data.fontLibraryLocation == nil ? URL(fileURLWithPath: data.fontLibraryPath, isDirectory: true) : nil
        if let moved = await engine.moveFromFormerPlace(records: data.records) {
            data.records = moved.records
            data.fontLibraryPath = locations.defaultFontLibrary.path
            if store.flush(durably: true) { engine.forgetLibraryMove() }
        }
        var checked = data
        checked.keepFormerFontLibraryAsLocation(hasFonts: fontLibraryHasFonts)
        data = checked
    }

    func start() {
        guard !started else { return }
        started = true
        openWaitingFiles()
    }

    private func restoreLibrary() {
        let scanner = scanner, records = data.records
        restoring = SavedLibraryRead { scanner.savedLibrary(records: records) }
    }

    private func finishRestoring() {
        guard let read = restoring else { return }
        restoring = nil
        #if CICERO_MEASURE
        let waiting = ContinuousClock.now
        #endif
        let saved = read.wait()
        #if CICERO_MEASURE
        Measurements.record("restore.wait", ms: (ContinuousClock.now - waiting).milliseconds, detail: "\(saved?.families.count ?? 0) families")
        #endif
        guard let saved else { return }
        withMutation(keyPath: \.library) { storedLibrary = saved }
        FontLoader.shared.prefetch(visibleFamilies.prefix(Self.readAheadFirst).map(\.regular.face))
    }

    private func dropAdobeFolders() {
        data.folders.removeAll { WatchedFolder.detectAppName(forPath: $0.path) != nil }
    }

    private func prepareToQuit() {
        commandRequests?.stop()
        #if CICERO_MEASURE
        let measuring = Measurements.begin("quit.endUntilQuit")
        let untilQuit = data.records.temporary.values.count { $0.scope == .untilQuit }
        #endif
        data.records = engine.endUntilQuit(data.records)
        #if CICERO_MEASURE
        measuring.end(detail: "\(untilQuit) files")
        Measurements.flush()
        #endif
        store.flush()
        scanner.flush()
        appLock?.release()
    }

    // MARK: Scanning

    var scanInput: ScanInput {
        ScanInput(folders: data.scannedFolders(), files: data.fontFiles, records: data.records)
    }

    @discardableResult
    func rescan(changes: Set<String>? = nil, check: Bool = false) -> Int {
        rescan(changes.map(ScanScope.files) ?? .everything, check: check)
    }

    @discardableResult
    private func rescan(_ scope: ScanScope, check: Bool) -> Int {
        if let running = runningScan, running.scope.walksFolders, !scope.walksAll {
            pendingScope = nil
            switch scope {
            case .files(let changes): changedDuringScan.formUnion(changes)
            case .fontd(let except):
                changedDuringScan.formUnion(except)
                fontdChangedDuringScan = true
            case .everything: break
            }
            return running.id
        }
        var scope = scope.adding(.files(changedDuringScan))
        if fontdChangedDuringScan { scope = scope.adding(.fontd(except: [])) }
        changedDuringScan = []
        fontdChangedDuringScan = false
        if let running = runningScan { scope = scope.adding(running.scope) }
        let check = check && runningScan?.check != false
        pendingScope = nil
        scanTask?.cancel()
        if scope == .everything { lastScan = Date() }
        scanCount += 1
        let id = scanCount
        runningScan = (id, scope, check)
        let input = scanInput
        let fontsFolders = [locations.userFonts.path, locations.allUsersFonts.path]
        folderWatcher.watch(fontsFolders + input.folders.map(\.path), files: input.files, hidden: [locations.adobeFontsInAdobeApps?.path].compactMap { $0 })
        latestProgress = .finding
        progressDue = false
        revealProgress?.cancel()
        revealProgress = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.scanCount == id else { return }
            self.progressDue = true
            self.showProgress(check: check)
        }
        let scanner = scanner
        let report: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard self.scanCount == id else { return }
                self.latestProgress = progress
                self.showProgress(check: check)
            }
        }
        let restoring = restoring
        scanTask = Task { [weak self] in
            await restoring?.finished()
            do {
                let library = switch scope {
                case .everything: try await scanner.scan(input, progress: report)
                case .files(let changes): try await scanner.scan(input, changes: changes, progress: report)
                case .fontd(let except): try await scanner.scan(input, keepingWalksExcept: except, progress: report)
                }
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

    private func showProgress(check: Bool) {
        guard progressDue || scanProgress != nil, let progress = latestProgress else { return }
        if check, progress == .finding, !library.families.isEmpty { return }
        scanProgress = progress
    }

    private func finishScan(_ id: Int) {
        guard runningScan?.id == id else { return }
        runningScan = nil
        if !changedDuringScan.isEmpty || fontdChangedDuringScan { scheduleRescan(after: 0) }
    }

    private func endScan(_ id: Int) {
        lastEndedScan = max(lastEndedScan, id)
        #if CICERO_MEASURE
        endedScans += 1
        #endif
        if scanCount == id {
            revealProgress?.cancel()
            progressDue = false
            scanProgress = nil
        }
        dropExpectations(confirmedBy: id)
        mergeExpectations()
        showOpenedFiles(after: id)
    }

    private func fontsChanged(_ scope: ScanScope) {
        if runningOperations > 0 {
            if changeSeenBeforeScan == nil { changeSeenBeforeScan = scanCount }
            return
        }
        var scope = scope
        if case .fontd = scope, Date().timeIntervalSince(lastScan) > ScanScope.walkEvery { scope = .everything }
        pendingScope = pendingScope.map { $0.adding(scope) } ?? scope
        scheduleRescan(after: pendingScope?.isFilesOnly == true ? 0.05 : 0.3)
        let changed: Set<String>? = if case .files(let changed) = scope { changed } else { nil }
        // macOS turns on a font put in a Fonts folder a few seconds later and says so, but says nothing when it doesn't take the font: look again then.
        let fontsFolders = [locations.userFonts.path + "/", locations.allUsersFonts.path + "/"]
        if let changed, changed.contains(where: { path in fontsFolders.contains { path.hasPrefix($0) } }) {
            fontsFolderCheck?.cancel()
            fontsFolderCheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.fontsChanged(.fontd(except: []))
            }
        }
    }

    private func scheduleRescan(after delay: Double) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.rescan(self.pendingScope ?? .files([]), check: true)
        }
    }

    func rebuildFontList() {
        scanner.clearCache()
        coverage.clearCache()
        measurements.clearCache()
        SampleWidths.shared.clearSaved()
        rescan()
    }

    private func apply(_ new: Library, scan id: Int) {
        let signpost = Signposts.library.beginInterval("Apply")
        defer { Signposts.library.endInterval("Apply", signpost) }
        #if CICERO_MEASURE
        let measuring = Measurements.begin("apply")
        defer { measuring.end(detail: "\(library.families.count) families") }
        #endif
        let first = !hasScanned
        hasScanned = true
        defer { guessClassifications() }
        // Looking for gone added files every time touches their folder, which may be one macOS asks about, like Downloads.
        if !store.isReadOnly, !new.goneFiles.isEmpty || !data.missingFontFiles.isEmpty { data.noteGoneFiles(new.goneFiles) }
        guard first || new.fingerprint != library.fingerprint else { return endScan(id) }
        let known = Set(library.families.lazy.flatMap(\.faces).map(\.face.path))
        if !store.isReadOnly { data.recordActivations(from: library, to: new) }
        let offline = library.offlinePaths
        library = new
        if !store.isReadOnly { activateAddedFonts(knowing: known, offline: offline) }
        endScan(id)
        if first {
            offerEarlierImportCopy()
            openWaitingFiles()
        }
        refreshGroups()
        selectedIDs = selectedIDs.filter { new.family($0) != nil }
        if let open = openFamilyID, new.family(open) == nil { openFamilyID = nil }
        if compareEntries.contains(where: { new.family($0.familyID) == nil }) { compareEntries.removeAll { new.family($0.familyID) == nil } }
        if let similar = similarFamilyID, new.family(similar) == nil { endSimilar() }
        FontLoader.shared.invalidate(paths: new.changedPaths)
        pageContents.forget(paths: new.changedPaths)
        scanner.tookChanges(new.changedPaths)
        FontLoader.shared.prefetch(visibleFamilies.prefix(Self.readAheadFirst).map(\.regular.face))
        updateCoverage()
        updateProblems()
    }

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
        measurementTask?.cancel()
        measurementRun &+= 1
        measurementProgress = nil
        coverageRun &+= 1
        let run = coverageRun
        let families = library.families
        let coverage = coverage
        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            guard let self else { return }
            Task { @MainActor in
                guard self.coverageRun == run else { return }
                self.coverageProgress = CoverageProgress(done: done, total: total)
                if done == total || done % 200 == 0 { self.coverageRevision &+= 1 }
            }
        }
        coverageTask = Task { [weak self] in
            await coverage.update(families, progress: report)
            guard !Task.isCancelled, let self else { return }
            self.coverageProgress = nil
            self.coverageRevision &+= 1
            self.characterSetLookup.reset()
            #if CICERO_MEASURE
            Measurements.record("coverage.done", ms: Measurements.sinceProcessStart, detail: "\(families.count) families")
            #endif
            self.updateMeasurements()
        }
    }

    private func updateMeasurements() {
        measurementTask?.cancel()
        measurementRun &+= 1
        let run = measurementRun
        let families = library.families
        let measurements = measurements
        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            guard let self else { return }
            Task { @MainActor in
                guard self.measurementRun == run else { return }
                self.measurementProgress = CoverageProgress(done: done, total: total)
                if done == total || done % 200 == 0 {
                    self.measurementRevision &+= 1
                    self.refreshLetterGuesses()
                }
            }
        }
        measurementTask = Task { [weak self] in
            await measurements.update(families, progress: report)
            guard !Task.isCancelled, let self else { return }
            self.measurementProgress = nil
            self.measurementRevision &+= 1
            self.refreshLetterGuesses()
            #if CICERO_MEASURE
            self.measuredLibraries += 1
            Measurements.record("measurements.done", ms: Measurements.sinceProcessStart, detail: "\(families.count) families")
            #endif
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

    func setSearchTokens(_ tokens: [SearchToken]) {
        let added = tokens.last { !searchTokens.contains($0) }
        searchTokens = SearchToken.normalized(tokens)
        guard let added, let rest = SearchToken.suggestions(for: lastTyped, besides: []).first(where: { $0.token == added })?.typed else { return }
        lastTyped = rest
        Task { @MainActor in self.searchText = rest }
    }

    func clearSearch() {
        searchText = ""
        searchTokens = []
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !searchText.isEmpty else {
            appliedSearch = ""
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.appliedSearch != self.searchText else { return }
            #if CICERO_MEASURE
            self.searchApplies?()
            #endif
            self.appliedSearch = self.searchText
            let name = SearchQuery(self.searchText).text
            if let family = self.visibleFamilies.first(where: { $0.name.lowercased() == name }) {
                self.jumpTargets = [family.id]
            }
        }
    }

    // MARK: Operations

    @discardableResult
    func enqueue(_ work: @escaping (AppModel) async -> Void) -> Bool {
        guard !store.isReadOnly else {
            showToast(store.readOnlyMessage)
            return false
        }
        let previous = operation
        runningOperations += 1
        queuedOperations += 1
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
            self.queuedOperations -= 1
            self.endOperation()
        }
        return true
    }

    var isWorking: Bool { queuedOperations > 0 || commandRequests?.isAnswering == true }

    func finishWork(within limit: Duration) async {
        commandRequests?.stop()
        let deadline = ContinuousClock.now + limit
        while isWorking, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func holdScans() {
        runningOperations += 1
    }

    func releaseScans() {
        endOperation()
    }

    private func endOperation() {
        runningOperations -= 1
        if let seen = changeSeenBeforeScan, runningOperations == 0 {
            changeSeenBeforeScan = nil
            if scanCount == seen { rescan() }
        }
    }

    // MARK: Expected positions

    private struct Expectation {
        var operation: Int
        var faces: [FaceID: SwitchPosition]
        var families: Set<String>
        var scan: Int?
    }

    func expect(_ faces: [LibraryFace], at position: SwitchPosition) -> Int {
        operationCount += 1
        guard !store.isReadOnly else { return operationCount }
        expectations.append(Expectation(
            operation: operationCount, faces: Dictionary(faces.map { ($0.id, position) }) { a, _ in a },
            families: Set(faces.map(\.face.familyName))
        ))
        mergeExpectations()
        return operationCount
    }

    func settle(_ operation: Int, after id: Int) {
        for index in expectations.indices where expectations[index].operation == operation {
            expectations[index].scan = id
        }
    }

    private func dropExpectations(confirmedBy id: Int) {
        expectations.removeAll { ($0.scan ?? .max) <= id }
    }

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

    static let undoTime = Duration.seconds(6)

    func showToast(_ message: String, undo: (() -> Void)? = nil) {
        if importing != nil || earlierImportPrompt != nil { return heldToast = message }
        toast = message
        toastUndo = undo
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: undo == nil ? .seconds(3) : Self.undoTime)
            guard !Task.isCancelled else { return }
            self?.toast = nil
            self?.toastUndo = nil
        }
    }

    private func showHeldToast() {
        guard importing == nil, earlierImportPrompt == nil, let held = heldToast else { return }
        heldToast = nil
        showToast(held)
    }

    func undoToast() {
        let undo = toastUndo
        toastTask?.cancel()
        toast = nil
        toastUndo = nil
        undo?()
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

    private func guessClassifications() {
        guard guessesClassifications else { return }
        let open = library.families.filter { $0.classification == .unclassified && !$0.mixesSerifAndSans }
        guesser.guess(open) { [weak self] in self?.guessesChanged() }
    }

    private func guessesChanged() {
        classificationGuesses = guesser.guesses
        guessRevision &+= 1
        refreshGroups()
    }

    func ask(overActivationSheets: Bool = false, _ show: @escaping (AppModel) -> Void) {
        guard isAsking(overActivationSheets: overActivationSheets) else { return show(self) }
        Task {
            while isAsking(overActivationSheets: overActivationSheets) { try? await Task.sleep(for: .milliseconds(200)) }
            show(self)
        }
    }

    var isShowingPrompt: Bool { isAsking(overActivationSheets: false) }

    private func isAsking(overActivationSheets: Bool) -> Bool {
        let hosts = overActivationSheets ? false : installPrompt != nil || documentFonts != nil
        return hosts || manyActivationPrompt != nil || movingOutPrompt != nil || copySwitchPrompt != nil || duplicatePrompt != nil
            || replacePrompt != nil || openAppsReplacePrompt != nil || trashPlan != nil || textPrompt != nil || newTagRequest != nil
            || editingSmartSet != nil || editingAppsForSet != nil || editingCharacterSet != nil || !deletingCharacterSets.isEmpty
            || isClearingCaches || importing != nil || earlierImportPrompt != nil || showsGuessingQuestion || showsBackupSheet
            || restorePrompt != nil
    }

    func startJob(_ new: LibraryJob) -> Bool {
        guard !store.isReadOnly else {
            showToast(store.readOnlyMessage)
            return false
        }
        if let job {
            showToast(job.waitMessage)
            return false
        }
        job = new
        return true
    }

    func endJob(_ ended: LibraryJob) {
        if job == ended { job = nil }
    }

    func answerGuessing(_ guesses: Bool) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.asksAboutGuessingKey)
        defaults.set(guesses, forKey: Self.guessesClassificationsKey)
        showsGuessingQuestion = false
        asksAboutGuessing = false
        guessesClassifications = guesses
    }

    private func refreshLetterGuesses() {
        let found = ClassificationGuesses.letters(of: library.families, measurements: measurements)
        guard found != letterGuesses else { return }
        letterGuesses = found
        guard guessesClassifications else { return }
        guessRevision &+= 1
        refreshGroups()
    }

    private func refreshGroups() {
        guard hasScanned else { return }
        var names = Set<String>()
        var classifications = Set<String>()
        var ownFolders = Set<UUID>()
        let foundryName = foundryNamer()
        let classificationName = classificationNamer()
        for family in library.families {
            if family.folderIDs.contains(WatchedFolder.adobeAppsID) { ownFolders.insert(WatchedFolder.adobeAppsID) }
            if data.showCreativeCloudFonts, family.folderIDs.contains(WatchedFolder.adobeFontsID) { ownFolders.insert(WatchedFolder.adobeFontsID) }
            if family.folderIDs.contains(WatchedFolder.addedFilesID) { ownFolders.insert(WatchedFolder.addedFilesID) }
            guard data.lists(family) else { continue }
            if let name = foundryName(family) { names.insert(name) }
            classifications.insert(classificationName(family))
        }
        if library.onlineOnlyFiles[WatchedFolder.addedFilesID] != nil { ownFolders.insert(WatchedFolder.addedFilesID) }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if sorted != foundryNames { foundryNames = sorted }
        let builtIn = Classification.allCases.filter { $0 != .unclassified }.map(name(of:)).filter(classifications.contains)
        let present = builtIn + data.classifications + [name(of: .unclassified)].filter(classifications.contains)
        if present != presentClassifications { presentClassifications = present }
        if ownFolders != ownFoldersWithFonts {
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

    private func restoreGroups() {
        guard let saved = UserDefaults.standard.data(forKey: ScannedGroups.defaultsKey),
              let groups = try? JSONDecoder().decode(ScannedGroups.self, from: saved) else { return }
        savedGroups = groups
        ownFoldersWithFonts = groups.ownFolders
        foundryNames = groups.foundries
        presentClassifications = groups.classifications
    }
}

private struct ScannedGroups: Codable, Equatable {
    static let defaultsKey = "sidebar.scannedGroups"
    var ownFolders: Set<UUID>
    var foundries: [String]
    var classifications: [String]
}

enum LibraryJob: Equatable {
    case importing, copyingEarlierImport, restoring, backingUp, clearingCaches

    var waitMessage: String {
        switch self {
        case .importing, .copyingEarlierImport: "Wait for the import to finish first"
        case .restoring: "Wait for the restore to finish first"
        case .backingUp: "Wait for the backup to finish first"
        case .clearingCaches: "Wait for the font caches to be cleared first"
        }
    }
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
    case axes = "Axes"
}

struct AdjustedAxes: Equatable {
    let face: FaceID
    var values: [String: Double]
}

struct InstallPrompt: Identifiable {
    let id = UUID()
    var files: [String]
    var offersMove: Bool
    var location: DropLocation?
    var add: (AppModel, InstallMethod) -> Void
}

struct DropLocation: Equatable {
    var id: UUID
    var name: String
    var folder: URL
    var isActive: Bool
    var app: String?
}

struct CopySwitchRequest: Identifiable {
    let id = UUID()
    var source: String
    var title: String
    var plan: CopySwitchPlan
}

struct OpenAppsReplacePrompt: Identifiable {
    let id = UUID()
    var apps: [String]
    var replace: (AppModel) -> Void
}

struct DuplicatePrompt: Identifiable {
    let id = UUID()
    var paths: [String]
    var duplicates: [AddedDuplicate]
    var handling: DuplicateHandling = .ask
    var method: InstallMethod?
    var location: DropLocation?
    var then: (AppModel, Set<String>, AddNote) -> Void
}

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
    var requiresText = false
    var action: (String) -> Void
}

enum ScanScope: Equatable {
    case everything
    case files(Set<String>)
    case fontd(except: Set<String>)

    #if CICERO_MEASURE
    static let walkEvery = ProcessInfo.processInfo.environment["CICERO_MEASURE_WALK_EVERY"].flatMap(TimeInterval.init) ?? 10 * 60
    #else
    static let walkEvery: TimeInterval = 10 * 60
    #endif

    var walksFolders: Bool { !isFilesOnly }
    var walksAll: Bool { self == .everything }
    var isFilesOnly: Bool { if case .files = self { true } else { false } }

    func adding(_ other: ScanScope) -> ScanScope {
        switch (self, other) {
        case (.everything, _), (_, .everything): .everything
        case let (.files(a), .files(b)): .files(a.union(b))
        case let (.fontd(a), .fontd(b)): .fontd(except: a.union(b))
        case let (.fontd(a), .files(b)), let (.files(b), .fontd(a)): .fontd(except: a.union(b))
        }
    }
}

nonisolated final class SavedLibraryRead: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var library: Library?

    init(_ read: @escaping @Sendable () -> Library?) {
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            library = read()
            done.signal()
        }
    }

    nonisolated func wait() -> Library? {
        done.wait()
        done.signal()
        return library
    }

    nonisolated func finished() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                _ = wait()
                continuation.resume()
            }
        }
    }
}
