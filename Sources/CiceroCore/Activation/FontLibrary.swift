import Foundation
import UniformTypeIdentifiers

/// Cicero's Font Library (see `UserData.fontLibraryPath`): a folder of its own, ~/Cicero/Font Library unless the user
/// moves it, where the fonts it installs go, a folder for each family, when the user chooses so. Fonts in it are
/// registered where they are, so it's anywhere but a Fonts folder, and turning one off leaves it there.
extension ActivationEngine {
    func isInFontLibrary(_ path: String) -> Bool {
        guard let fontLibrary else { return false }
        return path.hasPrefix(fontLibrary.path + "/")
    }

    func isInDeactivatedFolder(_ path: String) -> Bool {
        path.hasPrefix(locations.deactivated.path + "/")
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

    // MARK: Fonts installed before

    /// The copies Cicero installed right in ~/Library/Fonts, while fonts go into the Font Library: they can move there.
    /// Never a file the user put in ~/Library/Fonts; none while fonts go into ~/Library/Fonts.
    public func misplacedCopies(in records: ActivationRecords) -> [String] {
        guard installsIntoFontLibrary, fontLibrary != nil else { return [] }
        let fonts = locations.userFonts.path + "/"
        return records.installedCopies.keys.filter { $0.hasPrefix(fonts) }.sorted()
    }

    /// Moves copies Cicero installed in ~/Library/Fonts into the Font Library (see `misplacedCopies`), each into the folder
    /// of the family `families` gives it, else of its first font. One that's on goes off while it moves, as macOS would see
    /// it go anyway, and is registered where it is now; one that can't move stays where it was, as it was.
    @concurrent
    public func moveInstalledCopies(_ paths: [String], families: [String: String], records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        var records = records
        guard installsIntoFontLibrary, fontLibrary != nil else { return ActivationResult(records: records, succeeded: 0, failed: [], message: "") }
        let paths = paths.filter { records.installedCopies[$0] != nil && fm.fileExists(atPath: $0) }
        let wasActive = paths.filter { registrar.isActive(Self.url($0)) }
        if !wasActive.isEmpty { _ = await registrar.unregister(wasActive.map(Self.url), scope: .persistent) }
        var moved: [String: String] = [:]
        var failed: [String] = []
        for path in paths {
            let folder = installFolder(for: path, family: families[path])
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: folder)
                try Self.move(Self.url(path), to: destination)
                records.installedCopies[destination.path] = records.installedCopies.removeValue(forKey: path)
                moved[path] = destination.path
            } catch {
                // The family's folder, if it was made for nothing.
                removeEmptyFolders(around: folder.appendingPathComponent(Self.url(path).lastPathComponent).path)
                failed.append(path)
            }
        }
        if !wasActive.isEmpty { _ = await registrar.register(wasActive.map { Self.url(moved[$0] ?? $0) }, scope: .persistent) }
        for path in wasActive { if let new = moved[path] { records.inPlace.insert(new) } }
        let message = if failed.isEmpty, let names = FontNames.describe(FontNames.fonts(inFiles: moved.values.sorted())) {
            "\(names) moved into your Font Library"
        } else {
            Self.message("Moved", "move", succeeded: moved.count, failed: failed.count)
        }
        return ActivationResult(records: records, succeeded: moved.count, failed: failed, message: message)
    }

    // MARK: Moving the library

    /// Moves the Font Library into `destination`, an empty folder (see `refusal`), which it takes the place of: the whole
    /// folder moves, a rename on the same disk. Its fonts that are on go off for the moment that takes and on again there,
    /// and the records follow. When the library was in its first place, ~/Cicero goes too, once nothing is left in it.
    /// One that can't move stays where it was, as it was, with its path in `failed`.
    @concurrent
    public func moveFontLibrary(to destination: URL, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        var records = records
        let place = (destination.path as NSString).abbreviatingWithTildeInPath
        guard let fontLibrary, fm.fileExists(atPath: fontLibrary.path) else {
            // Nothing in it yet: it's just somewhere else from now on.
            return ActivationResult(records: records, succeeded: 0, failed: [], message: "Font Library moved to \(place)")
        }
        let old = fontLibrary.path, new = destination.path
        func moved(_ path: String) -> String { path.hasPrefix(old + "/") ? new + path.dropFirst(old.count) : path }
        let persistent = records.inPlace.filter { $0.hasPrefix(old + "/") }.sorted()
        let session = records.temporary.keys.filter { $0.hasPrefix(old + "/") }.sorted()
        func register(_ paths: (String) -> String) async {
            if !persistent.isEmpty { _ = await registrar.register(persistent.map { Self.url(paths($0)) }, scope: .persistent) }
            if !session.isEmpty { _ = await registrar.register(session.map { Self.url(paths($0)) }, scope: .session) }
        }
        let failure = ActivationResult(records: records, succeeded: 0, failed: [old], message: "Couldn’t move the Font Library to \(place)")
        // The folder chosen goes, for the library to take its place, only when there's nothing in it.
        guard !fm.fileExists(atPath: new) || Self.removeIfEmpty(new) else { return failure }
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }
        do {
            try fm.moveItem(atPath: old, toPath: new)
        } catch _ where fm.fileExists(atPath: old) {
            // Anything there now is what a move to another disk had copied before it stopped.
            try? fm.removeItem(atPath: new)
            try? fm.createDirectory(atPath: new, withIntermediateDirectories: true)
            await register { $0 }
            return failure
        } catch {
            // Gone from where it was, so moved after all.
        }
        records.installedCopies = Dictionary(records.installedCopies.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        records.inPlace = Set(records.inPlace.map(moved))
        records.temporary = Dictionary(records.temporary.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        await register(moved)
        if fontLibrary.standardizedFileURL.path == locations.defaultFontLibrary.standardizedFileURL.path {
            _ = Self.removeIfEmpty(fontLibrary.deletingLastPathComponent().path)
        }
        return ActivationResult(records: records, succeeded: 1, failed: [], message: "Font Library moved to \(place)")
    }

    /// Why the Font Library can't go into a folder, said to the user; nil when it can. Not a Fonts folder, where macOS
    /// turns on every font by itself, nor Cicero's own folders, macOS's or an app's, nor the library itself or a folder in
    /// it, nor one the library reads already (`folders`, the user's and the ones apps load). Not iCloud Drive or another
    /// cloud service's folder either: it can take files off the Mac to make room, and fonts used from there stop working.
    /// And only an empty folder, so the library holds only what Cicero puts in it.
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
        if [locations.support, locations.caches].contains(where: { isIn($0.path) }) {
            return "Cicero keeps that folder for itself."
        }
        if isProtected(path + "/") {
            return "macOS or an app keeps that folder for itself."
        }
        if let current {
            if path == current.standardizedFileURL.path || resolved == current.resolvingSymlinksInPath().path { return "The Font Library is there already." }
            if isIn(current.standardizedFileURL.path) || isIn(current.resolvingSymlinksInPath().path) { return "That folder is in the Font Library." }
        }
        if let watched = folders.first(where: { $0.id != WatchedFolder.fontLibraryID && isIn($0.path) }) {
            return "That folder is in \(watched.displayName), which your library reads already. Choose one outside your locations."
        }
        let synced = (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
        if synced || ["/Library/Mobile Documents/", "/Library/CloudStorage/"].contains(where: { (path + "/").contains($0) }) {
            return "iCloud Drive and other cloud services can take files off this Mac to make room, and fonts used from there stop working. Choose a folder that stays on this Mac."
        }
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return "Cicero can’t read that folder." }
        guard items.allSatisfy({ $0 == ".DS_Store" }) else {
            return "Choose an empty folder, or make a new one: the Font Library holds only the fonts Cicero puts in it."
        }
        guard fm.isWritableFile(atPath: path) else { return "Cicero can’t make changes in that folder." }
        return nil
    }
}
