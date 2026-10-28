import Foundation

/// Reads FontBase's library. FontBase keeps one folder of fonts (`~/FontBase` unless moved, its `rootFolder`) and
/// names each font by its PostScript name. It turns a font on by copying it to `~/Library/Fonts/FontBase/<PostScript
/// name>.<ext>`, and, as it's set to at first, deletes the copies when it quits and makes them again when it opens: so
/// what's on is what it remembers, not what's in that folder.
///
/// It remembers everything in IndexedDB (an Electron app's, in `~/Library/Application Support/FontBase`): the database
/// "fontbase", object store "fontbase_db", one value per part of its state. `fontbase_settings.rootFolder`;
/// `fontbase_pathsAll`, each file by its path under the folder (`id` its PostScript name, `url` where a provider's font
/// is downloaded from); `fontbase_fontsAll`, each font's names; `fontbase_fontsStatus`, the path of each font that's on;
/// `fontbase_collectionsAll`, its collections (`query.ids` their fonts; All, Recent, Active and Inactive are filters, of
/// type "default"; Favorites is type "favorites"); `fontbase_fontsTagsUser`, the user's tags of each font.
///
/// FontBase writes these while it runs, a moment after each change, and last when it quits: read once it has quit.
public enum FontBaseImport {
    public enum Failure: Error, Equatable {
        /// No FontBase library there.
        case notALibrary
    }

    public static let bundleIdentifier = "com.dominiklevitsky.fontbase"

    /// FontBase's folder on this Mac, when it has a library there.
    public static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let url = home.appendingPathComponent("Library/Application Support/FontBase", isDirectory: true)
        return leveldb(in: url) != nil ? url : nil
    }

    /// The folder FontBase copies the fonts that are on into.
    public static func copiesFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Fonts/FontBase", isDirectory: true)
    }

    /// The LevelDB folder of FontBase's folder, of its IndexedDB folder, or that folder itself, as a user may choose
    /// any of them.
    static func leveldb(in url: URL) -> URL? {
        let name = "file__0.indexeddb.leveldb"
        let candidates = [url, url.appendingPathComponent(name), url.appendingPathComponent("IndexedDB").appendingPathComponent(name)]
        return candidates.first { candidate in
            candidate.lastPathComponent.hasSuffix(".indexeddb.leveldb")
                && FileManager.default.fileExists(atPath: candidate.appendingPathComponent("CURRENT").path)
        }
    }

    /// Reads the library at `url`: FontBase's folder, or its IndexedDB. A folder in another account's home is taken as
    /// being in `home`. FontBase's copies in the Fonts folder are only looked at for this Mac's own library.
    public static func read(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> ImportedLibrary {
        guard let leveldb = leveldb(in: url) else { throw Failure.notALibrary }
        let values: [String: JSValue]
        do {
            values = try ChromiumIndexedDB.values(in: leveldb, database: "fontbase", store: "fontbase_db")
        } catch {
            throw Failure.notALibrary
        }
        guard values["fontbase_pathsAll"] != nil || values["fontbase_settings"] != nil else { throw Failure.notALibrary }
        let isThisMacs = folder(home: home).map { leveldb.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") } ?? false
        return Reader(values: values, home: home.path).library(copies: isThisMacs ? copiesFolder(home: home) : nil)
    }

    struct Reader {
        let values: [String: JSValue]
        let home: String
        let fm = FileManager.default

        func library(copies: URL?) -> ImportedLibrary {
            var library = ImportedLibrary(source: .fontBase)
            let root = rootFolder()
            let realRoot = Self.realPath(root)

            // Each file by its path under the folder, and where it is on this Mac: under the folder, or, through a
            // symbolic link, elsewhere.
            var pathOf: [String: String] = [:]
            var located: [String: String] = [:]
            var missing = 0
            var notDownloaded: [String: Int] = [:]
            var unreadable: [FontExplorerImport.UnreadableKind: Int] = [:]
            var other = Set<String>()
            var count = 0
            for (relative, entry) in values["fontbase_pathsAll"]?.properties ?? [] {
                guard relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { continue }
                if let id = entry["id"]?.string, pathOf[id] == nil { pathOf[id] = relative }
                let path = root + relative
                guard fm.fileExists(atPath: path) else {
                    // A provider's font FontBase lists without having downloaded it, or a file that's gone.
                    let parts = relative.split(separator: "/")
                    if entry["url"]?.string != nil, parts.count > 2, parts[0] == "Providers" {
                        notDownloaded[String(parts[1]), default: 0] += 1
                    } else {
                        missing += 1
                    }
                    continue
                }
                let ext = (path as NSString).pathExtension
                guard FontFormat.fileExtensions.contains(ext.lowercased()) else {
                    unreadable[FontExplorerImport.UnreadableKind(extension: ext), default: 0] += 1
                    continue
                }
                let real = Self.realPath(path)
                if real.hasPrefix(realRoot + "/") {
                    located[relative] = path
                    count += 1
                } else {
                    located[relative] = real
                    other.insert(real)
                }
            }
            if fm.fileExists(atPath: root) {
                library.fontFolder = root
                library.fontFolderCount = count
            } else if !(values["fontbase_pathsAll"]?.properties ?? []).isEmpty {
                library.notes.append("its folder, \((root as NSString).abbreviatingWithTildeInPath), which isn’t on this Mac")
            }
            library.otherFiles = other.sorted()

            let names = Dictionary((values["fontbase_fontsAll"]?.properties ?? []).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            func font(_ id: String, at relative: String? = nil) -> ImportedFont {
                let path = (relative ?? pathOf[id]).map { located[$0] ?? root + $0 }
                return ImportedFont(path: path, postScriptName: id, family: names[id]?["fontFamilyName"]?.string,
                                    style: names[id]?["fontSubFamily"]?.string)
            }

            // Collections: the user's, and Favorites when it has any; not the filters.
            var otherCollections: [String] = []
            for (id, collection) in values["fontbase_collectionsAll"]?.properties ?? [] {
                let type = collection["type"]?.string ?? ""
                let ids = collection["query"]?["ids"]?.array?.compactMap(\.string) ?? []
                let name = collection["name"]?.string ?? id
                switch type {
                case "default":
                    continue
                case "favorites":
                    if !ids.isEmpty { library.sets.append(ImportedSet(id: id, name: name, fonts: ids.map { font($0) })) }
                case "":
                    library.sets.append(ImportedSet(id: id, name: name, fonts: ids.map { font($0) }))
                default:
                    otherCollections.append(name)
                }
            }

            // The user's tags, each given to the fonts that have it.
            var tagged: [String: [ImportedFont]] = [:]
            var tagOrder: [String] = []
            for (id, tags) in values["fontbase_fontsTagsUser"]?.properties ?? [] {
                for tag in tags.array?.compactMap(\.string) ?? [] {
                    let name = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    if tagged[name] == nil { tagOrder.append(name) }
                    tagged[name, default: []].append(font(id))
                }
            }
            library.tags = tagOrder.map { ImportedTag(name: $0, color: nil, fonts: tagged[$0] ?? []) }

            // The fonts that are on, at the paths FontBase copied them from.
            var active = Set<String>()
            for (id, relative) in values["fontbase_fontsStatus"]?.properties ?? [] {
                guard let relative = relative.string, relative.hasPrefix("/") else { continue }
                library.active.append(font(id, at: relative))
                if located[relative] != nil { active.insert(id) }
            }

            // FontBase's copies of those, left in the Fonts folder: FontBase was set to keep them on once it quit, or
            // didn't get to delete them. Only those named after a font that's on and still in its folder.
            if let copies, let files = try? fm.contentsOfDirectory(at: copies, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                library.leftoverCopies = files.filter { file in
                    FontFormat.fileExtensions.contains(file.pathExtension.lowercased())
                        && active.contains(file.deletingPathExtension().lastPathComponent)
                }
                .map(\.path).sorted()
            }

            notes(&library, otherCollections: otherCollections, missing: missing, notDownloaded: notDownloaded, unreadable: unreadable)
            return library
        }

        /// What doesn't come over, for the sheet.
        private func notes(_ library: inout ImportedLibrary, otherCollections: [String], missing: Int, notDownloaded: [String: Int],
                           unreadable: [FontExplorerImport.UnreadableKind: Int]) {
            if !otherCollections.isEmpty {
                library.notes.append((otherCollections.count == 1 ? "the collection " : "the collections ")
                    + otherCollections.map { "“\($0)”" }.formatted(.list(type: .and)))
            }
            let automatic = ["fontbase_fontsTagsSystem", "fontbase_fontsTagsCrowd"].contains { !(values[$0]?.properties ?? []).isEmpty }
            if automatic { library.notes.append("the tags FontBase gives fonts itself, like Sans and Script") }
            let edited = values["fontbase_fontsOverrides"]?.properties?.count ?? 0
            if edited > 0 { library.notes.append(edited == 1 ? "your changes to 1 font’s details" : "your changes to \(edited.formatted()) fonts’ details") }
            let licenses = values["fontbase_licensesAll"]?.properties?.count ?? 0
            if licenses > 0 { library.notes.append(licenses == 1 ? "1 license you added" : "\(licenses.formatted()) licenses you added") }
            let activeFolders = (values["fontbase_foldersAll"]?.properties ?? []).filter { $0.value["status"]?.string == "active" && $0.value["virtual"]?.bool != true }
            if !activeFolders.isEmpty {
                library.notes.append("turning on new fonts in \(activeFolders.count == 1 ? "the active folder" : "active folders") by themselves")
            }
            library.notes.append("sample texts and preview settings")
            for kind in FontExplorerImport.UnreadableKind.allCases {
                if let count = unreadable[kind] { library.notes.append(kind.describe(count)) }
            }
            let total = notDownloaded.values.reduce(0, +)
            if total > 0 {
                let providers = notDownloaded.keys.sorted().formatted(.list(type: .and))
                library.notes.append("\(total.formatted()) \(providers) \(total == 1 ? "font" : "fonts") you haven’t downloaded")
            }
            if missing > 0 {
                library.notes.append(missing == 1 ? "1 font file that isn’t on this Mac" : "\(missing.formatted()) font files that aren’t on this Mac")
            }
        }

        /// FontBase's folder, as it's set, or where it is at first; in another account's home, in this one's.
        private func rootFolder() -> String {
            var root = values["fontbase_settings"]?["rootFolder"]?.string ?? home + "/FontBase"
            while root.count > 1, root.hasSuffix("/") { root.removeLast() }
            let parts = root.split(separator: "/")
            if !fm.fileExists(atPath: root), root.hasPrefix("/Users/"), parts.count >= 2, parts[1] != "Shared" {
                let oldHome = "/Users/\(parts[1])"
                if oldHome != home { root = home + root.dropFirst(oldHome.count) }
            }
            return root
        }

        static func realPath(_ path: String) -> String {
            guard let resolved = realpath(path, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
