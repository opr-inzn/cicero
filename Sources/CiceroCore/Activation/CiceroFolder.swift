import Foundation
import UniformTypeIdentifiers

/// Cicero's folder in ~/Library/Fonts (see `Locations.ciceroFolder`), where the fonts it installs go, a folder for each
/// family, when the user keeps them together.
extension ActivationEngine {
    /// Where a copy of a file goes: right into ~/Library/Fonts, or into the folder of `family` in Cicero's folder (see
    /// `installsIntoCiceroFolder`). Without a family, as for a file opened from the Finder, it's the family of the file's
    /// first font; a collection with fonts of several families goes with the one it's copied for.
    func installFolder(for path: String, family: String?) -> URL {
        guard installsIntoCiceroFolder else { return locations.userFonts }
        let family = family ?? FontFileReader.faces(atPath: path).first?.familyName ?? ""
        let fallback = (Self.url(path).lastPathComponent as NSString).deletingPathExtension
        return locations.ciceroFolder.appendingPathComponent(Self.folderName(forFamily: family, fallback: fallback), isDirectory: true)
    }

    /// A family's folder in Cicero's folder: its name, with "/" and ":" (which the Finder shows as "/") as "-", without
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

    /// Once a file has left a family's folder in Cicero's folder, takes away the folders it was in that are left empty
    /// (but for the Finder's .DS_Store), up to Cicero's folder itself; never ~/Library/Fonts, nor a folder with anything
    /// else in it.
    func removeEmptyFolders(around path: String) {
        let fm = FileManager.default
        let root = locations.ciceroFolder.path
        var folder = (path as NSString).deletingLastPathComponent
        while folder == root || folder.hasPrefix(root + "/") {
            guard let items = try? fm.contentsOfDirectory(atPath: folder), items.allSatisfy({ $0 == ".DS_Store" }) else { return }
            for item in items { try? fm.removeItem(atPath: (folder as NSString).appendingPathComponent(item)) }
            guard rmdir(folder) == 0 else { return }
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    /// The copies Cicero installed that aren't where it puts copies now (see `installsIntoCiceroFolder`): right in
    /// ~/Library/Fonts while they go into Cicero's folder, or in Cicero's folder while they don't. Never a file the user
    /// put in ~/Library/Fonts.
    public func misplacedCopies(in records: ActivationRecords) -> [String] {
        let fonts = locations.userFonts.path + "/", cicero = locations.ciceroFolder.path + "/"
        return records.installedCopies.keys.filter { $0.hasPrefix(fonts) && $0.hasPrefix(cicero) != installsIntoCiceroFolder }.sorted()
    }

    /// Moves copies Cicero installed to where it puts copies now (see `misplacedCopies`), each into the folder of the
    /// family `families` gives it, else of its first font. One that's on goes off while it moves, as macOS would see it
    /// go anyway, and on again in its new place; one that can't move stays where it was, as it was. Folders left empty in
    /// Cicero's folder go.
    @concurrent
    public func moveInstalledCopies(_ paths: [String], families: [String: String], records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        var records = records
        let paths = paths.filter { records.installedCopies[$0] != nil && fm.fileExists(atPath: $0) }
        let wasActive = paths.filter { registrar.isActive(Self.url($0)) }
        _ = await registrar.unregister(wasActive.map(Self.url), scope: .persistent)
        var moved: [String: String] = [:]
        var failed: [String] = []
        for path in paths {
            let folder = installFolder(for: path, family: families[path])
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: folder)
                try fm.moveItem(at: Self.url(path), to: destination)
                records.installedCopies[destination.path] = records.installedCopies.removeValue(forKey: path)
                moved[path] = destination.path
                removeEmptyFolders(around: path)
            } catch {
                failed.append(path)
            }
        }
        _ = await registrar.register(wasActive.map { Self.url(moved[$0] ?? $0) }, scope: .persistent)
        let place = installsIntoCiceroFolder ? "the Cicero folder" : "your Fonts folder"
        let message = if failed.isEmpty, let names = FontNames.describe(FontNames.fonts(inFiles: moved.values.sorted())) {
            "\(names) moved into \(place)"
        } else {
            Self.message("Moved", "move", succeeded: moved.count, failed: failed.count)
        }
        return ActivationResult(records: records, succeeded: moved.count, failed: failed, message: message)
    }
}
