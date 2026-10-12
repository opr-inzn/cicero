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

    public init(support: URL, caches: URL, userFonts: URL, allUsersFonts: URL) {
        self.support = support
        self.caches = caches
        self.userFonts = userFonts
        self.allUsersFonts = allUsersFonts
    }

    public static var standard: Locations {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return Locations(
            support: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cicero", isDirectory: true),
            caches: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Cicero", isDirectory: true),
            userFonts: home.appendingPathComponent("Library/Fonts", isDirectory: true),
            allUsersFonts: URL(fileURLWithPath: "/Library/Fonts", isDirectory: true)
        )
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

    public init(families: [Family], unreadableFiles: [String], activePaths: Set<String>, fingerprint: Int) {
        self.families = families
        self.unreadableFiles = unreadableFiles
        self.activePaths = activePaths
        self.fingerprint = fingerprint
        var index: [String: Int] = [:]
        for (position, family) in families.enumerated() { index[family.id] = position }
        self.index = index
        searchText = families.map { family in
            ([family.name, family.manufacturer ?? ""] + family.faces.map(\.face.postScriptName)).joined(separator: " ").lowercased()
        }
    }

    public static let empty = Library(families: [], unreadableFiles: [], activePaths: [], fingerprint: 0)

    private let index: [String: Int]
    private let searchText: [String]

    public func family(_ id: String) -> Family? {
        index[id].map { families[$0] }
    }

    public func position(of id: String) -> Int? { index[id] }

    /// Whether a family matches a search: name, foundry or a PostScript name contains the (lowercased) query.
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
public struct ScanInput: Sendable {
    public var folders: [WatchedFolder]
    public var records: ActivationRecords

    public init(folders: [WatchedFolder], records: ActivationRecords) {
        self.folders = folders
        self.records = records
    }
}


/// Finds every font file (CoreText's active fonts, ~/Library/Fonts, /Library/Fonts, the watched
/// folders and Cicero's Deactivated folder), reads new or changed files, and builds a `Library`.
/// Parsed faces and Date Added are cached in `Locations.caches` by path, modification date and size;
/// the decoded cache stays in memory between scans. Cancellation stops it between phases.
public final class LibraryScanner: Sendable {
    private let locations: Locations
    private let registrar: any FontRegistrar
    private let cacheURL: URL
    private let state = Mutex(State())

    private struct State {
        var files: [String: CachedFile] = [:]
        var loaded = false
        var dirty = false
        /// Finder-order positions from the last full sort, so scans with no new family skip `localizedStandardCompare`.
        var ranks: [String: Int] = [:]
        /// The last library built and a hash of what it was built from, so an unchanged rescan returns it as is.
        var last: (inputs: Int, library: Library)?
    }

    public convenience init(locations: Locations) {
        self.init(locations: locations, registrar: CoreTextRegistrar())
    }

    /// `registrar` supplies the system's active font files; tests pass a fake.
    public init(locations: Locations, registrar: any FontRegistrar) {
        self.locations = locations
        self.registrar = registrar
        cacheURL = locations.caches.appendingPathComponent("faces.cache", isDirectory: false)
    }

    @concurrent
    public func scan(_ input: ScanInput, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Library {
        progress(.finding)
        // Asking fontd for the active files takes ~100 ms, as long as walking the folders; do both at once.
        let registrar = registrar
        async let active = Self.activeFontURLs(registrar)
        var found = enumerateFolders(input)
        let known = loadCache()
        addActive(await active, to: &found)
        try Task.checkCancellation()

        let stale = found.filter { known[$0.key]?.stamp != $0.value.stamp }
        var parsed: [String: CachedFile] = [:]
        if !stale.isEmpty {
            progress(.identifying(done: 0, total: stale.count))
            parsed = try await Self.parse(stale, progress: progress)
        }
        try Task.checkCancellation()

        let files = updateCache(found: found, parsed: parsed)
        let inputs = Self.inputHash(found: found, records: input.records)
        if parsed.isEmpty, let last = state.withLock({ $0.last }), last.inputs == inputs {
            return last.library
        }
        let library = build(found: found, files: files, input: input)
        state.withLock { $0.last = (inputs, library) }
        saveCacheIfNeeded()
        return library
    }

    /// Forgets parsed faces so the next scan reads every file again.
    public func clearCache() {
        state.withLock {
            $0.files = [:]
            $0.loaded = true
            $0.dirty = true
            $0.last = nil
        }
    }

    /// Everything a build depends on besides the cached faces, combined in any order.
    private static func inputHash(found: [String: FoundFile], records: ActivationRecords) -> Int {
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
        for (path, record) in records.temporary {
            add { hasher in
                hasher.combine(path)
                hasher.combine(record.scope)
            }
        }
        return Int(bitPattern: UInt(sum))
    }

    // MARK: Finding

    struct FoundFile: Sendable {
        var stamp: FaceStamp
        var isActive: Bool
        var folderIDs: [UUID] = []
        var appName: String?
    }

    @concurrent
    private static func activeFontURLs(_ registrar: any FontRegistrar) async -> [URL] {
        registrar.activeFontURLs()
    }

    private func enumerateFolders(_ input: ScanInput) -> [String: FoundFile] {
        var found: [String: FoundFile] = [:]
        found.reserveCapacity(4096)
        for folder in [locations.userFonts, locations.allUsersFonts] {
            Self.enumerate(folder) { path, stamp in
                found[path] = FoundFile(stamp: stamp, isActive: true)
            }
        }
        let deactivated = WatchedFolder(id: WatchedFolder.deactivatedID, path: locations.deactivated.path)
        for folder in input.folders + [deactivated] {
            Self.enumerate(folder.url) { path, stamp in
                if found[path] == nil {
                    found[path] = FoundFile(stamp: stamp, isActive: false)
                }
                found[path]!.folderIDs.append(folder.id)
                if found[path]!.appName == nil { found[path]!.appName = folder.appName }
            }
        }
        return found
    }

    private func addActive(_ urls: [URL], to found: inout [String: FoundFile]) {
        for url in urls {
            let path = url.path(percentEncoded: false)
            if found[path] != nil {
                found[path]!.isActive = true
            } else if Self.isFontFile(path), let stamp = Self.stamp(ofPath: path) {
                found[path] = FoundFile(stamp: stamp, isActive: true)
            }
        }
    }

    private static func isFontFile(_ path: String) -> Bool {
        FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Every font file under a folder, except inside packages and hidden ones (AppleDouble "._" files look like fonts).
    /// Paths start with the folder's own path, as the user chose it, even when it goes through a symlink.
    private static func enumerate(_ folder: URL, _ body: (String, FaceStamp) -> Void) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        let chosen = folder.path + "/"
        let resolved = realPath(folder.path) + "/"
        for case let url as URL in enumerator {
            guard FontFileReader.fontExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let modified = values.contentModificationDate, let size = values.fileSize
            else { continue }
            var path = url.path(percentEncoded: false)
            if resolved != chosen, path.hasPrefix(resolved) { path = chosen + path.dropFirst(resolved.count) }
            body(path, FaceStamp(modified: modified, size: Int64(size)))
        }
    }

    /// The path with every symlink resolved, as the enumerator reports files (e.g. /private/var for /var).
    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func stamp(ofPath path: String) -> FaceStamp? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        return FaceStamp(modified: modified, size: Int64(info.st_size))
    }

    // MARK: Reading

    private static func parse(_ files: [String: FoundFile], progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [String: CachedFile] {
        let total = files.count
        var results: [String: CachedFile] = [:]
        results.reserveCapacity(total)
        try await withThrowingTaskGroup(of: (String, CachedFile).self) { group in
            var pending = files.map { ($0.key, $0.value.stamp) }[...]
            func addNext() {
                guard let (path, stamp) = pending.popFirst() else { return }
                group.addTask {
                    (path, CachedFile(stamp: stamp, dateAdded: FontFileReader.dateAdded(atPath: path), faces: FontFileReader.faces(atPath: path)))
                }
            }
            for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
            while let (path, file) = try await group.next() {
                results[path] = file
                if results.count % 200 == 0 || results.count == total {
                    progress(.identifying(done: results.count, total: total))
                }
                try Task.checkCancellation()
                addNext()
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

    /// Adds what was read, drops files that are gone, and returns the cache for the found files.
    private func updateCache(found: [String: FoundFile], parsed: [String: CachedFile]) -> [String: CachedFile] {
        state.withLock { state in
            let before = state.files.count
            state.files = state.files.filter { found[$0.key] != nil }
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

    // MARK: Building

    private struct FaceKey: Hashable {
        var family: String
        var postScriptName: String
    }

    private struct Candidate {
        var face: FontFace
        var state: FaceState
        var dateAdded: Date?
        var folderIDs: [UUID]
        var stamp: FaceStamp
    }

    private func build(found: [String: FoundFile], files: [String: CachedFile], input: ScanInput) -> Library {
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
                candidates[FaceKey(family: face.familyName, postScriptName: face.postScriptName), default: []].append(
                    Candidate(face: face, state: state, dateAdded: cached.dateAdded, folderIDs: file.folderIDs, stamp: cached.stamp)
                )
            }
        }

        // One face per PostScript name within a family: the active file wins, the others are its other
        // copies. Different families keep their own faces even when names clash (the Problems view says so).
        var byFamily: [String: [(LibraryFace, Set<UUID>, FaceStamp)]] = [:]
        for (_, copies) in candidates {
            let sorted = copies.sorted { Self.precedes($0, $1) }
            let winner = sorted[0]
            var others: [String] = []
            for copy in sorted.dropFirst() where copy.face.path != winner.face.path && !others.contains(copy.face.path) {
                others.append(copy.face.path)
            }
            let face = LibraryFace(face: winner.face, state: winner.state, otherCopies: others, dateAdded: sorted.compactMap(\.dateAdded).min())
            let folderIDs = Set(sorted.flatMap(\.folderIDs))
            byFamily[winner.face.familyName, default: []].append((face, folderIDs, winner.stamp))
        }

        var families: [Family] = []
        families.reserveCapacity(byFamily.count)
        var stamps: [FaceID: FaceStamp] = [:]
        let names = sortedNames(Array(byFamily.keys))
        for name in names {
            let members = byFamily[name]!
            let faces = members.map(\.0).sorted { a, b in
                if a.face.weight != b.face.weight { return a.face.weight < b.face.weight }
                if a.face.isItalic != b.face.isItalic { return !a.face.isItalic }
                if a.face.styleName != b.face.styleName { return a.face.styleName.caseInsensitiveCompare(b.face.styleName) == .orderedAscending }
                return a.face.id < b.face.id
            }
            for (face, _, stamp) in members { stamps[face.id] = stamp }
            families.append(Family(
                name: name, faces: faces, state: Self.familyState(of: faces),
                folderIDs: members.reduce(into: Set<UUID>()) { $0.formUnion($1.1) },
                manufacturer: faces.lazy.compactMap { Foundry.normalized($0.face.manufacturer) }.first
            ))
        }
        families = Self.unifyingManufacturerCase(families)
        unreadable.sort()

        var hasher = Hasher()
        for family in families {
            hasher.combine(family.id)
            hasher.combine(family.state)
            hasher.combine(family.manufacturer)
            hasher.combine(family.folderIDs)
            for face in family.faces {
                hasher.combine(face.id)
                hasher.combine(face.state)
                hasher.combine(face.otherCopies)
                hasher.combine(face.dateAdded)
                hasher.combine(stamps[face.id])
            }
        }
        hasher.combine(unreadable)
        let library = Library(families: families, unreadableFiles: unreadable, activePaths: activePaths, fingerprint: hasher.finalize())
        return library
    }

    /// Active copies first — those Cicero can turn off before the rest, so the Problems view can offer Deactivate — then by path.
    private static func precedes(_ a: Candidate, _ b: Candidate) -> Bool {
        let rankA = rank(a.state), rankB = rank(b.state)
        if rankA != rankB { return rankA < rankB }
        return a.face.id < b.face.id
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
        if let app = file.appName { return .appOnly(app) }
        return .inactive
    }

    /// Where an active file is activated from, judged by its path and Cicero's records.
    static func activeSource(of path: String, locations: Locations, records: ActivationRecords) -> ActiveSource {
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Application Support/Apple/") { return .macOS }
        if path.hasPrefix(locations.allUsersFonts.path + "/") { return .allUsers }
        if path.hasPrefix(locations.userFonts.path + "/") { return .fontsFolder }
        if path.contains("/Adobe/CoreSync/") { return .adobeFonts }
        if let temporary = records.temporary[path] { return .temporary(temporary.scope) }
        if records.inPlace.contains(path) { return .inPlace }
        if path.contains(".app/") { return .app }
        return .otherApp
    }

    private static func familyState(of faces: [LibraryFace]) -> FamilyState {
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
