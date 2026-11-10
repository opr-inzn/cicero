import Foundation
import UniformTypeIdentifiers

extension ActivationEngine {
    func isInFontLibrary(_ path: String) -> Bool {
        guard let fontLibrary else { return false }
        return path.hasPrefix(fontLibrary.path + "/") && !isInInactiveFolder(path)
    }

    func isInInactiveFolder(_ path: String) -> Bool {
        locations.isInInactiveFolder(path)
    }

    func installFolder(for path: String, family: String?) -> URL {
        guard installsIntoFontLibrary, let fontLibrary else { return locations.userFonts }
        let family = family ?? FontFileReader.faces(atPath: path).first?.familyName ?? ""
        let fallback = (Self.url(path).lastPathComponent as NSString).deletingPathExtension
        return fontLibrary.appendingPathComponent(Self.folderName(forFamily: family, fallback: fallback), isDirectory: true)
    }

    static func folderName(forFamily family: String, fallback: String = "") -> String {
        // ":" too, which the Finder shows as "/".
        var name = String(family.map { $0 == "/" || $0 == ":" ? "-" : $0 }
            .filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name = name.dropFirst().trimmingCharacters(in: .whitespaces) }
        while name.utf8.count > 200 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        let ext = (name as NSString).pathExtension
        // An extension like ".app" would make the folder a package, which the scan doesn't look inside.
        if !ext.isEmpty, UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) == true {
            name = (name as NSString).deletingPathExtension + " " + ext
        }
        guard name.isEmpty else { return name }
        return fallback.isEmpty ? "Untitled" : folderName(forFamily: fallback)
    }

    func removeEmptyFolders(around path: String) {
        guard let fontLibrary else { return }
        let root = fontLibrary.path
        var folder = (path as NSString).deletingLastPathComponent
        while folder.hasPrefix(root + "/"), Self.removeIfEmpty(folder) {
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    static func removeIfEmpty(_ folder: String) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder), items.allSatisfy({ $0 == ".DS_Store" }) else { return false }
        for item in items { try? fm.removeItem(atPath: (folder as NSString).appendingPathComponent(item)) }
        return rmdir(folder) == 0
    }

    @discardableResult
    static func removeEmptyFolders(_ folder: String) -> Bool {
        guard isFolder(folder) else { return false }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
            let path = (folder as NSString).appendingPathComponent(name)
            if isFolder(path) { removeEmptyFolders(path) }
        }
        return removeIfEmpty(folder)
    }

    public static func hasFontFiles(in folder: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in enumerator where FontFileReader.fontExtensions.contains(url.pathExtension.lowercased()) {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        }
        return false
    }

    // MARK: Moving the library

    @concurrent
    public func moveFontLibrary(to destination: URL, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        var records = records
        let place = (destination.path as NSString).abbreviatingWithTildeInPath
        // A new move would write over the journal of one not yet put back, and lose the files still to go back.
        if let fontLibrary, hasLibraryMove, await !finishLibraryMove(libraryPath: fontLibrary.path, records: records) {
            return ActivationResult(records: records, succeeded: 0, failed: [fontLibrary.path],
                                    message: "Couldn’t move Cicero’s Library to \(place): an earlier move isn’t finished. Check that its disk is connected.")
        }
        guard let fontLibrary, fm.fileExists(atPath: fontLibrary.path) else {
            return ActivationResult(records: records, succeeded: 0, failed: [], message: "Cicero’s Library moved to \(place)")
        }
        let old = fontLibrary.path, new = destination.path
        let failure = ActivationResult(records: records, succeeded: 0, failed: [old], message: "Couldn’t move Cicero’s Library to \(place)")
        let held = locations.inactiveFolders.map(\.path).filter { $0.hasPrefix(old + "/") }
        guard held.allSatisfy({ ($0 as NSString).deletingLastPathComponent == old }) else { return failure }
        func isLibrary(_ path: String) -> Bool { path.hasPrefix(old + "/") && !isInInactiveFolder(path) }
        func moved(_ path: String) -> String { isLibrary(path) ? new + path.dropFirst(old.count) : path }
        let persistent = records.inPlace.filter(isLibrary).sorted()
        let session = records.temporary.keys.filter(isLibrary).sorted()
        let newWasThere = Self.exists(new)
        if newWasThere {
            guard let items = try? fm.contentsOfDirectory(atPath: new), items.allSatisfy({ $0 == ".DS_Store" }) else { return failure }
        }
        let move = LibraryMove(old: old, new: new, kept: held.map { ($0 as NSString).lastPathComponent }.sorted(),
                               newWasThere: newWasThere, persistent: persistent, session: session)
        guard (try? noteLibraryMove(move)) != nil else { return failure }
        func failed() async -> ActivationResult {
            _ = await finishLibraryMove(libraryPath: old, records: records)
            return failure
        }
        guard !newWasThere || Self.removeIfEmpty(new) else { return await failed() }
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }
        var whole = false
        if held.isEmpty {
            do {
                try Self.moveItem(Self.url(old), to: Self.url(new))
                whole = true
            } catch let error as POSIXError where error.code == .EXDEV {
            } catch {
                return await failed()
            }
        }
        if !whole {
            guard Self.moveItems(in: old, to: new, except: Set(move.kept)) else { return await failed() }
            if held.isEmpty { Self.removeEmptyFolders(old) }
        }
        records.installedCopies = Dictionary(records.installedCopies.map { (moved($0.key), moved($0.value)) }, uniquingKeysWith: { first, _ in first })
        records.inPlace = Set(records.inPlace.map(moved))
        records.temporary = Dictionary(records.temporary.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        if !persistent.isEmpty { _ = await registrar.register(persistent.map { Self.url(moved($0)) }, scope: .persistent) }
        if !session.isEmpty { _ = await registrar.register(session.map { Self.url(moved($0)) }, scope: .session) }
        let firstPlaces = [locations.defaultFontLibrary, locations.formerDefaultFontLibrary].map(\.standardizedFileURL.path)
        if firstPlaces.contains(fontLibrary.standardizedFileURL.path) {
            _ = Self.removeIfEmpty(fontLibrary.deletingLastPathComponent().path)
        }
        return ActivationResult(records: records, succeeded: 1, failed: [], message: "Cicero’s Library moved to \(place)")
    }

    static func moveItems(in old: String, to new: String, except kept: Set<String>) -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: old),
              (try? fm.createDirectory(atPath: new, withIntermediateDirectories: true)) != nil
        else { return false }
        let items = names.sorted().filter { !kept.contains($0) && $0 != ".DS_Store" }.map {
            (from: url((old as NSString).appendingPathComponent($0)), to: url((new as NSString).appendingPathComponent($0)))
        }
        let otherDisk = disk(of: new) != disk(of: old)
        var done: [(from: URL, to: URL)] = []
        // Onto another disk file by file, so a folder is never left half gone.
        for (from, to) in otherDisk ? items.flatMap({ fileMoves($0.from, to: $0.to) }) : items {
            do {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try moveItem(from, to: to)
                done.append((from, to))
            } catch {
                for (from, to) in done.reversed() {
                    try? fm.createDirectory(at: from.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? moveItem(to, to: from)
                }
                removeEmptyFolders(new)
                return false
            }
        }
        if otherDisk { for item in items { removeEmptyFolders(item.from.path) } }
        return true
    }

    // MARK: A move that stopped

    var libraryMoveJournal: URL { locations.support.appendingPathComponent("moving-library.json", isDirectory: false) }

    public var hasLibraryMove: Bool { FileManager.default.fileExists(atPath: libraryMoveJournal.path) }

    func noteLibraryMove(_ move: LibraryMove) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(move).write(to: libraryMoveJournal, options: .atomic)
        // On the disk itself before anything goes off, so a power cut can't leave the move without it.
        guard UserDataStore.syncToDisk(libraryMoveJournal) else { throw POSIXError(.EIO) }
    }

    public func forgetLibraryMove() {
        try? FileManager.default.removeItem(at: libraryMoveJournal)
    }

    @concurrent
    @discardableResult
    public func finishLibraryMove(libraryPath: String, records: ActivationRecords) async -> Bool {
        guard let data = try? Data(contentsOf: libraryMoveJournal), let move = try? JSONDecoder().decode(LibraryMove.self, from: data) else {
            forgetLibraryMove()
            return true
        }
        func standard(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
        let saved = standard(libraryPath)
        let done: Bool
        if saved == standard(move.new) {
            done = Self.diskIsThere(move.new)
            if done { Self.removeHalfCopies(in: move.new, except: []) }
        } else if saved == standard(move.old) {
            done = await undo(move, records: records)
        } else {
            done = true
        }
        if done { forgetLibraryMove() }
        return done
    }

    private func undo(_ move: LibraryMove, records: ActivationRecords) async -> Bool {
        let fm = FileManager.default
        let old = move.old, new = move.new
        guard Self.diskIsThere(old) else { return false }
        func moved(_ path: String) -> String { new + path.dropFirst(old.count) }
        func isOn(_ path: String) -> Bool { Self.exists(path) && registrar.isActive(Self.url(path)) }
        var complete = Self.diskIsThere(new)
        if complete {
            let persistent = move.persistent.map(moved).filter(isOn), session = move.session.map(moved).filter(isOn)
            if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
            if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }
            Self.removeHalfCopies(in: old, except: Set(move.kept))
            Self.removeHalfCopies(in: new, except: [])
            if Self.isFolder(new) {
                let whole = (!Self.exists(old) || Self.removeIfEmpty(old))
                    && (try? fm.createDirectory(atPath: (old as NSString).deletingLastPathComponent, withIntermediateDirectories: true)) != nil
                    && Self.renameExclusively(new, to: old)
                if !whole {
                    for (from, to) in Self.fileMoves(Self.url(new), to: Self.url(old)) {
                        if Self.exists(to.path) {
                            if ActivationEngine.isIdenticalCopy(from.path, of: to.path), (try? fm.removeItem(at: from)) != nil { continue }
                        }
                        let target = Self.exists(to.path) ? Self.uniqueURL(for: to.lastPathComponent, in: to.deletingLastPathComponent()) : to
                        do {
                            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try Self.moveItem(from, to: target)
                        } catch {
                            complete = false
                        }
                    }
                    Self.removeEmptyFolders(new)
                }
            }
            if move.newWasThere { try? fm.createDirectory(atPath: new, withIntermediateDirectories: true) }
        }
        func lost(_ path: String) -> Bool { Self.exists(path) && !registrar.isActive(Self.url(path)) }
        let persistent = move.persistent.filter { records.inPlace.contains($0) && lost($0) }
        let session = move.session.filter { records.temporary[$0] != nil && lost($0) }
        if !persistent.isEmpty { _ = await registrar.register(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.register(session.map(Self.url), scope: .session) }
        return complete
    }

    static func removeHalfCopies(in folder: String, except kept: Set<String>) {
        let fm = FileManager.default
        for name in ((try? fm.contentsOfDirectory(atPath: folder)) ?? []) where !kept.contains(name) {
            let path = (folder as NSString).appendingPathComponent(name)
            if name.hasPrefix(movingPrefix) {
                unlock(url(path))
                try? fm.removeItem(atPath: path)
            } else if isFolder(path) {
                removeHalfCopies(in: path, except: [])
            }
        }
    }

    static func diskIsThere(_ path: String) -> Bool {
        let parts = (URL(fileURLWithPath: path).standardizedFileURL.path as NSString).pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return true }
        let volume = "/Volumes/" + parts[2]
        guard let disk = disk(of: volume) else { return false }
        // A folder can be left in /Volumes where a disk was mounted: it's on the same disk as /Volumes then.
        return disk != Self.disk(of: "/Volumes")
    }

    @concurrent
    public func moveFromFormerPlace(records: ActivationRecords) async -> ActivationResult? {
        let former = locations.formerDefaultFontLibrary.standardizedFileURL, new = locations.defaultFontLibrary.standardizedFileURL
        guard let fontLibrary, fontLibrary.standardizedFileURL.path == former.path, former.path != new.path else { return nil }
        let fm = FileManager.default
        if fm.fileExists(atPath: new.path) {
            guard let items = try? fm.contentsOfDirectory(atPath: new.path), items.allSatisfy({ $0 == ".DS_Store" }) else { return nil }
        }
        let result = await moveFontLibrary(to: new, records: records)
        return result.failed.isEmpty ? result : nil
    }

    public static func refusal(forFontLibraryAt folder: URL, current: URL?, folders: [WatchedFolder], locations: Locations) -> String? {
        let fm = FileManager.default
        let path = folder.standardizedFileURL.path
        let resolved = folder.resolvingSymlinksInPath().path
        func isIn(_ other: String) -> Bool {
            [path, resolved].contains { $0 == other || $0.hasPrefix(other + "/") }
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return "Choose a folder." }
        if ([locations.userFonts, locations.allUsersFonts] + locations.systemFonts).contains(where: { isIn($0.path) }) {
            return "macOS turns on every font in a Fonts folder by itself, so Cicero couldn’t turn the library’s fonts off."
        }
        if [locations.support, locations.caches, locations.inactiveFolder].contains(where: { isIn($0.path) }) {
            return "Cicero keeps that folder for itself."
        }
        let inactive = [locations.inactiveFolder.standardizedFileURL.path, locations.inactiveFolder.resolvingSymlinksInPath().path]
        if inactive.contains(where: { $0.hasPrefix(path + "/") || $0.hasPrefix(resolved + "/") }),
           (try? fm.contentsOfDirectory(atPath: path))?.allSatisfy({ $0 == ".DS_Store" }) == true {
            return "Cicero keeps its Inactive folder in “\(folder.lastPathComponent)”. Choose another folder, or make a new one in it."
        }
        if isProtected(path + "/") {
            return "macOS or an app keeps that folder for itself."
        }
        if let current {
            let places = [current.standardizedFileURL, current.resolvingSymlinksInPath()]
            if places.contains(where: { [path, resolved].contains($0.path) || [path, resolved].contains($0.deletingLastPathComponent().path) }) {
                return "Cicero’s Library is there already."
            }
            if places.contains(where: { isIn($0.path) }) { return "That folder is in Cicero’s Library." }
        }
        if let watched = folders.first(where: { $0.id != WatchedFolder.fontLibraryID && isIn($0.path) }) {
            return "That folder is in \(watched.displayName), which your library reads already. Choose one outside your locations."
        }
        guard (try? fm.contentsOfDirectory(atPath: path)) != nil else { return "Cicero can’t read that folder." }
        guard fm.isWritableFile(atPath: path) else { return "Cicero can’t make changes in that folder." }
        return nil
    }

    public enum CloudService: Equatable, Sendable {
        case iCloudDrive
        case other
    }

    public static func cloudService(syncing folder: URL) -> CloudService? {
        let paths = [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path].map { $0 + "/" }
        if (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
            || paths.contains(where: { $0.contains("/Library/Mobile Documents/") }) {
            return .iCloudDrive
        }
        return paths.contains { $0.contains("/Library/CloudStorage/") } ? .other : nil
    }

    public static func fontLibraryFolder(in folder: URL) -> URL {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: folder.path), items.allSatisfy({ $0 == ".DS_Store" }) { return folder }
        var name = "Cicero Library", number = 1
        while (try? fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)) != nil {
            number += 1
            name = "Cicero Library \(number)"
        }
        return folder.appendingPathComponent(name, isDirectory: true)
    }
}

struct LibraryMove: Codable, Equatable, Sendable {
    var old: String
    var new: String
    var kept: [String]
    var newWasThere: Bool
    var persistent: [String]
    var session: [String]
}
