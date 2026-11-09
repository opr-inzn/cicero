import Foundation
import Synchronization

public struct Locations: Sendable {
    public var support: URL
    public var caches: URL
    public var userFonts: URL
    public var allUsersFonts: URL
    public var systemFonts: [URL]
    public var home: URL
    public var adobeFontsInAdobeApps: URL?
    public var adobeFontsList: URL?
    public var defaultFontLibrary: URL
    // In the home folder, not in Application Support, which apps that remove an app delete with it, fonts and all.
    public var inactiveFolder: URL

    public var formerDefaultFontLibrary: URL {
        defaultFontLibrary.deletingLastPathComponent().appendingPathComponent("Font Library", isDirectory: true)
    }

    public init(support: URL, caches: URL, userFonts: URL, allUsersFonts: URL, systemFonts: [URL] = [], home: URL? = nil,
                adobeFontsInAdobeApps: URL? = nil, adobeFontsList: URL? = nil, defaultFontLibrary: URL? = nil, inactiveFolder: URL? = nil) {
        self.support = support
        self.caches = caches
        self.userFonts = userFonts
        self.allUsersFonts = allUsersFonts
        self.systemFonts = systemFonts
        self.home = home ?? userFonts.deletingLastPathComponent().deletingLastPathComponent()
        self.adobeFontsInAdobeApps = adobeFontsInAdobeApps
        self.adobeFontsList = adobeFontsList
        let defaultFontLibrary = defaultFontLibrary
            ?? userFonts.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Cicero/Library", isDirectory: true)
        self.defaultFontLibrary = defaultFontLibrary
        self.inactiveFolder = inactiveFolder
            ?? defaultFontLibrary.deletingLastPathComponent().appendingPathComponent("Inactive", isDirectory: true)
    }

    public static var standard: Locations {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return Locations(
            support: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cicero", isDirectory: true),
            caches: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Cicero", isDirectory: true),
            userFonts: home.appendingPathComponent("Library/Fonts", isDirectory: true),
            allUsersFonts: URL(fileURLWithPath: "/Library/Fonts", isDirectory: true),
            systemFonts: [URL(fileURLWithPath: "/System/Library/Fonts", isDirectory: true)],
            home: realHome,
            adobeFontsInAdobeApps: home.appendingPathComponent("Library/Application Support/Adobe/CoreSync/plugins/livetype/.w", isDirectory: true),
            adobeFontsList: home.appendingPathComponent("Library/Application Support/Adobe/CoreSync/plugins/livetype/.c/entitlements.xml")
        )
    }

    private static var realHome: URL? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    public var formerInactiveFolders: [URL] {
        Self.formerInactiveNames.map { support.appendingPathComponent($0, isDirectory: true) }
    }

    private static let formerInactiveNames = ["Inactive", "Deactivated"]

    public var inactiveFolders: [URL] {
        [inactiveFolder] + formerInactiveFolders.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func isInInactiveFolder(_ path: String) -> Bool {
        if path.hasPrefix(inactiveFolder.path + "/") { return true }
        let support = self.support.path + "/"
        return path.hasPrefix(support) && Self.formerInactiveNames.contains { path.hasPrefix(support + $0 + "/") }
    }

    public func inactiveFolderForNewFiles() throws -> URL {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: inactiveFolder, withIntermediateDirectories: true)
            return inactiveFolder
        } catch {
            let former = formerInactiveFolders[0]
            try fm.createDirectory(at: former, withIntermediateDirectories: true)
            return former
        }
    }
}

public struct Library: Sendable {
    public let families: [Family]
    public let unreadableFiles: [String]
    public let activePaths: Set<String>
    public let fingerprint: Int
    public let changedPaths: Set<String>
    public let unavailableFolders: [UUID: FolderAvailability]
    public let onlineOnlyFiles: [UUID: [String]]
    public let offlineFamilies: Set<String>
    public let offlinePaths: Set<String>
    public let goneFiles: Set<String>
    public let hasFacesOnUntilQuit: Bool

    public init(families: [Family], unreadableFiles: [String], activePaths: Set<String>, fingerprint: Int, changedPaths: Set<String> = [],
                unavailableFolders: [UUID: FolderAvailability] = [:], onlineOnlyFiles: [UUID: [String]] = [:], offlineFamilies: Set<String> = [],
                offlinePaths: Set<String> = [], goneFiles: Set<String> = []) {
        self.families = families
        self.unreadableFiles = unreadableFiles
        self.activePaths = activePaths
        self.fingerprint = fingerprint
        self.changedPaths = changedPaths
        self.unavailableFolders = unavailableFolders
        self.onlineOnlyFiles = onlineOnlyFiles
        self.offlineFamilies = offlineFamilies
        self.offlinePaths = offlinePaths
        self.goneFiles = goneFiles
        var index: [String: Int] = [:]
        var onUntilQuit = false
        for (position, family) in families.enumerated() {
            index[family.id] = position
            if !onUntilQuit { onUntilQuit = family.faces.contains { $0.state == .active(.temporary(.untilQuit)) } }
        }
        self.index = index
        hasFacesOnUntilQuit = onUntilQuit
        search = families.concurrentMap { family in
            var names = [family.id], others = [family.manufacturer ?? ""]
            if family.name != family.id { names.append(family.name) }
            var styles = Set<String>(), credits = Set<String>()
            for face in family.faces.map(\.face) {
                if styles.insert(face.styleName).inserted { names.append(face.styleName) }
                others.append(face.postScriptName)
                for word in [face.designer, face.vendorID].compactMap({ $0 }) where credits.insert(word).inserted { others.append(word) }
            }
            return SearchFields(names: names.joined(separator: " ").lowercased(), others: others.joined(separator: " ").lowercased(),
                                terms: family.searchTerms)
        }
    }

    public static let empty = Library(families: [], unreadableFiles: [], activePaths: [], fingerprint: 0)

    private let index: [String: Int]
    private let search: [SearchFields]

    private struct SearchFields: Sendable {
        var names: String
        var others: String
        var terms: [String]
    }

    public func family(_ id: String) -> Family? {
        index[id].map { families[$0] }
    }

    public func position(of id: String) -> Int? { index[id] }

    public func matches(_ family: Family, search query: SearchQuery, note: String? = nil, texts: [String] = [], terms: [String] = []) -> Bool {
        guard !query.isEmpty, let position = index[family.id] else { return true }
        let fields = search[position]
        return query.matches(names: note.map { [fields.names, $0] } ?? [fields.names], texts: [fields.others] + texts, terms: fields.terms + terms)
    }
}

public enum ScanProgress: Sendable, Equatable {
    case finding
    case identifying(done: Int, total: Int)
    case updating(done: Int, total: Int)
}

public struct ScanInput: Equatable, Sendable {
    public var folders: [WatchedFolder]
    public var files: [String]
    public var records: ActivationRecords

    public init(folders: [WatchedFolder], files: [String] = [], records: ActivationRecords) {
        self.folders = folders
        self.files = files
        self.records = records
    }
}

public final class LibraryScanner: Sendable {
    private let locations: Locations
    private let registrar: any FontRegistrar
    private let cacheURL: URL
    private let libraryURL: URL
    private let state = Mutex(State())
    private let saving: DispatchQueue
    private let saves: Bool

    private struct State {
        var files: [String: CachedFile] = [:]
        var loaded = false
        var dirty = false
        var ranks: [String: Int] = [:]
        var last: (inputs: Int, library: Library)?
        var lastStamps: [String: FaceStamp] = [:]
        var built = false
        var restored: Library?
        var savedFingerprint: Int?
        var onDisk: Library?
        var rereadAll = false
        var lastFind: Find?
        var lastFindScan = 0
        var scans = 0
    }

    private struct Find {
        var input: ScanInput
        var found: [String: FoundFile]
        var reach: OutOfReach
        var listed: Bool
        var walks: [WalkKey: Walk] = [:]
    }

    struct WalkKey: Hashable, Sendable {
        var path: String
        var includingHidden: Bool
        var skipping: [String]
    }

    struct Walk: Sendable {
        var files: [(path: String, stamp: FaceStamp)] = []
        var onlineOnly: [String] = []
    }

    #if CICERO_MEASURE
    public static let lastScanDetail = Mutex("")
    #endif

    public convenience init(locations: Locations) {
        self.init(locations: locations, registrar: CoreTextRegistrar())
    }

    public init(locations: Locations, registrar: any FontRegistrar, saves: Bool = true) {
        self.locations = locations
        self.saves = saves
        saving = DispatchQueue(label: "com.maximilianinzinger.Cicero.library-save", qos: .utility)
        self.registrar = registrar
        cacheURL = locations.caches.appendingPathComponent("faces.cache", isDirectory: false)
        libraryURL = locations.caches.appendingPathComponent("library.cache", isDirectory: false)
    }

    public func savedLibrary(records: ActivationRecords) -> Library? {
        Signposts.library.withIntervalSignpost("Restore library") {
            guard let data = try? Data(contentsOf: libraryURL, options: .mappedIfSafe) else { return nil }
            let session = ActivationEngine.currentSession()
            var asSaved = true
            let library = LibraryCache.decode(data) { state, path, app in
                guard case .active(.temporary) = state else { return state }
                if let record = records.temporary[path], record.scope == .whileAppsRun, record.session == session { return state }
                asSaved = false
                if let app, records.appFolderOrigins[path] == nil { return .appOnly(app) }
                return .inactive
            }
            state.withLock { state in
                state.restored = library
                state.onDisk = asSaved ? library : nil
            }
            return library
        }
    }

    public func savedLibraryAsNow(records: ActivationRecords) -> (library: Library, lastSaved: Date?)? {
        guard let data = try? Data(contentsOf: libraryURL, options: .mappedIfSafe) else { return nil }
        let saved = (try? FileManager.default.attributesOfItem(atPath: libraryURL.path))?[.modificationDate] as? Date
        let listed = Set(registrar.activeFontURLs().map { $0.path(percentEncoded: false) })
        var off: Set<String>?
        let locations = locations
        let registrar = registrar
        let fontsFolders = [locations.userFonts.path + "/", locations.allUsersFonts.path + "/"]
        let systemFolders = locations.systemFonts.map { $0.path + "/" }
        let library = LibraryCache.decode(data) { _, path, app in
            var active = listed.contains(path) || systemFolders.contains { path.hasPrefix($0) }
            if !active, fontsFolders.contains(where: { path.hasPrefix($0) }) {
                if off == nil { off = registrar.offFontPaths() }
                let offPaths = off!
                active = !offPaths.contains(path) && registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
            } else if !active, records.inPlace.contains(path) || records.temporary[path] != nil {
                active = registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
            }
            let file = FoundFile(stamp: FaceStamp(modified: .distantPast, size: 0), isActive: active, appName: app)
            return Self.faceState(of: path, file: file, locations: locations, records: records)
        }
        return library.map { ($0, saved) }
    }

    public func flush() {
        saving.sync { saveCacheIfNeeded() }
    }

    @concurrent
    public func scan(_ input: ScanInput, changes: Set<String>? = nil, keepingWalksExcept kept: Set<String>? = nil,
                     progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Library {
        let signposter = Signposts.library
        let scan = signposter.beginInterval("Scan")
        defer { signposter.endInterval("Scan", scan) }
        #if CICERO_MEASURE
        let measuring = Measurements.begin("scan")
        var detail = changes.map { "\($0.count) changed" } ?? "full"
        defer {
            measuring.end(detail: detail)
            Self.lastScanDetail.withLock { [detail] in $0 = detail }
        }
        #endif
        progress(.finding)
        let (number, last, rereadAll) = state.withLock { state in
            state.scans += 1
            return (state.scans, state.lastFind, state.rereadAll)
        }
        let finding = signposter.beginInterval("Find")
        let known = loadCache()
        let find: Find
        if let changes, !rereadAll, let last, last.input == input, let refound = refind(last, changes: changes) {
            find = refound
        } else {
            let registrar = registrar
            async let active = Self.activeFontURLs(registrar)
            let replaying = changes == nil && kept != nil && !rereadAll && last?.input == input ? last?.walks : nil
            var (found, reach, walks, replayed) = enumerateFolders(input, replaying: replaying, except: kept ?? [])
            #if CICERO_MEASURE
            if kept != nil { detail = "fontd, \(replayed) of \(walks.count) folders replayed" }
            #endif
            let activeURLs = await active
            addActive(activeURLs, to: &found, linked: linkedFolders(input))
            for path in found.keys where ActiveSource.isAdobeFonts(path) { found[path]!.folderIDs.append(WatchedFolder.adobeFontsID) }
            try confirmFontsFolders(&found, listed: !activeURLs.isEmpty)
            confirmRegistered(&found, records: input.records)
            reach.leaveOut(found)
            find = Find(input: input, found: found, reach: reach, listed: !activeURLs.isEmpty, walks: walks)
        }
        state.withLock { state in
            guard number > state.lastFindScan else { return }
            state.lastFind = find
            state.lastFindScan = number
        }
        let (found, reach) = (find.found, find.reach)
        signposter.endInterval("Find", finding)
        try Task.checkCancellation()

        let stale = rereadAll ? found : found.filter { known[$0.key]?.stamp != $0.value.stamp }
        var parsed: [String: CachedFile] = [:]
        if !stale.isEmpty {
            let total = stale.count
            let updating = listsAlready(stale)
            let report: @Sendable (Int) -> Void = { done in
                progress(updating ? .updating(done: done, total: total) : .identifying(done: done, total: total))
            }
            report(0)
            let parsing = signposter.beginInterval("Parse", "\(stale.count) files")
            parsed = await parse(stale, progress: report)
            signposter.endInterval("Parse", parsing)
        }
        try Task.checkCancellation()

        let files = updateCache(found: found, parsed: parsed, keeping: reach)
        if rereadAll { state.withLock { $0.rereadAll = false } }
        let inputs = Self.inputHash(found: found, records: input.records, reach: reach)
        if parsed.isEmpty, let last = state.withLock({ $0.last }), last.inputs == inputs {
            return last.library
        }
        let library = signposter.withIntervalSignpost("Build") { build(found: found, files: files, input: input, reach: reach, read: Set(parsed.keys)) }
        state.withLock { $0.last = (inputs, library) }
        let save = { [self] in
            signposter.withIntervalSignpost("Save cache") {
                saveCacheIfNeeded()
                saveLibraryIfNeeded(library)
            }
        }
        if changes != nil { saving.async(execute: save) } else { saving.sync(execute: save) }
        return library
    }

    private func refind(_ last: Find, changes: Set<String>) -> Find? {
        guard changes.count <= 200 else { return nil }
        let input = last.input
        var found = last.found
        for path in changes where Self.isFontFile(path) {
            if input.records.appFolderOrigins[path] != nil || last.reach.onlineOnlyPaths.contains(path) || last.reach.disconnectedFiles.contains(path) {
                return nil
            }
            func isIn(_ folder: URL) -> Bool { path.hasPrefix(folder.path + "/") }
            if locations.systemFonts.contains(where: isIn) || locations.isInInactiveFolder(path) { return nil }
            let fontsFolder = [locations.userFonts, locations.allUsersFonts].first(where: isIn)
            let folders = input.folders.filter { path.hasPrefix($0.path + "/") }
            let adobe = locations.adobeFontsInAdobeApps.flatMap { isIn($0) ? $0 : nil }
            let added = input.files.contains(path)
            guard fontsFolder != nil || !folders.isEmpty || adobe != nil || added else { return nil }
            if folders.contains(where: { last.reach.folders[$0.id] != nil }) { return nil }

            var info = stat()
            guard lstat(path, &info) == 0 else {
                if added, Reachability.disconnectedVolume(of: path) != nil { return nil }
                found[path] = nil
                continue
            }
            guard info.st_mode & S_IFMT != S_IFLNK else { return nil }
            guard let stamp = Self.stamp(ofPath: path) else {
                found[path] = nil
                continue
            }
            let previous = found[path]
            var file = FoundFile(stamp: stamp, isActive: false)
            var listed = added
            if let fontsFolder, Self.isListed(path, in: fontsFolder, includingHidden: false) {
                file.inFontsFolder = true
                listed = true
            }
            for folder in folders where Self.isListed(path, in: folder.url, includingHidden: false) {
                if Reachability.isOnlineOnly(path) { return nil }
                file.folderIDs.append(folder.id)
                if file.appName == nil { file.appName = folder.appName }
                listed = true
            }
            if let adobe, Self.isListed(path, in: adobe, includingHidden: true) {
                file.appName = "Adobe"
                listed = true
            }
            if added { file.folderIDs.append(WatchedFolder.addedFilesID) }
            guard listed else {
                if previous?.isActive == true { return nil }
                found[path] = nil
                continue
            }
            file.isActive = previous?.isActive ?? file.inFontsFolder
            if !file.isActive, file.inFontsFolder || input.records.inPlace.contains(path) || input.records.temporary[path] != nil {
                file.isActive = (file.inFontsFolder && !last.listed) || registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
            }
            if ActiveSource.isAdobeFonts(path) { file.folderIDs.append(WatchedFolder.adobeFontsID) }
            found[path] = file
        }
        var reach = last.reach
        reach.goneFiles = reach.goneFiles.filter { found[$0] == nil }
        let walks = last.walks.filter { key, _ in !Self.holds(key.path, any: changes) }
        return Find(input: input, found: found, reach: reach, listed: last.listed, walks: walks)
    }

    private static func isListed(_ path: String, in folder: URL, includingHidden: Bool) -> Bool {
        let components = path.dropFirst(folder.path.count + 1).split(separator: "/")
        if !includingHidden, components.contains(where: { $0.hasPrefix(".") }) { return false }
        var url = folder
        for component in components.dropLast() {
            url.appendPathComponent(String(component), isDirectory: true)
            if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return false }
        }
        return true
    }

    public func clearCache() {
        state.withLock {
            $0.rereadAll = true
            $0.dirty = true
            $0.last = nil
            $0.savedFingerprint = nil
            $0.onDisk = nil
        }
    }

    private static func inputHash(found: [String: FoundFile], records: ActivationRecords, reach: OutOfReach) -> Int {
        var sum: UInt64 = 0
        func add(_ hash: (inout Hasher) -> Void) {
            var hasher = Hasher()
            hash(&hasher)
            sum &+= UInt64(bitPattern: Int64(hasher.finalize()))
        }
        for (path, file) in found {
            add { hasher in
                hasher.combine(path)
                hasher.combine(file.stamp)
                hasher.combine(file.isActive)
                hasher.combine(file.folderIDs)
                hasher.combine(file.appName)
            }
        }
        for path in records.inPlace { add { $0.combine(path) } }
        for (path, origin) in records.appFolderOrigins {
            add { hasher in
                hasher.combine(path)
                hasher.combine(origin)
            }
        }
        for (path, record) in records.temporary {
            add { hasher in
                hasher.combine(path)
                hasher.combine(record.scope)
            }
        }
        add { hasher in
            hasher.combine(reach.folders)
            hasher.combine(reach.onlineOnly)
            hasher.combine(reach.disconnectedFiles)
        }
        return Int(bitPattern: UInt(sum))
    }

    // MARK: Finding

    struct FoundFile: Sendable {
        var stamp: FaceStamp
        var isActive: Bool
        var folderIDs: [UUID] = []
        var appName: String?
        var inFontsFolder = false
    }

    @concurrent
    private static func activeFontURLs(_ registrar: any FontRegistrar) async -> [URL] {
        registrar.activeFontURLs()
    }

    struct OutOfReach: Sendable {
        var folders: [UUID: FolderAvailability] = [:]
        var folderPaths: [String] = []
        var onlineOnly: [UUID: [String]] = [:]
        var onlineOnlyPaths: Set<String> = []
        var disconnectedFiles: Set<String> = []
        var goneFiles: Set<String> = []

        func keeps(_ path: String) -> Bool {
            onlineOnlyPaths.contains(path) || disconnectedFiles.contains(path) || folderPaths.contains { path.hasPrefix($0) }
        }

        mutating func leaveOut(_ found: [String: FoundFile]) {
            onlineOnly = onlineOnly.compactMapValues { paths in
                let left = paths.filter { found[$0] == nil }
                return left.isEmpty ? nil : left.sorted()
            }
            onlineOnlyPaths = Set(onlineOnly.values.joined())
        }
    }

    private static func holds(_ path: String, any paths: Set<String>) -> Bool {
        guard !paths.isEmpty else { return false }
        let given = path + "/", resolved = realPath(path) + "/"
        return paths.contains { $0.hasPrefix(given) || $0.hasPrefix(resolved) }
    }

    private func enumerateFolders(_ input: ScanInput, replaying: [WalkKey: Walk]? = nil, except: Set<String> = [])
        -> ([String: FoundFile], OutOfReach, [WalkKey: Walk], Int) {
        var found: [String: FoundFile] = [:]
        found.reserveCapacity(4096)
        var reach = OutOfReach()
        var walks: [WalkKey: Walk] = [:]
        var replayed = 0
        func walk(_ folder: URL, includingHidden: Bool = false, skipping: [String] = [], onlineOnly: ((String) -> Void)? = nil,
                  _ body: (String, FaceStamp) -> Void) {
            let key = WalkKey(path: folder.path, includingHidden: includingHidden, skipping: skipping)
            // Never replayed on a server: FSEvents doesn't hear of other Macs' changes there.
            if let kept = replaying?[key], Reachability.isOnLocalDisk(folder.path), !Self.holds(folder.path, any: except) {
                for file in kept.files { body(file.path, file.stamp) }
                if let onlineOnly { kept.onlineOnly.forEach(onlineOnly) }
                walks[key] = kept
                replayed += 1
                return
            }
            var walked = Walk()
            let report = onlineOnly.map { report in { (path: String) in
                walked.onlineOnly.append(path)
                report(path)
            } }
            Self.enumerate(folder, includingHidden: includingHidden, skipping: skipping, onlineOnly: report) { path, stamp in
                walked.files.append((path, stamp))
                body(path, stamp)
            }
            walks[key] = walked
        }
        for folder in [locations.userFonts, locations.allUsersFonts] {
            walk(folder) { path, stamp in
                found[path] = FoundFile(stamp: stamp, isActive: false, inFontsFolder: true)
            }
        }
        // macOS's own fonts are on, whether or not CoreText's list has them; its hidden ones (".SFNS") have names starting with a dot, which the library leaves out.
        for folder in locations.systemFonts {
            Self.enumerate(folder) { path, stamp in
                found[path] = FoundFile(stamp: stamp, isActive: true)
            }
        }
        let inactive = locations.inactiveFolders.map { WatchedFolder(id: WatchedFolder.inactiveFolderID, path: $0.path) }
        let inactivePaths = inactive.flatMap { [$0.path + "/", Self.realPath($0.path) + "/"] }
        for folder in input.folders + inactive {
            if folder.id != WatchedFolder.adobeAppsID && folder.id != WatchedFolder.inactiveFolderID,
               let availability = FolderAvailability.of(folder.path) {
                if folder.id == WatchedFolder.fontLibraryID && availability == .notFound { continue }
                reach.folders[folder.id] = availability
                reach.folderPaths.append(folder.path + "/")
                continue
            }
            let skipped = folder.id == WatchedFolder.inactiveFolderID ? [] : inactivePaths
            let add = { (path: String, stamp: FaceStamp) in
                if found[path] == nil {
                    found[path] = FoundFile(stamp: stamp, isActive: false)
                }
                found[path]!.folderIDs.append(folder.id)
                if found[path]!.appName == nil { found[path]!.appName = folder.appName }
            }
            let onlineOnly = { (path: String) in reach.onlineOnly[folder.id, default: []].append(path) }
            if folder.id == WatchedFolder.inactiveFolderID {
                Self.enumerate(folder.url, skipping: skipped, onlineOnly: onlineOnly, add)
            } else {
                walk(folder.url, skipping: skipped, onlineOnly: onlineOnly, add)
            }
        }
        if let folder = locations.adobeFontsInAdobeApps {
            walk(folder, includingHidden: true) { path, stamp in
                if found[path] == nil { found[path] = FoundFile(stamp: stamp, isActive: false) }
                found[path]!.appName = "Adobe"
            }
        }
        for path in input.files where Self.isFontFile(path) {
            guard let stamp = Self.stamp(ofPath: path) else {
                if Reachability.disconnectedVolume(of: path) != nil {
                    reach.disconnectedFiles.insert(path)
                } else if Reachability.isGone(path) {
                    reach.goneFiles.insert(path)
                }
                continue
            }
            if Reachability.isOnlineOnly(path) {
                reach.onlineOnly[WatchedFolder.addedFilesID, default: []].append(path)
                continue
            }
            if found[path] == nil { found[path] = FoundFile(stamp: stamp, isActive: false) }
            found[path]!.folderIDs.append(WatchedFolder.addedFilesID)
        }
        for (path, origin) in input.records.appFolderOrigins where found[path] != nil {
            guard let folder = input.folders.first(where: { $0.appName != nil && origin.hasPrefix($0.path + "/") }) else { continue }
            found[path]!.folderIDs.append(folder.id)
            found[path]!.appName = folder.appName
        }
        reach.onlineOnlyPaths = Set(reach.onlineOnly.values.joined())
        return (found, reach, walks, replayed)
    }

    private func addActive(_ urls: [URL], to found: inout [String: FoundFile], linked: [(real: String, chosen: String)]) {
        for url in urls {
            var path = url.path(percentEncoded: false)
            if found[path] == nil, let folder = linked.first(where: { path.hasPrefix($0.real) }) {
                let chosen = folder.chosen + path.dropFirst(folder.real.count)
                if found[chosen] != nil { path = chosen }
            }
            if found[path] != nil {
                found[path]!.isActive = true
            } else if Self.isFontFile(path), let stamp = Self.stamp(ofPath: path) {
                found[path] = FoundFile(stamp: stamp, isActive: true)
            }
        }
    }

    private func linkedFolders(_ input: ScanInput) -> [(real: String, chosen: String)] {
        // fontd names the files it has active by their paths with every symlink resolved.
        let folders = Set([locations.userFonts.path, locations.allUsersFonts.path] + input.folders.map(\.path)
            + input.files.map { ($0 as NSString).deletingLastPathComponent })
        return folders.flatMap { folder in
            Self.linkedPaths(folder).map { ($0 + "/", folder + "/") }
        }.sorted { $0.real.count > $1.real.count }
    }

    private func confirmFontsFolders(_ found: inout [String: FoundFile], listed: Bool) throws {
        // CoreText's list of active files leaves out files whose fonts have hidden names, so those missing from it are asked about.
        let unconfirmed = found.filter { $0.value.inFontsFolder && !$0.value.isActive }.keys
        guard listed else {
            for path in unconfirmed { found[path]!.isActive = true }
            return
        }
        let off = unconfirmed.isEmpty ? [] : registrar.offFontPaths()
        for path in unconfirmed where !off.contains(path) {
            try Task.checkCancellation()
            found[path]!.isActive = registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
        }
    }

    private func confirmRegistered(_ found: inout [String: FoundFile], records: ActivationRecords) {
        // CoreText's list hides some fonts though they're on, as copies of the macOS fonts it hides (Iowan Old Style, Times).
        for path in records.inPlace.union(records.temporary.keys) where found[path]?.isActive == false {
            found[path]!.isActive = registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
        }
    }

    private static func isFontFile(_ path: String) -> Bool {
        FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static func enumerate(_ folder: URL, includingHidden: Bool = false, skipping: [String] = [], onlineOnly: ((String) -> Void)? = nil,
                                  _ body: (String, FaceStamp) -> Void) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let chosen = folder.path + "/"
        let resolved = realPath(folder.path) + "/"
        // Walked where it really is: the enumerator doesn't follow a folder that's a symlink itself.
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: resolved, isDirectory: true), includingPropertiesForKeys: Array(keys),
            // Hidden files skipped, as AppleDouble "._" files look like fonts.
            options: includingHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            guard FontFileReader.fontExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let modified = values.contentModificationDate, let size = values.fileSize
            else { continue }
            var path = url.path(percentEncoded: false)
            if !skipping.isEmpty, skipping.contains(where: path.hasPrefix) { continue }
            if resolved != chosen, path.hasPrefix(resolved) { path = chosen + path.dropFirst(resolved.count) }
            if !skipping.isEmpty, skipping.contains(where: path.hasPrefix) { continue }
            // Reading a file a cloud service has taken off the Mac would download it.
            if let onlineOnly, Reachability.isOnlineOnly(path) {
                onlineOnly(path)
                continue
            }
            body(path, FaceStamp(modified: modified, size: Int64(size)))
        }
    }

    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func linkedPaths(_ path: String) -> Set<String> {
        // fontd resolves symlinks as Foundation does, which leaves /private off /private/var and /private/tmp, unlike realpath.
        Set([realPath(path), (path as NSString).resolvingSymlinksInPath]).subtracting([path])
    }

    private static func stamp(ofPath path: String) -> FaceStamp? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        return FaceStamp(modified: modified, size: Int64(info.st_size))
    }

    // MARK: Reading

    private func parse(_ files: [String: FoundFile], progress: @escaping @Sendable (Int) -> Void) async -> [String: CachedFile] {
        let total = files.count
        var results: [String: CachedFile] = [:]
        results.reserveCapacity(total)
        var saved = ContinuousClock.now
        await withTaskGroup(of: (String, CachedFile).self) { group in
            var pending = files.map { ($0.key, $0.value.stamp) }[...]
            func addNext() {
                guard let (path, stamp) = pending.popFirst() else { return }
                group.addTask {
                    // Its descriptors aren't kept, so fonts made from the path before are out of date: a file moved away and back would still draw from no file, which macOS answers with its "?" font.
                    let faces = FontFileReader.faces(atPath: path)
                    FontLoader.shared.invalidate(paths: [path])
                    return (path, CachedFile(stamp: stamp, dateAdded: FontFileReader.dateAdded(atPath: path), faces: faces))
                }
            }
            for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
            while let (path, file) = await group.next() {
                results[path] = file
                keep(path, file)
                if results.count % 200 == 0 || results.count == total {
                    progress(results.count)
                    if results.count < total, ContinuousClock.now - saved > .seconds(2) {
                        saved = .now
                        saving.async { [self] in saveCacheIfNeeded() }
                    }
                }
                if !Task.isCancelled { addNext() }
            }
        }
        return results
    }

    private func listsAlready(_ files: [String: FoundFile]) -> Bool {
        let (stamps, restored) = state.withLock { ($0.lastStamps, $0.restored) }
        if !stamps.isEmpty { return files.keys.count { stamps[$0] != nil } * 2 >= files.count }
        guard let restored else { return false }
        var paths = Set(restored.unreadableFiles)
        for face in restored.families.lazy.flatMap(\.faces) {
            paths.insert(face.face.path)
            for copy in face.copies { paths.insert(copy.face.path) }
        }
        return files.keys.count(where: paths.contains) * 2 >= files.count
    }

    // MARK: Cache

    private func loadCache() -> [String: CachedFile] {
        state.withLock { state in
            if !state.loaded {
                state.loaded = true
                if let data = try? Data(contentsOf: cacheURL, options: .mappedIfSafe), let files = FaceCache.decode(data) {
                    state.files = files
                }
            }
            return state.files
        }
    }

    private func keep(_ path: String, _ file: CachedFile) {
        state.withLock { state in
            state.files[path] = file
            state.dirty = true
        }
    }

    private func updateCache(found: [String: FoundFile], parsed: [String: CachedFile], keeping reach: OutOfReach) -> [String: CachedFile] {
        state.withLock { state in
            let before = state.files.count
            state.files = state.files.filter { found[$0.key] != nil || reach.keeps($0.key) }
            state.files.merge(parsed) { _, new in new }
            if !parsed.isEmpty || state.files.count != before { state.dirty = true }
            return state.files
        }
    }

    private func saveCacheIfNeeded() {
        guard saves else { return }
        let snapshot: [String: CachedFile]? = state.withLock { state in
            guard state.dirty else { return nil }
            state.dirty = false
            return state.files
        }
        guard let snapshot else { return }
        #if CICERO_MEASURE
        let measuring = Measurements.begin("cacheSave")
        defer { measuring.end(detail: "\(snapshot.count) files") }
        #endif
        let fm = FileManager.default
        try? fm.createDirectory(at: locations.caches, withIntermediateDirectories: true)
        if (try? FaceCache.encode(snapshot).write(to: cacheURL, options: .atomic)) == nil { state.withLock { $0.dirty = true } }
    }

    private func saveLibraryIfNeeded(_ library: Library) {
        guard saves else { return }
        let changed = state.withLock { state in
            guard state.savedFingerprint != library.fingerprint else { return false }
            state.savedFingerprint = library.fingerprint
            defer { state.onDisk = nil }
            return state.onDisk.map { !Self.savesAlike($0, library) } ?? true
        }
        guard changed else { return }
        try? FileManager.default.createDirectory(at: locations.caches, withIntermediateDirectories: true)
        if (try? LibraryCache.encode(library).write(to: libraryURL, options: .atomic)) == nil { state.withLock { $0.savedFingerprint = nil } }
    }

    private static func savesAlike(_ a: Library, _ b: Library) -> Bool {
        a.families == b.families && a.unreadableFiles == b.unreadableFiles && a.activePaths == b.activePaths
            && a.unavailableFolders == b.unavailableFolders && a.onlineOnlyFiles == b.onlineOnlyFiles
            && a.offlineFamilies == b.offlineFamilies && a.offlinePaths == b.offlinePaths
    }

    // MARK: Building

    private struct FaceKey: Hashable {
        var family: String
        var postScriptName: String
        // Some fonts' italics are named exactly like their uprights, so the name alone doesn't make two files copies.
        var isItalic: Bool
    }

    private struct Candidate {
        var face: FontFace
        var state: FaceState
        var dateAdded: Date?
        var folderIDs: [UUID]
        var stamp: FaceStamp
        var app: String?
    }

    private func build(found: [String: FoundFile], files: [String: CachedFile], input: ScanInput, reach: OutOfReach, read: Set<String>) -> Library {
        var candidates: [FaceKey: [Candidate]] = [:]
        candidates.reserveCapacity(files.values.reduce(0) { $0 + $1.faces.count })
        var unreadable: [String] = []
        var activePaths = Set<String>()
        activePaths.reserveCapacity(found.count)
        for (path, file) in found {
            if file.isActive { activePaths.insert(path) }
            guard let cached = files[path] else { continue }
            guard !cached.faces.isEmpty else {
                unreadable.append(path)
                continue
            }
            let state = Self.faceState(of: path, file: file, locations: locations, records: input.records)
            for face in cached.faces where !face.familyName.hasPrefix(".") && !face.familyName.isEmpty {
                candidates[FaceKey(family: face.familyName, postScriptName: face.postScriptName, isItalic: face.isItalic), default: []].append(
                    Candidate(face: face, state: state, dateAdded: cached.dateAdded, folderIDs: file.folderIDs, stamp: cached.stamp, app: file.appName)
                )
            }
        }

        var byFamily: [String: [(LibraryFace, Set<UUID>, FaceStamp)]] = [:]
        for (_, copies) in candidates {
            let sorted = copies.sorted { Self.precedes($0, $1) }
            let winner = sorted[0]
            var others: [FaceCopy] = []
            for copy in sorted.dropFirst() where copy.face.path != winner.face.path && !others.contains(where: { $0.face.path == copy.face.path }) {
                others.append(FaceCopy(face: copy.face, state: copy.state, app: copy.app))
            }
            let face = LibraryFace(face: winner.face, state: winner.state, copies: others, dateAdded: sorted.compactMap(\.dateAdded).min(), app: winner.app)
            let folderIDs = Set(sorted.flatMap(\.folderIDs))
            byFamily[winner.face.familyName, default: []].append((face, folderIDs, winner.stamp))
        }

        var stamps: [FaceID: FaceStamp] = [:]
        for members in byFamily.values {
            for (face, _, stamp) in members { stamps[face.id] = stamp }
        }
        let grouped = byFamily
        var families = Array(byFamily.keys).concurrentMap { name in
            let members = grouped[name]!
            let faces = members.map(\.0).sorted { Self.stylePrecedes($0.face, $1.face) }
            return Family(
                name: name, faces: faces, state: Self.familyState(of: faces),
                folderIDs: members.reduce(into: Set<UUID>()) { $0.formUnion($1.1) },
                manufacturer: faces.lazy.compactMap { Foundry.normalized($0.face.manufacturer) }.first
            )
        }
        families = Self.unifyingManufacturerCase(sorted(families))
        unreadable.sort()

        var offline = Set<String>()
        var offlinePaths = Set<String>()
        for (path, file) in files where found[path] == nil && reach.keeps(path) {
            if !reach.onlineOnlyPaths.contains(path) { offlinePaths.insert(path) }
            for face in file.faces where byFamily[face.familyName] == nil && !face.familyName.hasPrefix(".") && !face.familyName.isEmpty {
                offline.insert(face.familyName)
            }
        }

        var hasher = Hasher()
        for family in families {
            hasher.combine(family.id)
            hasher.combine(family.state)
            hasher.combine(family.manufacturer)
            hasher.combine(family.folderIDs)
            for face in family.faces {
                hasher.combine(face.id)
                hasher.combine(face.state)
                hasher.combine(face.copies)
                hasher.combine(face.app)
                hasher.combine(face.dateAdded)
                hasher.combine(stamps[face.id])
            }
        }
        hasher.combine(unreadable)
        hasher.combine(reach.folders)
        hasher.combine(reach.onlineOnly)
        hasher.combine(offline)
        let changed: Set<String> = state.withLock { state in
            var changed = Set(state.lastStamps.filter { found[$0.key]?.stamp != $0.value }.keys)
            if state.built {
                for path in found.keys where state.lastStamps[path] == nil && !read.contains(path) { changed.insert(path) }
            }
            state.built = true
            state.lastStamps = found.mapValues(\.stamp)
            state.restored = nil
            return changed
        }
        return Library(families: families, unreadableFiles: unreadable, activePaths: activePaths, fingerprint: hasher.finalize(), changedPaths: changed,
                       unavailableFolders: reach.folders, onlineOnlyFiles: reach.onlineOnly, offlineFamilies: offline, offlinePaths: offlinePaths,
                       goneFiles: reach.goneFiles)
    }

    static func stylePrecedes(_ a: FontFace, _ b: FontFace) -> Bool {
        if a.styleWeight != b.styleWeight { return a.styleWeight < b.styleWeight }
        if let order = precedes(a, b, along: { $0.first?.isUppercase == true }) { return order }
        if a.styleWidth != b.styleWidth { return a.styleWidth < b.styleWidth }
        if let order = precedes(a, b, along: { $0.first?.isUppercase != true && !["wght", "wdth", "ital", "slnt"].contains($0) }) {
            return order
        }
        if a.isItalic != b.isItalic { return !a.isItalic }
        if a.styleName != b.styleName { return a.styleName.caseInsensitiveCompare(b.styleName) == .orderedAscending }
        return a.id < b.id
    }

    private static func precedes(_ a: FontFace, _ b: FontFace, along tags: (String) -> Bool) -> Bool? {
        for axis in a.axes where tags(axis.tag) {
            if let value = b.axes.first(where: { $0.tag == axis.tag })?.value, value != axis.value { return axis.value < value }
        }
        return nil
    }

    private static func precedes(_ a: Candidate, _ b: Candidate) -> Bool {
        let rankA = rank(a), rankB = rank(b)
        if rankA != rankB { return rankA < rankB }
        return a.face.id < b.face.id
    }

    private static func rank(_ candidate: Candidate) -> Int {
        if case .appOnly = candidate.state, ActiveSource.isAdobeFonts(candidate.face.path) { return 10 }
        return rank(candidate.state)
    }

    private static func rank(_ state: FaceState) -> Int {
        switch state {
        case .active(.fontsFolder): 0
        case .active(.inPlace): 1
        case .active(.temporary): 2
        case .active(.otherApp): 3
        case .active(.allUsers): 4
        case .active(.adobeFonts): 5
        case .active(.app): 6
        case .active(.macOS): 7
        case .appOnly: 8
        case .inactive: 9
        }
    }

    static func faceState(of path: String, file: FoundFile, locations: Locations, records: ActivationRecords) -> FaceState {
        if file.isActive { return .active(activeSource(of: path, locations: locations, records: records)) }
        if let app = file.appName, records.appFolderOrigins[path] == nil { return .appOnly(app) }
        return .inactive
    }

    static func activeSource(of path: String, locations: Locations, records: ActivationRecords) -> ActiveSource {
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Application Support/Apple/") { return .macOS }
        if locations.systemFonts.contains(where: { path.hasPrefix($0.path + "/") }) { return .macOS }
        if let temporary = records.temporary[path], !ActiveSource.isAdobeFonts(path) { return .temporary(temporary.scope) }
        if path.hasPrefix(locations.allUsersFonts.path + "/") { return .allUsers }
        if path.hasPrefix(locations.userFonts.path + "/") { return .fontsFolder }
        if ActiveSource.isAdobeFonts(path) { return .adobeFonts }
        if records.inPlace.contains(path) { return .inPlace }
        if path.contains(".app/") { return .app }
        return .otherApp
    }

    static func familyState(of faces: [LibraryFace]) -> FamilyState {
        let active = faces.count { $0.state.isActive }
        if active == faces.count {
            return faces.allSatisfy { $0.state.source == .macOS } ? .system : .active
        }
        if active > 0 { return .partial }
        var apps = Set<String>()
        for face in faces {
            guard case .appOnly(let app) = face.state else { return .inactive }
            apps.insert(app)
        }
        return apps.count == 1 ? .appOnly(apps.first!) : .inactive
    }

    static func unifyingManufacturerCase(_ families: [Family]) -> [Family] {
        var spellings: [String: String] = [:]
        return families.map { family in
            guard let manufacturer = family.manufacturer else { return family }
            let key = String(manufacturer.lowercased().filter { $0.isLetter || $0.isNumber })
            if let spelling = spellings[key] {
                guard spelling != manufacturer else { return family }
                return Family(name: family.id, faces: family.faces, state: family.state, folderIDs: family.folderIDs, manufacturer: spelling)
            }
            spellings[key] = manufacturer
            return family
        }
    }

    private func sorted(_ families: [Family]) -> [Family] {
        let keys = families.map { $0.name == $0.id ? $0.id : $0.name + "\u{0}" + $0.id }
        let order: [String] = state.withLock { state in
            if keys.allSatisfy({ state.ranks[$0] != nil }) {
                return keys.sorted { state.ranks[$0]! < state.ranks[$1]! }
            }
            let sorted = keys.sorted(by: <).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            state.ranks = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1, $0) })
            return sorted
        }
        let byKey = Dictionary(uniqueKeysWithValues: zip(keys, families))
        return order.map { byKey[$0]! }
    }
}

public enum Foundry {
    private static let suffixes = [", Inc.", " Inc", " LLC", " Ltd.", " GmbH", " AG", " S.A.", " B.V.", " Corporation", " Corp."]

    public static func normalized(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 60 else { return nil }
        let lowercased = name.lowercased()
        guard !lowercased.contains("http"), !lowercased.contains("www."), !lowercased.hasPrefix("copyright"), !name.contains("©") else { return nil }
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where name.count > suffix.count && name.lowercased().hasSuffix(suffix.lowercased()) {
                name = String(name.dropLast(suffix.count))
                changed = true
            }
            let stray = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
            if stray != name {
                name = stray
                changed = true
            }
        }
        return name.isEmpty ? nil : name
    }
}

extension Array where Element: Sendable {
    func concurrentMap<T: Sendable>(_ transform: @Sendable (Element) -> T) -> [T] {
        [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            guard let base = buffer.baseAddress else { return }
            let slots = Slots(base: base)
            DispatchQueue.concurrentPerform(iterations: count) { index in
                (slots.base + index).initialize(to: transform(self[index]))
            }
            initialized = count
        }
    }
}

private struct Slots<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
}
