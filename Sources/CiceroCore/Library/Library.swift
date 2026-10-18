import Foundation
import Synchronization

/// Where Cicero keeps and finds things.
public struct Locations: Sendable {
    /// ~/Library/Application Support/Cicero
    public var support: URL
    /// ~/Library/Caches/Cicero
    public var caches: URL
    /// ~/Library/Fonts
    public var userFonts: URL
    /// /Library/Fonts
    public var allUsersFonts: URL
    /// The folders macOS keeps its own fonts in, /System/Library/Fonts. CoreText's lists of fonts leave some of
    /// them out (Times, Courier, Iowan Old Style, Seravek, many Noto fonts), though every app can use them.
    public var systemFonts: [URL]
    /// The user's home folder, whose own folders (Downloads, Desktop…) moving fonts never puts in the Trash. By
    /// default the one `userFonts` is in.
    public var home: URL
    /// Where Creative Cloud keeps the Adobe Fonts that Adobe apps turned on for themselves, as for a document
    /// that uses them: a hidden folder whose fonts only Adobe apps load, under hidden names.
    public var adobeFontsInAdobeApps: URL?

    public init(support: URL, caches: URL, userFonts: URL, allUsersFonts: URL, systemFonts: [URL] = [], home: URL? = nil,
                adobeFontsInAdobeApps: URL? = nil) {
        self.support = support
        self.caches = caches
        self.userFonts = userFonts
        self.allUsersFonts = allUsersFonts
        self.systemFonts = systemFonts
        self.home = home ?? userFonts.deletingLastPathComponent().deletingLastPathComponent()
        self.adobeFontsInAdobeApps = adobeFontsInAdobeApps
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
            adobeFontsInAdobeApps: home.appendingPathComponent("Library/Application Support/Adobe/CoreSync/plugins/livetype/.w", isDirectory: true)
        )
    }

    /// The home folder from the user's account, also when a test run gives Cicero another one (CFFIXED_USER_HOME),
    /// so its Downloads and Desktop stay safe from moving fonts too.
    private static var realHome: URL? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    /// Fonts Cicero moved out of ~/Library/Fonts because it had no other copy.
    public var deactivated: URL { support.appendingPathComponent("Deactivated", isDirectory: true) }
}

/// An immutable snapshot of every font Cicero knows about, built off the main thread by
/// `LibraryScanner` with everything views need precomputed.
public struct Library: Sendable {
    /// Sorted by name (Finder order).
    public let families: [Family]
    /// Font files CoreText couldn't read.
    public let unreadableFiles: [String]
    /// Every file macOS currently has active.
    public let activePaths: Set<String>
    /// Changes whenever anything visible about the library changes (files, stamps, states, folders).
    public let fingerprint: Int
    /// Files that changed or went away since the library the scanner built before this one, so
    /// whatever was read from them can be dropped.
    public let changedPaths: Set<String>
    /// Watched folders that can't be read now, and why. Their fonts are out of the library until they're back.
    public let unavailableFolders: [UUID: FolderAvailability]
    /// Font files in watched folders that a cloud service keeps online only, by folder. They're left out of the
    /// library, as reading one would download it.
    public let onlineOnlyFiles: [UUID: [String]]
    /// Families whose files are all out of reach for now (online only, in a watched folder that isn't there, or
    /// on a disk that isn't connected): not in `families`, but not gone either.
    public let offlineFamilies: Set<String>
    /// Font files the library had that are out of reach for now, in a watched folder that isn't there or on a disk that
    /// isn't connected; not those online only. Back, they're the files they were, not new ones.
    public let offlinePaths: Set<String>
    /// Font files added one at a time that are gone for good (see `Reachability.isGone`), for the user's list of them
    /// to drop. Looked for off the main thread, as a file on a server that stopped answering can take a while.
    public let goneFiles: Set<String>

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
        for (position, family) in families.enumerated() { index[family.id] = position }
        self.index = index
        searchText = families.concurrentMap { family in
            var words = [family.name, family.manufacturer ?? ""]
            var seen = Set<String>()
            for face in family.faces.map(\.face) {
                words.append(face.postScriptName)
                for word in [face.designer, face.vendorID].compactMap({ $0 }) where seen.insert(word).inserted { words.append(word) }
            }
            return words.joined(separator: " ").lowercased()
        }
    }

    public static let empty = Library(families: [], unreadableFiles: [], activePaths: [], fingerprint: 0)

    private let index: [String: Int]
    private let searchText: [String]

    public func family(_ id: String) -> Family? {
        index[id].map { families[$0] }
    }

    public func position(of id: String) -> Int? { index[id] }

    /// Whether a family matches a search: its name, foundry, or a style's PostScript name, designer or vendor
    /// ID contains the (lowercased) query.
    public func matches(_ family: Family, search lowercasedQuery: String) -> Bool {
        guard !lowercasedQuery.isEmpty, let position = index[family.id] else { return true }
        return searchText[position].contains(lowercasedQuery)
    }
}

public enum ScanProgress: Sendable, Equatable {
    case finding
    case identifying(done: Int, total: Int)
}

/// What a scan needs to know besides the disk.
public struct ScanInput: Equatable, Sendable {
    public var folders: [WatchedFolder]
    /// Font files added one at a time, listed where they are like a folder's (see `WatchedFolder.addedFilesID`).
    public var files: [String]
    public var records: ActivationRecords

    public init(folders: [WatchedFolder], files: [String] = [], records: ActivationRecords) {
        self.folders = folders
        self.files = files
        self.records = records
    }
}


/// Finds every font file (CoreText's active fonts, macOS's font folders, ~/Library/Fonts, /Library/Fonts, the
/// watched folders, the files added one at a time and Cicero's Deactivated folder), reads new or changed files,
/// and builds a `Library`.
/// Parsed faces and Date Added are cached in `Locations.caches` by path, modification date and size;
/// the decoded cache stays in memory between scans. Cancellation stops it between phases.
public final class LibraryScanner: Sendable {
    private let locations: Locations
    private let registrar: any FontRegistrar
    private let cacheURL: URL
    private let libraryURL: URL
    private let state = Mutex(State())
    /// Writes the caches in the order scans finish.
    private let saving: DispatchQueue

    private struct State {
        var files: [String: CachedFile] = [:]
        var loaded = false
        var dirty = false
        /// Finder-order positions from the last full sort, so scans with no new family skip `localizedStandardCompare`.
        var ranks: [String: Int] = [:]
        /// The last library built and a hash of what it was built from, so an unchanged rescan returns it as is.
        var last: (inputs: Int, library: Library)?
        /// The stamps of the files the last library was built from.
        var lastStamps: [String: FaceStamp] = [:]
        /// The fingerprint of the library last saved for the next launch.
        var savedFingerprint: Int?
        /// Set by `clearCache`: the next scan reads every file it finds again, but keeps what it knows of the
        /// ones out of reach.
        var rereadAll = false
        /// The files the latest scan found, for a scan told which files changed to start from; and that scan's
        /// number, so a scan that started earlier but found its files later doesn't replace them.
        var lastFind: Find?
        var lastFindScan = 0
        var scans = 0
    }

    /// What a scan found on disk and from fontd, before reading any file.
    private struct Find {
        var input: ScanInput
        var found: [String: FoundFile]
        var reach: OutOfReach
        /// Whether fontd gave its list of active files (see `confirmFontsFolders`).
        var listed: Bool
    }

    public convenience init(locations: Locations) {
        self.init(locations: locations, registrar: CoreTextRegistrar())
    }

    /// `registrar` supplies the system's active font files; tests pass a fake.
    public init(locations: Locations, registrar: any FontRegistrar) {
        self.locations = locations
        saving = DispatchQueue(label: "com.maximilianinzinger.Cicero.library-save", qos: .utility)
        self.registrar = registrar
        cacheURL = locations.caches.appendingPathComponent("faces.cache", isDirectory: false)
        libraryURL = locations.caches.appendingPathComponent("library.cache", isDirectory: false)
    }

    /// The library the last scan built, as saved after it, for the window to show until this launch's first scan
    /// is done. Faces turned on until Cicero quit, or for an application set before a logout or restart, are off again.
    public func savedLibrary(records: ActivationRecords) -> Library? {
        Signposts.library.withIntervalSignpost("Restore library") {
            guard let data = try? Data(contentsOf: libraryURL, options: .mappedIfSafe) else { return nil }
            let session = ActivationEngine.currentSession()
            return LibraryCache.decode(data) { state, path, app in
                guard case .active(.temporary) = state else { return state }
                if let record = records.temporary[path], record.scope == .whileAppsRun, record.session == session { return state }
                // What `faceState` says of a file that isn't active.
                if let app, records.appFolderOrigins[path] == nil { return .appOnly(app) }
                return .inactive
            }
        }
    }

    /// With `changes`, the files FSEvents says changed since the last scan (as `FolderWatcher` reports them),
    /// only those are looked at again, which takes a few milliseconds instead of a walk through every folder
    /// and fontd's whole list, which can take seconds on a busy Mac. It scans everything when the input
    /// changed or a change needs it, such as a file in a folder whose fonts are online only.
    @concurrent
    public func scan(_ input: ScanInput, changes: Set<String>? = nil, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Library {
        let signposter = Signposts.library
        let scan = signposter.beginInterval("Scan")
        defer { signposter.endInterval("Scan", scan) }
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
            // Asking fontd for the active files takes ~100 ms, as long as walking the folders; do both at once.
            let registrar = registrar
            async let active = Self.activeFontURLs(registrar)
            var (found, reach) = enumerateFolders(input)
            let activeURLs = await active
            addActive(activeURLs, to: &found, linked: linkedFolders(input))
            for path in found.keys where ActiveSource.isAdobeFonts(path) { found[path]!.folderIDs.append(WatchedFolder.adobeFontsID) }
            confirmFontsFolders(&found, listed: !activeURLs.isEmpty)
            confirmRegistered(&found, records: input.records)
            reach.leaveOut(found)
            find = Find(input: input, found: found, reach: reach, listed: !activeURLs.isEmpty)
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
            progress(.identifying(done: 0, total: stale.count))
            let parsing = signposter.beginInterval("Parse", "\(stale.count) files")
            parsed = await Self.parse(stale, progress: progress)
            signposter.endInterval("Parse", parsing)
        }
        if Task.isCancelled {
            // What was read is kept, so the scan that replaced this one reads only the rest: one of everything, after an
            // update that reads every file again, would otherwise never finish while fonts kept changing.
            keep(parsed)
            throw CancellationError()
        }

        let files = updateCache(found: found, parsed: parsed, keeping: reach)
        if rereadAll { state.withLock { $0.rereadAll = false } }
        let inputs = Self.inputHash(found: found, records: input.records, reach: reach)
        if parsed.isEmpty, let last = state.withLock({ $0.last }), last.inputs == inputs {
            return last.library
        }
        let library = signposter.withIntervalSignpost("Build") { build(found: found, files: files, input: input, reach: reach) }
        state.withLock { $0.last = (inputs, library) }
        // After a few changed files the caches are written once the library is back, as on a busy Mac that can
        // take longer than everything else.
        let save = { [self] in
            signposter.withIntervalSignpost("Save cache") {
                saveCacheIfNeeded()
                saveLibraryIfNeeded(library)
            }
        }
        if changes != nil { saving.async(execute: save) } else { saving.sync(execute: save) }
        return library
    }

    /// The last scan's files with the changed ones looked at again, as a full scan would find them; nil when one
    /// needs a full scan: one Cicero moved out of an app's folder, one out of reach, on a disk that isn't
    /// connected or online only, a symlink, or one outside the folders scanned.
    private func refind(_ last: Find, changes: Set<String>) -> Find? {
        guard changes.count <= 200 else { return nil }
        let input = last.input
        var found = last.found
        for path in changes where Self.isFontFile(path) {
            if input.records.appFolderOrigins[path] != nil || last.reach.onlineOnlyPaths.contains(path) || last.reach.disconnectedFiles.contains(path) {
                return nil
            }
            func isIn(_ folder: URL) -> Bool { path.hasPrefix(folder.path + "/") }
            if locations.systemFonts.contains(where: isIn) || isIn(locations.deactivated) { return nil }
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
            // As `enumerateFolders` finds it, folder by folder.
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
            // A file that was there keeps what fontd said of it. A new one in a Fonts folder is on, as macOS turns on
            // whatever is put there, if a few seconds later (the scan after it says, see `AppModel.fontsChanged`);
            // any other is off unless Cicero registered it before (as `confirmRegistered` asks).
            file.isActive = previous?.isActive ?? file.inFontsFolder
            if !file.isActive, file.inFontsFolder || input.records.inPlace.contains(path) || input.records.temporary[path] != nil {
                file.isActive = (file.inFontsFolder && !last.listed) || registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
            }
            if ActiveSource.isAdobeFonts(path) { file.folderIDs.append(WatchedFolder.adobeFontsID) }
            found[path] = file
        }
        // An added file the last scan of everything found gone that's back isn't gone any more.
        var reach = last.reach
        reach.goneFiles = reach.goneFiles.filter { found[$0] == nil }
        return Find(input: input, found: found, reach: reach, listed: last.listed)
    }

    /// Whether `enumerate` lists a file under a folder: none of the folders between them, nor the file, is
    /// hidden (unless `includingHidden`) or a package.
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

    /// Has the next scan read every file it finds again. What was read from files out of reach for now is
    /// kept, so their families still count as away rather than gone.
    public func clearCache() {
        state.withLock {
            $0.rereadAll = true
            $0.dirty = true
            $0.last = nil
            $0.savedFingerprint = nil
        }
    }

    /// Everything a build depends on besides the cached faces, combined in any order.
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
        /// In ~/Library/Fonts or /Library/Fonts.
        var inFontsFolder = false
    }

    @concurrent
    private static func activeFontURLs(_ registrar: any FontRegistrar) async -> [URL] {
        registrar.activeFontURLs()
    }

    /// What a scan couldn't get at: watched folders it couldn't read, files a cloud service keeps online only,
    /// and files added one at a time whose disk isn't connected. What was read from them before is kept.
    struct OutOfReach: Sendable {
        var folders: [UUID: FolderAvailability] = [:]
        /// The unavailable folders' paths, each with a "/" at the end.
        var folderPaths: [String] = []
        var onlineOnly: [UUID: [String]] = [:]
        var onlineOnlyPaths: Set<String> = []
        var disconnectedFiles: Set<String> = []
        /// Files added one at a time that are gone for good, which no scan needs to look for again.
        var goneFiles: Set<String> = []

        /// Whether the faces read from a file the scan didn't find are worth keeping: it's only out of reach.
        func keeps(_ path: String) -> Bool {
            onlineOnlyPaths.contains(path) || disconnectedFiles.contains(path) || folderPaths.contains { path.hasPrefix($0) }
        }

        /// Online-only files that are in the library anyway, being active (which downloads them), aren't left out.
        mutating func leaveOut(_ found: [String: FoundFile]) {
            onlineOnly = onlineOnly.compactMapValues { paths in
                let left = paths.filter { found[$0] == nil }
                return left.isEmpty ? nil : left.sorted()
            }
            onlineOnlyPaths = Set(onlineOnly.values.joined())
        }
    }

    private func enumerateFolders(_ input: ScanInput) -> ([String: FoundFile], OutOfReach) {
        var found: [String: FoundFile] = [:]
        found.reserveCapacity(4096)
        var reach = OutOfReach()
        for folder in [locations.userFonts, locations.allUsersFonts] {
            Self.enumerate(folder) { path, stamp in
                found[path] = FoundFile(stamp: stamp, isActive: false, inFontsFolder: true)
            }
        }
        // macOS's own fonts are on, whether or not CoreText's list has them. Its hidden ones (".SFNS") have
        // names starting with a dot, which the library leaves out.
        for folder in locations.systemFonts {
            Self.enumerate(folder) { path, stamp in
                found[path] = FoundFile(stamp: stamp, isActive: true)
            }
        }
        let deactivated = WatchedFolder(id: WatchedFolder.deactivatedID, path: locations.deactivated.path)
        for folder in input.folders + [deactivated] {
            // Adobe's folders and Cicero's own are listed only when they're there.
            if folder.id != WatchedFolder.adobeAppsID && folder.id != WatchedFolder.deactivatedID,
               let availability = FolderAvailability.of(folder.path) {
                reach.folders[folder.id] = availability
                reach.folderPaths.append(folder.path + "/")
                continue
            }
            Self.enumerate(folder.url, onlineOnly: { reach.onlineOnly[folder.id, default: []].append($0) }) { path, stamp in
                if found[path] == nil {
                    found[path] = FoundFile(stamp: stamp, isActive: false)
                }
                found[path]!.folderIDs.append(folder.id)
                if found[path]!.appName == nil { found[path]!.appName = folder.appName }
            }
        }
        // Adobe Fonts that Adobe apps turned on for themselves are on in those apps, and Creative Cloud's to switch.
        if let folder = locations.adobeFontsInAdobeApps {
            Self.enumerate(folder, includingHidden: true) { path, stamp in
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
        // Files Cicero moved out of an app's folder to turn them off still belong with that folder.
        for (path, origin) in input.records.appFolderOrigins where found[path] != nil {
            guard let folder = input.folders.first(where: { $0.appName != nil && origin.hasPrefix($0.path + "/") }) else { continue }
            found[path]!.folderIDs.append(folder.id)
            found[path]!.appName = folder.appName
        }
        reach.onlineOnlyPaths = Set(reach.onlineOnly.values.joined())
        return (found, reach)
    }

    private func addActive(_ urls: [URL], to found: inout [String: FoundFile], linked: [(real: String, chosen: String)]) {
        for url in urls {
            var path = url.path(percentEncoded: false)
            // A file in a folder reached through a symlink goes by the path the folder was found at.
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

    /// The folders scanned that are reached through a symlink, each as CoreText may name it and as it was chosen (with a
    /// "/" at the end), longest first: fontd names the files it has active by their paths with every symlink resolved.
    private func linkedFolders(_ input: ScanInput) -> [(real: String, chosen: String)] {
        let folders = Set([locations.userFonts.path, locations.allUsersFonts.path] + input.folders.map(\.path)
            + input.files.map { ($0 as NSString).deletingLastPathComponent })
        return folders.flatMap { folder in
            Self.linkedPaths(folder).map { ($0 + "/", folder + "/") }
        }.sorted { $0.real.count > $1.real.count }
    }

    /// Files in the Fonts folders are active unless macOS says otherwise, as for one turned off in macOS or
    /// one macOS hasn't noticed yet. Its list leaves out files whose fonts have hidden names, so files missing
    /// from it are asked about one by one (there are only a few); without a list at all, they count as active.
    private func confirmFontsFolders(_ found: inout [String: FoundFile], listed: Bool) {
        let unconfirmed = found.filter { $0.value.inFontsFolder && !$0.value.isActive }.keys
        for path in unconfirmed {
            found[path]!.isActive = !listed || registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
        }
    }

    /// The files Cicero registered itself (in place, or for a while) that CoreText's list leaves out are asked
    /// about one by one, like those in the Fonts folders: the list hides some fonts though they're on, as copies
    /// of the macOS fonts it hides (Iowan Old Style, Times).
    private func confirmRegistered(_ found: inout [String: FoundFile], records: ActivationRecords) {
        for path in records.inPlace.union(records.temporary.keys) where found[path]?.isActive == false {
            found[path]!.isActive = registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
        }
    }

    private static func isFontFile(_ path: String) -> Bool {
        FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Every font file under a folder, except inside packages and hidden ones (AppleDouble "._" files look like fonts).
    /// Paths start with the folder's own path, as the user chose it, even when it goes through a symlink.
    /// With `onlineOnly`, files a cloud service has taken off the Mac go there instead: reading one would
    /// download it.
    private static func enumerate(_ folder: URL, includingHidden: Bool = false, onlineOnly: ((String) -> Void)? = nil,
                                  _ body: (String, FaceStamp) -> Void) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let chosen = folder.path + "/"
        let resolved = realPath(folder.path) + "/"
        // Walked where it really is: the enumerator doesn't follow a folder that's a symlink itself.
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: resolved, isDirectory: true), includingPropertiesForKeys: Array(keys),
            options: includingHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            guard FontFileReader.fontExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let modified = values.contentModificationDate, let size = values.fileSize
            else { continue }
            var path = url.path(percentEncoded: false)
            if resolved != chosen, path.hasPrefix(resolved) { path = chosen + path.dropFirst(resolved.count) }
            if let onlineOnly, Reachability.isOnlineOnly(path) {
                onlineOnly(path)
                continue
            }
            body(path, FaceStamp(modified: modified, size: Int64(size)))
        }
    }

    /// The path with every symlink resolved, as the enumerator reports files (e.g. /private/var for /var).
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The paths besides this one that CoreText may name a file by when a symlink leads to it: fontd resolves every
    /// symlink as Foundation does, which leaves /private off /private/var and /private/tmp, unlike `realPath`. None
    /// when no symlink does.
    static func linkedPaths(_ path: String) -> Set<String> {
        Set([realPath(path), (path as NSString).resolvingSymlinksInPath]).subtracting([path])
    }

    private static func stamp(ofPath path: String) -> FaceStamp? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        return FaceStamp(modified: modified, size: Int64(info.st_size))
    }

    // MARK: Reading

    /// Stops starting files when the task is cancelled, and returns those it read.
    private static func parse(_ files: [String: FoundFile], progress: @escaping @Sendable (ScanProgress) -> Void) async -> [String: CachedFile] {
        let total = files.count
        var results: [String: CachedFile] = [:]
        results.reserveCapacity(total)
        await withTaskGroup(of: (String, CachedFile).self) { group in
            var pending = files.map { ($0.key, $0.value.stamp) }[...]
            func addNext() {
                guard let (path, stamp) = pending.popFirst() else { return }
                group.addTask {
                    // Previews and coverage need the same descriptors, so they aren't read again.
                    let (faces, descriptors) = FontFileReader.read(atPath: path)
                    FontLoader.shared.keep(descriptors, for: path)
                    return (path, CachedFile(stamp: stamp, dateAdded: FontFileReader.dateAdded(atPath: path), faces: faces))
                }
            }
            for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
            while let (path, file) = await group.next() {
                results[path] = file
                if results.count % 200 == 0 || results.count == total {
                    progress(.identifying(done: results.count, total: total))
                }
                if !Task.isCancelled { addNext() }
            }
        }
        return results
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

    /// Adds what a scan that was cancelled read, for the next one.
    private func keep(_ parsed: [String: CachedFile]) {
        guard !parsed.isEmpty else { return }
        state.withLock { state in
            state.files.merge(parsed) { _, new in new }
            state.dirty = true
        }
    }

    /// Adds what was read, drops files that are gone, and returns the cache for the found files and the
    /// ones only out of reach, which needn't be read again when they're back.
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
        let snapshot: [String: CachedFile]? = state.withLock { state in
            guard state.dirty else { return nil }
            state.dirty = false
            return state.files
        }
        guard let snapshot else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: locations.caches, withIntermediateDirectories: true)
        try? FaceCache.encode(snapshot).write(to: cacheURL, options: .atomic)
    }

    /// Saves the library for the next launch (see `savedLibrary`) when it isn't the one saved last. Fingerprints
    /// differ from one launch to the next, so each launch's first scan saves it again.
    private func saveLibraryIfNeeded(_ library: Library) {
        let changed = state.withLock { state in
            guard state.savedFingerprint != library.fingerprint else { return false }
            state.savedFingerprint = library.fingerprint
            return true
        }
        guard changed else { return }
        try? FileManager.default.createDirectory(at: locations.caches, withIntermediateDirectories: true)
        try? LibraryCache.encode(library).write(to: libraryURL, options: .atomic)
    }

    // MARK: Building

    private struct FaceKey: Hashable {
        var family: String
        var postScriptName: String
        /// Some fonts' italics are named exactly like their uprights, so the name alone doesn't make two files copies.
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

    private func build(found: [String: FoundFile], files: [String: CachedFile], input: ScanInput, reach: OutOfReach) -> Library {
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

        // One face per PostScript name (and slant) within a family: the active file wins, the others are its other
        // copies. Different families keep their own faces even when names clash (the Problems view says so).
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
        let names = sortedNames(Array(byFamily.keys))
        let grouped = byFamily
        var families = names.concurrentMap { name in
            let members = grouped[name]!
            let faces = members.map(\.0).sorted { a, b in
                // Narrowest first, then lightest: by each named instance's place on the axes, as a variable
                // font's instances share one width and weight class.
                if a.face.styleWidth != b.face.styleWidth { return a.face.styleWidth < b.face.styleWidth }
                if a.face.styleWeight != b.face.styleWeight { return a.face.styleWeight < b.face.styleWeight }
                if a.face.isItalic != b.face.isItalic { return !a.face.isItalic }
                if a.face.styleName != b.face.styleName { return a.face.styleName.caseInsensitiveCompare(b.face.styleName) == .orderedAscending }
                return a.face.id < b.face.id
            }
            return Family(
                name: name, faces: faces, state: Self.familyState(of: faces),
                folderIDs: members.reduce(into: Set<UUID>()) { $0.formUnion($1.1) },
                manufacturer: faces.lazy.compactMap { Foundry.normalized($0.face.manufacturer) }.first
            )
        }
        families = Self.unifyingManufacturerCase(families)
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
            let changed = state.lastStamps.filter { found[$0.key]?.stamp != $0.value }.keys
            state.lastStamps = found.mapValues(\.stamp)
            return Set(changed)
        }
        return Library(families: families, unreadableFiles: unreadable, activePaths: activePaths, fingerprint: hasher.finalize(), changedPaths: changed,
                       unavailableFolders: reach.folders, onlineOnlyFiles: reach.onlineOnly, offlineFamilies: offline, offlinePaths: offlinePaths,
                       goneFiles: reach.goneFiles)
    }

    /// Active copies first — those Cicero can turn off before the rest, so the Problems view can offer Deactivate — then by path.
    /// Adobe Fonts only Adobe apps load come last: they stand for a font only when the library has no other copy of it,
    /// so one of the user's own stays theirs to switch.
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

    /// Where an active file is activated from, judged by its path and Cicero's records.
    static func activeSource(of path: String, locations: Locations, records: ActivationRecords) -> ActiveSource {
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Application Support/Apple/") { return .macOS }
        if locations.systemFonts.contains(where: { path.hasPrefix($0.path + "/") }) { return .macOS }
        if path.hasPrefix(locations.allUsersFonts.path + "/") { return .allUsers }
        if path.hasPrefix(locations.userFonts.path + "/") { return .fontsFolder }
        if ActiveSource.isAdobeFonts(path) { return .adobeFonts }
        if let temporary = records.temporary[path] { return .temporary(temporary.scope) }
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

    /// "Monotype" and "MONOTYPE" are one foundry: the spelling seen first (by family order) wins.
    static func unifyingManufacturerCase(_ families: [Family]) -> [Family] {
        var spellings: [String: String] = [:]
        return families.map { family in
            guard let manufacturer = family.manufacturer else { return family }
            let key = String(manufacturer.lowercased().filter { $0.isLetter || $0.isNumber })
            if let spelling = spellings[key] {
                guard spelling != manufacturer else { return family }
                return Family(name: family.name, faces: family.faces, state: family.state, folderIDs: family.folderIDs, manufacturer: spelling)
            }
            spellings[key] = manufacturer
            return family
        }
    }

    /// Finder order. A full `localizedStandardCompare` sort costs tens of milliseconds, so its result
    /// is remembered as ranks and reused while no new family name appears.
    private func sortedNames(_ names: [String]) -> [String] {
        state.withLock { state in
            if names.allSatisfy({ state.ranks[$0] != nil }) {
                return names.sorted { state.ranks[$0]! < state.ranks[$1]! }
            }
            // Sorted from a fixed starting order, so the result never depends on dictionary order.
            let sorted = names.sorted(by: <).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            state.ranks = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1, $0) })
            return sorted
        }
    }
}

/// Foundry names as the files give them, tidied for display.
public enum Foundry {
    private static let suffixes = [", Inc.", " Inc", " LLC", " Ltd.", " GmbH", " AG", " S.A.", " B.V.", " Corporation", " Corp."]

    /// Drops "Inc."/"LLC"/"GmbH"…, URLs, copyright lines and over-long strings; nil when nothing useful is left.
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
    /// `map` across all cores, for work done once per family that adds up to tens of milliseconds over a library.
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

/// Where `concurrentMap` puts its results: each iteration writes its own element, so the threads never share one.
private struct Slots<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
}
