import Foundation
import UniformTypeIdentifiers

/// Cicero's Font Library (see `UserData.fontLibraryPath`): a folder of its own, ~/Cicero/Library unless the user
/// moves it, where the fonts it installs go, a folder for each family, when the user chooses so. Fonts in it are
/// registered where they are, so it's anywhere but a Fonts folder, and turning one off leaves it there.
extension ActivationEngine {
    /// Not a file in the Inactive folder, also when the library holds it, as a library in ~/Cicero itself would.
    func isInFontLibrary(_ path: String) -> Bool {
        guard let fontLibrary else { return false }
        return path.hasPrefix(fontLibrary.path + "/") && !isInInactiveFolder(path)
    }

    func isInInactiveFolder(_ path: String) -> Bool {
        locations.isInInactiveFolder(path)
    }

    /// Where a copy of a file goes: right into ~/Library/Fonts, or into the folder of `family` in the Font Library (see
    /// `installsIntoFontLibrary`). Without a family, as for a file opened from the Finder, it's the family of the file's
    /// first font; a collection with fonts of several families goes with the one it's copied for.
    func installFolder(for path: String, family: String?) -> URL {
        guard installsIntoFontLibrary, let fontLibrary else { return locations.userFonts }
        let family = family ?? FontFileReader.faces(atPath: path).first?.familyName ?? ""
        let fallback = (Self.url(path).lastPathComponent as NSString).deletingPathExtension
        return fontLibrary.appendingPathComponent(Self.folderName(forFamily: family, fallback: fallback), isDirectory: true)
    }

    /// A family's folder in the Font Library: its name, with "/" and ":" (which the Finder shows as "/") as "-", without
    /// control characters, leading dots (they hide a folder, and the library leaves hidden folders out) or spaces around
    /// it, and short enough for a file name. An extension that would make the folder a package, which the library doesn't
    /// look inside, loses its dot: "Sans.app" is "Sans app". `fallback` (the file's name) when nothing is left, else
    /// "Untitled".
    static func folderName(forFamily family: String, fallback: String = "") -> String {
        var name = String(family.map { $0 == "/" || $0 == ":" ? "-" : $0 }
            .filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name = name.dropFirst().trimmingCharacters(in: .whitespaces) }
        // A file name can have 255 bytes.
        while name.utf8.count > 200 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) == true {
            name = (name as NSString).deletingPathExtension + " " + ext
        }
        guard name.isEmpty else { return name }
        return fallback.isEmpty ? "Untitled" : folderName(forFamily: fallback)
    }

    /// Once a file has left a family's folder in the Font Library, takes away the folders it was in that are left empty
    /// (but for the Finder's .DS_Store), up to the Font Library itself, which stays; never a folder with anything else in it.
    func removeEmptyFolders(around path: String) {
        guard let fontLibrary else { return }
        let root = fontLibrary.path
        var folder = (path as NSString).deletingLastPathComponent
        while folder.hasPrefix(root + "/"), Self.removeIfEmpty(folder) {
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    /// Takes away a folder with nothing in it but the Finder's .DS_Store; false when there's anything else, or it can't go.
    static func removeIfEmpty(_ folder: String) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder), items.allSatisfy({ $0 == ".DS_Store" }) else { return false }
        for item in items { try? fm.removeItem(atPath: (folder as NSString).appendingPathComponent(item)) }
        return rmdir(folder) == 0
    }

    /// Removes `folder` and the folders in it that have nothing in them but .DS_Store and such empty folders, as files
    /// moved out one by one leave them. Returns whether `folder` is gone.
    @discardableResult
    static func removeEmptyFolders(_ folder: String) -> Bool {
        guard isFolder(folder) else { return false }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
            let path = (folder as NSString).appendingPathComponent(name)
            if isFolder(path) { removeEmptyFolders(path) }
        }
        return removeIfEmpty(folder)
    }

    /// Whether a folder has a font file in it, at any depth, not counting hidden ones or what's inside packages, as the
    /// scan reads it: whether the Font Library has fonts to keep listed.
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

    /// Moves the Font Library into `destination`, an empty folder (see `refusal`), which it takes the place of: the whole
    /// folder moves, a rename on the same disk, or file by file onto another one. Its fonts that are on go off for the moment that takes and on again there,
    /// and the records follow. When the library was in its first place, ~/Cicero goes too, once nothing is left in it.
    /// One that can't move stays where it was, as it was, with its path in `failed`. A library that holds the Inactive
    /// folder, as one in ~/Cicero itself does, moves item by item instead, and the Inactive folder stays where it is.
    @concurrent
    public func moveFontLibrary(to destination: URL, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        var records = records
        let place = (destination.path as NSString).abbreviatingWithTildeInPath
        guard let fontLibrary, fm.fileExists(atPath: fontLibrary.path) else {
            // Nothing in it yet: it's just somewhere else from now on.
            return ActivationResult(records: records, succeeded: 0, failed: [], message: "Cicero’s Library moved to \(place)")
        }
        let old = fontLibrary.path, new = destination.path
        let failure = ActivationResult(records: records, succeeded: 0, failed: [old], message: "Couldn’t move Cicero’s Library to \(place)")
        let held = locations.inactiveFolders.map(\.path).filter { $0.hasPrefix(old + "/") }
        // Only one right in it, which leaves everything beside it to move.
        guard held.allSatisfy({ ($0 as NSString).deletingLastPathComponent == old }) else { return failure }
        func isLibrary(_ path: String) -> Bool { path.hasPrefix(old + "/") && !isInInactiveFolder(path) }
        func moved(_ path: String) -> String { isLibrary(path) ? new + path.dropFirst(old.count) : path }
        let persistent = records.inPlace.filter(isLibrary).sorted()
        let session = records.temporary.keys.filter(isLibrary).sorted()
        func register(_ paths: (String) -> String) async {
            if !persistent.isEmpty { _ = await registrar.register(persistent.map { Self.url(paths($0)) }, scope: .persistent) }
            if !session.isEmpty { _ = await registrar.register(session.map { Self.url(paths($0)) }, scope: .session) }
        }
        // The folder chosen goes, for the library to take its place, only when there's nothing in it.
        guard !fm.fileExists(atPath: new) || Self.removeIfEmpty(new) else { return failure }
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }
        // The whole folder, a rename on the same disk; onto another disk what's in it, file by file (see `moveItems`).
        var whole = false
        if held.isEmpty {
            do {
                try Self.moveItem(Self.url(old), to: Self.url(new))
                whole = true
            } catch let error as POSIXError where error.code == .EXDEV {
                // Onto another disk.
            } catch {
                try? fm.createDirectory(atPath: new, withIntermediateDirectories: true)
                await register { $0 }
                return failure
            }
        }
        if !whole {
            guard Self.moveItems(in: old, to: new, except: Set(held.map { ($0 as NSString).lastPathComponent })) else {
                if held.isEmpty { try? fm.createDirectory(atPath: new, withIntermediateDirectories: true) }
                await register { $0 }
                return failure
            }
            if held.isEmpty { Self.removeEmptyFolders(old) }
        }
        records.installedCopies = Dictionary(records.installedCopies.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        records.inPlace = Set(records.inPlace.map(moved))
        records.temporary = Dictionary(records.temporary.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        await register(moved)
        let firstPlaces = [locations.defaultFontLibrary, locations.formerDefaultFontLibrary].map(\.standardizedFileURL.path)
        if firstPlaces.contains(fontLibrary.standardizedFileURL.path) {
            _ = Self.removeIfEmpty(fontLibrary.deletingLastPathComponent().path)
        }
        return ActivationResult(records: records, succeeded: 1, failed: [], message: "Cicero’s Library moved to \(place)")
    }

    /// Moves what's in `old` into `new`, made for it, but for the items named in `kept` and .DS_Store; all or nothing:
    /// when one can't move, those that did go back, and `new` goes again. Onto another disk, file by file (see
    /// `fileMoves`), so a folder is never left half gone; the folders they leave go once they're empty.
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

    /// Moves a Font Library still in its former first place, ~/Cicero/Font Library, to today's, ~/Cicero/Library, as
    /// `moveFontLibrary` does: the whole folder, so the old one is gone, with its fonts' registrations and the records.
    /// nil, with nothing changed, for a library somewhere else (the user moved it), when something is in ~/Cicero/Library
    /// already, or when the move fails. With no library folder yet, only its place changes (`succeeded` 0).
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

    /// Why the Font Library can't go into a folder, said to the user; nil when it can. Not a Fonts folder, where macOS
    /// turns on every font by itself, nor Cicero's own folders, macOS's or an app's, nor the library itself, the folder
    /// it's in or a folder in it, nor one the library reads already (`folders`, the user's and the ones apps load). A
    /// folder with other things in it is fine: the library goes into a new folder there (see `fontLibraryFolder`). So is
    /// a cloud service's, after a warning (see `cloudService`).
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
        // An empty one the library would take the place of, which the Inactive folder is in, or would be once made.
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

    /// A cloud service that keeps a folder's files: one the Font Library may go into only after a warning, since the
    /// service can take files off the Mac to make room, and fonts used from there can stop working.
    public enum CloudService: Equatable, Sendable {
        /// ~/Library/Mobile Documents, or anything iCloud keeps, as Desktop & Documents.
        case iCloudDrive
        /// ~/Library/CloudStorage: Dropbox, Google Drive, OneDrive and the like.
        case other
    }

    /// The cloud service `folder` syncs with, by its path or the one a symbolic link leads to; nil when it stays on the Mac.
    public static func cloudService(syncing folder: URL) -> CloudService? {
        let paths = [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path].map { $0 + "/" }
        if (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
            || paths.contains(where: { $0.contains("/Library/Mobile Documents/") }) {
            return .iCloudDrive
        }
        return paths.contains { $0.contains("/Library/CloudStorage/") } ? .other : nil
    }

    /// The folder the Font Library goes to when the user chooses `folder`: that one, when nothing but .DS_Store is in it,
    /// as a folder made for the library; otherwise a new "Cicero Library" folder in it ("Cicero Library 2" and so on when
    /// the name is taken), so the library holds only what Cicero puts in it.
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
