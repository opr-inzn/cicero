import Foundation

/// Reads FontExplorer X Pro's library: the database it keeps on this Mac, a `.fexconfig` (a folder with a copy of the
/// database and the app's settings, from File → Local Backup) or a `.fexbackup` (the same as a ZIP, with the fonts in
/// its Font Library). A copy of the database is opened read-only, so FontExplorer X can stay open and nothing of it
/// changes.
///
/// The database (SQLite, the same in 7.x and its backups): `containers` has a row per font file, `fonts` a row per face,
/// `sourceItems` the sidebar (sets, folders, smart sets and application sets, nested by `parentSerialID`),
/// `setContainers` which files each set has, `smartGroupRules` each smart set's rules and `applicationSetPaths` the
/// apps of each application set; `fonts.fontClassificationIds` numbers each face's classifications, which
/// `fontClassifications` names, the user's own among them (`isCustom`). Dates are seconds since 2001.
public enum FontExplorerImport {
    public enum Failure: Error, Equatable {
        /// Not FontExplorer X's database, or a backup without one.
        case notALibrary
    }

    /// What File → Import from FontExplorer X opens: its database, and its two kinds of backup.
    public static let fileExtensions: Set<String> = ["fexdb", "fexconfig", "fexbackup"]

    /// The database FontExplorer X keeps on this Mac, when there's one.
    public static func database(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let url = home.appendingPathComponent("Library/Application Support/Linotype/FontExplorer X/FontExplorer X.fexdb")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func preferences(home: URL) -> URL {
        home.appendingPathComponent("Library/Preferences/com.linotype.FontExplorerX.plist")
    }

    /// The location an import made of FontExplorer X's Font Library up to 0.10.13, which imports copy fonts in now: the
    /// location called after FontExplorer X, as the import named it, or else the one that is the Font Library, where
    /// FontExplorer X's settings put it or in its default place. Nil when there's none, or its folder isn't there.
    public static func earlierImportLocation(in data: UserData, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> WatchedFolder? {
        let named = data.folders.first { data.folderNames[$0.id.uuidString] == ImportedLibrary.Source.fontExplorer.appName }
        var libraries = [home.appendingPathComponent("FontExplorer X/Font Library").path]
        if let setting = (NSDictionary(contentsOf: preferences(home: home)) as? [String: Any])?["fontFolderLocation"] as? String, !setting.isEmpty {
            let expanded = setting.hasPrefix("~/") ? home.path + setting.dropFirst() : setting
            libraries.insert(expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded, at: 0)
        }
        let standardized = Set(libraries.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let folder = named ?? data.folders.first { standardized.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }
        var isDirectory: ObjCBool = false
        guard let folder, FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return folder
    }

    /// The name of the database in a backup, next to the app's settings.
    static let backupDatabase = "FontDatabase.db"
    static let backupPreferences = "com.linotype.FontExplorerX.plist"
    /// How a `.fexbackup` with fonts writes their paths: under the Font Library, which the backup has at its top, as
    /// "CLIENT_PATH/N/New York Medium/NewYorkMedium-Regular.otf". Files it used from elsewhere are put
    /// there too.
    static let backupLibraryPrefix = "CLIENT_PATH/"

    /// Reads the database at `url`, or the backup. Paths in another account's home folder are taken as being in
    /// `home`. Call off the main thread; a `.fexbackup` is unzipped into a temporary folder that the result's
    /// `discard` removes.
    public static func read(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> ImportedLibrary {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("Cicero Import \(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            var database = url
            var settings: URL?
            var backupFolder: URL?
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if url.pathExtension.lowercased() == "fexbackup" {
                let unzipped = temporary.appendingPathComponent("Backup", isDirectory: true)
                try fm.createDirectory(at: unzipped, withIntermediateDirectories: true)
                try await Archive.unzip(url, to: unzipped)
                guard let found = find(backupDatabase, in: unzipped) else { throw Failure.notALibrary }
                database = found
                settings = found.deletingLastPathComponent().appendingPathComponent(backupPreferences)
                backupFolder = found.deletingLastPathComponent()
            } else if isDirectory.boolValue {
                // A .fexconfig, which macOS takes for a plain folder when FontExplorer X isn't installed.
                database = url.appendingPathComponent(backupDatabase)
                settings = url.appendingPathComponent(backupPreferences)
            } else {
                // The settings next to a database copied with them, else this Mac's for its own database.
                let beside = url.deletingLastPathComponent().appendingPathComponent(backupPreferences)
                settings = fm.fileExists(atPath: beside.path) ? beside
                    : url.standardizedFileURL.path == Self.database(home: home)?.standardizedFileURL.path ? preferences(home: home) : nil
            }
            guard fm.fileExists(atPath: database.path) else { throw Failure.notALibrary }
            // FontExplorer X may be writing to its database; a copy reads as it was a moment ago.
            let copy = temporary.appendingPathComponent("Copy.db")
            do { try fm.copyItem(at: database, to: copy) } catch { throw Failure.notALibrary }
            let preferences = settings.flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]
            let file: SQLiteFile
            do { file = try SQLiteFile(copy) } catch { throw Failure.notALibrary }
            var library = try Reader(file: file, preferences: preferences, home: home.path, backupFolder: backupFolder).library()
            library.temporaryFolder = temporary
            if backupFolder == nil {
                // Nothing more is read from it.
                try? fm.removeItem(at: copy)
            }
            return library
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    /// The file called `name` in `folder` or a folder in it, two levels down at most; never through a symbolic link.
    private static func find(_ name: String, in folder: URL, depth: Int = 2) -> URL? {
        let fm = FileManager.default
        let here = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: here.path) { return here }
        guard depth > 0 else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if let found = find(name, in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    // MARK: Labels

    /// FontExplorer X's own classifications (its FontClassifications.json, which its database copies), by number, as
    /// Cicero's: each branch of its tree goes where Cicero puts that kind, its blackletter, a branch of scripts there,
    /// among the ornamental ones. Themes (Christmas, Techno…), usages (Book, Poster…), and Condensed and the like say
    /// nothing about it.
    static let classifications: [Int: Classification] = {
        var found: [Int: Classification] = [42: .monospaced, 48: .symbol, 17: .ornamental]
        for id in [1, 47, 3, 4, 5, 6, 7, 8] { found[id] = .serif }
        for id in [9, 45, 11, 12, 13, 14] { found[id] = .sansSerif }
        for id in [15, 46, 18, 19, 20, 69, 23, 24] { found[id] = .script }
        for id in [25, 40] + Array(27...37) { found[id] = .ornamental }
        return found
    }()

    /// The classification of a style FontExplorer X gave these (its numbers, however they're written): the user's own
    /// first, which only the user gives, then monospaced and symbol, which say more than a kind, then the first kind.
    static func classification(_ ids: String, of font: ImportedFont, custom: [Int: String]) -> ImportedClassification? {
        let numbers = ids.matches(of: /\d+/).compactMap { Int($0.output) }
        if let name = numbers.lazy.compactMap({ custom[$0] }).first { return ImportedClassification(font: font, custom: name) }
        let found = numbers.compactMap { classifications[$0] }
        guard let first = found.first(where: { $0 == .monospaced }) ?? found.first(where: { $0 == .symbol }) ?? found.first else { return nil }
        return ImportedClassification(font: font, builtIn: first)
    }

    /// FontExplorer X's labels by number, as tags: they have colours but no names, so they're named after them, as
    /// Cicero names a tag made with a colour and no name.
    static let labels: [Int: TagColor] = [1: .red, 2: .orange, 3: .yellow, 4: .green, 5: .blue, 6: .purple, 7: .gray]

    static func labelName(_ color: TagColor) -> String { color.rawValue.capitalized }

    // MARK: Smart set rules

    /// Smart sets FontExplorer X makes itself (Activated Fonts, Language supports English, Recently Activated,
    /// Deactivated and Imported), by serial number.
    static let builtInSmartSets: Set<Int> = [1, 3, 4, 5, 6]

    /// A smart set rule as Cicero's, or what it asks when Cicero has no counterpart. `sets` gives the `ImportedSet.id`
    /// of a set by its serial number.
    static func rule(field code: Int, comparison: Int, value: String, sets: [Int: String]) -> Result<SmartRule, UnsupportedRule> {
        let unsupported = UnsupportedRule(fieldName(field: code))
        func text(_ field: SmartRule.Field, _ comparisons: [Int: SmartRule.Comparison], value: String = value) -> Result<SmartRule, UnsupportedRule> {
            guard let mapped = comparisons[comparison] else {
                let words = textComparisons.indices.contains(comparison) ? textComparisons[comparison] : nil
                return .failure(UnsupportedRule(fieldName(field: code), comparison: words))
            }
            return .success(SmartRule(field: field, comparison: mapped, value: value))
        }
        func number(_ field: SmartRule.Field) -> Result<SmartRule, UnsupportedRule> {
            guard let mapped = [0: SmartRule.Comparison.is, 2: .greaterThan][comparison], let number = Int(value) else {
                return .failure(unsupported)
            }
            return .success(SmartRule(field: field, comparison: mapped, value: String(number)))
        }
        func recent(_ field: SmartRule.Field) -> Result<SmartRule, UnsupportedRule> {
            // "In the last 7 days" and "in the last 30 days"; the others say nothing Cicero's rules can.
            guard let days = [1007: 7, 1030: 30][comparison] else { return .failure(unsupported) }
            return .success(SmartRule(field: field, comparison: .inLast, value: String(days)))
        }
        /// Is Activated, Is System Font and the like: 1 for yes, compared with "is" or "is not".
        func yesOrNo(_ status: String) -> Result<SmartRule, UnsupportedRule> {
            guard comparison == 0 || comparison == 1 else { return .failure(unsupported) }
            let yes = (Int(value) ?? 1) != 0
            return .success(SmartRule(field: .status, comparison: yes == (comparison == 0) ? .is : .isNot, value: status))
        }
        switch code {
        // The full name, style and all: only "begins with" picks the same families by their names.
        case 0: return text(.name, [4: .beginsWith])
        case 4: return text(.name, [0: .is, 4: .beginsWith, 6: .contains, 7: .doesNotContain])
        case 9:
            // A foundry is as Cicero tidies the files' names, "Rasmus Andersson" for "Rasmus Andersson Inc.".
            return text(.foundry, [0: .is, 1: .isNot, 6: .contains], value: comparison == 6 ? value : Foundry.normalized(value) ?? value)
        // Comments come over as notes.
        case 10: return text(.note, [6: .contains, 7: .doesNotContain])
        case 11: return text(.designer, [0: .is, 6: .contains, 7: .doesNotContain])
        case 100: return yesOrNo("active")
        case 102, 105: return yesOrNo("system")
        case 400: return number(.rating)
        case 500:
            guard comparison == 0, let serial = Int(value), let set = sets[serial] else { return .failure(unsupported) }
            return .success(SmartRule(field: .set, comparison: .is, value: set))
        case 600:
            guard comparison == 0 || comparison == 1, let color = Int(value).flatMap({ labels[$0] }) else { return .failure(unsupported) }
            return .success(SmartRule(field: .tag, comparison: comparison == 0 ? .is : .isNot, value: labelName(color)))
        case 700: return number(.timesActivated)
        case 701: return recent(.lastActivated)
        case 800: return recent(.added)
        default: return .failure(unsupported)
        }
    }

    /// How FontExplorer X words its comparisons of text, by number.
    private static let textComparisons = [
        "is", "is not", "ends with", "doesn’t end with", "begins with", "doesn’t begin with", "contains", "doesn’t contain",
    ]

    /// The name FontExplorer X shows for a rule's field, as its Smart Set sheet has them (7.3).
    static func fieldName(field: Int) -> String {
        switch field {
        case 0: "Name"
        case 1: "PostScript Name"
        case 3: "Path"
        case 4: "Family Name"
        case 5: "Style"
        case 6: "Copyright"
        case 7: "Version"
        case 8: "Trademark"
        case 9: "Manufacturer"
        case 10: "Comment"
        case 11: "Designer"
        case 12: "Description"
        case 100: "Is Activated"
        case 101: "Is in Conflict"
        case 102: "Is in System Folder"
        case 105: "Is System Font"
        case 200: "Format"
        case 300: "Vendor"
        case 400: "Rating"
        case 500: "Contained In"
        case 501: "Not Contained In"
        case 600: "Label"
        case 700: "Number of Activations"
        case 701: "Last Activated"
        case 702: "Number of Last Activated Fonts"
        case 800: "Import Date"
        case 801: "Number of Last Imported Fonts"
        case 900: "Embedding Rights"
        case 1100: "Language"
        case 1200: "OpenType Features"
        case 1300: "SkyFonts"
        case 1301: "Monotype"
        case 1302: "Adobe Fonts"
        case 1500: "Classification"
        case 1600: "Last Deactivated"
        default: "a kind of rule from another version of FontExplorer X"
        }
    }

    /// Font files Cicero can't use, by what they are, for the sheet to say which don't come over.
    enum UnreadableKind: CaseIterable {
        case type1, web, other

        init(extension ext: String) {
            switch ext.lowercased() {
            // Classic Mac fonts have no extension: PostScript Type 1 outlines (LWFN) and suitcases.
            case "", "pfb", "pfa", "pfm", "afm", "lwfn", "suit": self = .type1
            case "woff", "woff2", "eot", "svg": self = .web
            default: self = .other
            }
        }

        func describe(_ count: Int) -> String {
            let number = count.formatted()
            return switch self {
            case .type1: count == 1 ? "1 PostScript Type 1 font or font suitcase, which Cicero can’t use"
                : "\(number) PostScript Type 1 fonts and font suitcases, which Cicero can’t use"
            case .web: count == 1 ? "1 web font, which Cicero can’t use" : "\(number) web fonts, which Cicero can’t use"
            case .other: count == 1 ? "1 other file Cicero can’t use" : "\(number) other files Cicero can’t use"
            }
        }
    }

    /// What a rule Cicero can't take asks, as FontExplorer X words it: "Format", "Family Name ends with".
    struct UnsupportedRule: Error, Equatable {
        var description: String

        init(_ field: String, comparison: String? = nil) {
            description = [field, comparison].compactMap { $0 }.joined(separator: " ")
        }
    }
}

// MARK: - Reading the database

private struct Reader {
    let file: SQLiteFile
    let preferences: [String: Any]
    /// This Mac's home folder.
    let home: String
    /// The unzipped `.fexbackup`'s folder with the database, the Font Library's files in folders next to it.
    let backupFolder: URL?

    private struct Container {
        var id: Int
        /// Where the file is on this Mac.
        var path: String
        var isSystem: Bool
        var isCloud: Bool
        var isActive: Bool
        var count: Int
        var lastActivated: Date?
        var label: Int
        var comment: String?
        var hasLicense: Bool
    }

    func library() throws -> ImportedLibrary {
        let containerColumns = file.columns(of: "containers")
        guard containerColumns.contains("path"), file.columns(of: "sourceItems").contains("type") else {
            throw FontExplorerImport.Failure.notALibrary
        }
        let containerRows = try select(["containerID", "path", "isSystemFont", "isInSystemFolder", "isSkyFont", "isTypekit", "isMLSFont",
                                        "activate", "count", "lastActivated", "labelColorID", "comment", "licenseName", "licenseLocation",
                                        "licenseComment"], from: "containers")
        let fontRows = try select(["containerID", "psName", "familyName", "style", "rating", "labelColorID", "comment", "fontClassificationIds"],
                                  from: "fonts")
        let classificationRows = try select(["fontClassificationID", "isCustom", "title"], from: "fontClassifications")
        let custom = Dictionary(classificationRows.compactMap { row -> (Int, String)? in
            guard row.int("isCustom") != 0, let title = row.text("title")?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
            return (row.int("fontClassificationID"), title)
        }, uniquingKeysWith: { first, _ in first })
        let items = try select(["serialID", "type", "title", "parentSerialID", "specialFlag"], from: "sourceItems", orderedBy: "rowid")
        let memberRows = try select(["serialID", "containerID"], from: "setContainers")
        let ruleRows = try select(["serialID", "baseCriteria", "subCriteria", "value"], from: "smartGroupRules", orderedBy: "rowid")
        let appRows = try select(["serialID", "path"], from: "applicationSetPaths", orderedBy: "rowid")

        // Where the files are: FontExplorer X's Font Library, and the home folder of the account the database was made
        // in, which stand for this Mac's. A backup's paths are under the Font Library already.
        let prefix = FontExplorerImport.backupLibraryPrefix
        let paths = containerRows.compactMap { $0.text("path") }
        let oldHome = Self.home(of: setting("fontFolderLocation") ?? "") ?? Self.mostCommonHome(paths)
        let oldLibrary = libraryFolder(oldHome: oldHome, paths: paths)
        let newLibrary = oldLibrary.map { place(library: $0, oldHome: oldHome) }
            ?? (paths.contains { $0.hasPrefix(prefix) } ? home + "/FontExplorer X/Font Library" : nil)
        func local(_ path: String) -> String {
            if let newLibrary, path.hasPrefix(prefix) { return newLibrary + "/" + path.dropFirst(prefix.count) }
            if let oldLibrary, let newLibrary, path.hasPrefix(oldLibrary + "/") { return newLibrary + path.dropFirst(oldLibrary.count) }
            if let oldHome, oldHome != home, path.hasPrefix(oldHome + "/") { return home + path.dropFirst(oldHome.count) }
            return path
        }

        // Files of macOS's own with hidden faces, whose PostScript names start with a dot, like PingFangUI.ttc, which
        // FontExplorer X lists from a private framework without calling it a system font, and puts in a backup.
        var hidden = Set<Int>()
        for row in fontRows where row.text("psName")?.hasPrefix(".") == true { hidden.insert(row.int("containerID")) }

        var containers: [Int: Container] = [:]
        var order: [Int] = []
        for row in containerRows {
            guard let path = row.text("path") else { continue }
            let id = row.int("containerID")
            let last = row.double("lastActivated")
            containers[id] = Container(
                id: id, path: local(path),
                isSystem: row.int("isSystemFont") != 0 || row.int("isInSystemFolder") != 0 || path.hasPrefix("/System/") || hidden.contains(id),
                isCloud: row.int("isSkyFont") != 0 || row.int("isTypekit") != 0 || row.int("isMLSFont") != 0,
                isActive: row.int("activate") == 1, count: max(row.int("count"), 0),
                lastActivated: last > 0 ? Date(timeIntervalSinceReferenceDate: last) : nil,
                label: row.int("labelColorID"), comment: row.text("comment"),
                hasLicense: ["licenseName", "licenseLocation", "licenseComment"].contains { row.text($0) != nil }
            )
            order.append(id)
        }

        // Files Cicero can't use (PostScript Type 1, suitcases, web fonts) don't come over, nor do the sets, labels and
        // the rest given to them; the sheet says how many there are.
        var unreadable: [FontExplorerImport.UnreadableKind: Int] = [:]
        for id in order {
            guard let container = containers[id], !container.isSystem, !container.isCloud else { continue }
            let ext = (container.path as NSString).pathExtension
            guard !FontFormat.fileExtensions.contains(ext.lowercased()) else { continue }
            unreadable[FontExplorerImport.UnreadableKind(extension: ext), default: 0] += 1
            containers[id] = nil
        }
        order.removeAll { containers[$0] == nil }

        // Each file's faces, as fonts; a file without any (FontExplorer X couldn't read it) by its path alone.
        var faces: [Int: [ImportedFont]] = [:]
        var labelled: [Int: [ImportedFont]] = [:]
        // Each file's faces' comments, which FontExplorer X keeps on the file too when it's given to all of them.
        var faceComments: [Int: Set<String>] = [:]
        var library = ImportedLibrary(source: .fontExplorer)
        for row in fontRows {
            guard let container = containers[row.int("containerID")] else { continue }
            let font = ImportedFont(path: container.path, postScriptName: row.text("psName"), family: row.text("familyName"), style: row.text("style"))
            faces[container.id, default: []].append(font)
            let label = row.int("labelColorID")
            if FontExplorerImport.labels[label] != nil { labelled[label, default: []].append(font) }
            let stars = row.int("rating")
            if (1...5).contains(stars) { library.ratings.append(ImportedRating(font: font, stars: stars)) }
            if let ids = row.text("fontClassificationIds"), let classification = FontExplorerImport.classification(ids, of: font, custom: custom) {
                library.classifications.append(classification)
            }
            if let comment = row.text("comment") {
                library.comments.append(ImportedComment(fonts: [font], text: comment))
                faceComments[container.id, default: []].insert(comment)
            }
        }
        func fonts(_ id: Int) -> [ImportedFont] {
            guard let container = containers[id] else { return [] }
            return faces[id] ?? [ImportedFont(path: container.path)]
        }
        for id in order {
            guard let container = containers[id] else { continue }
            if FontExplorerImport.labels[container.label] != nil {
                labelled[container.label, default: []] += fonts(id).filter { !(labelled[container.label] ?? []).contains($0) }
            }
            if let comment = container.comment, !(faceComments[id] ?? []).contains(comment) {
                library.comments.append(ImportedComment(fonts: fonts(id), text: comment))
            }
            // macOS's fonts are on all the time: FontExplorer X counts them as turned on when it first lists them.
            if !container.isSystem, container.count > 0 || container.lastActivated != nil {
                library.history.append(ImportedHistory(fonts: fonts(id), count: container.count, last: container.lastActivated))
            }
            if container.isActive, !container.isSystem, !container.isCloud { library.active += fonts(id) }
        }

        // The fonts to copy in: those in the Font Library, and the others. Fonts in the Fonts folders Cicero reads
        // anyway, and from SkyFonts, Adobe Fonts or Monotype's cloud, aren't.
        let fm = FileManager.default
        var missing = 0
        var inLibrary: [String] = []
        // A Font Library that isn't on this Mac, and how many of the files were in it.
        var absentLibrary: (path: String, files: Int)?
        for id in order {
            guard let container = containers[id], !container.isSystem, !container.isCloud else { continue }
            if let newLibrary, container.path.hasPrefix(newLibrary + "/") {
                library.fontFolderCount += 1
                inLibrary.append(String(container.path.dropFirst(newLibrary.count + 1)))
            } else if fm.fileExists(atPath: container.path) {
                if !library.otherFiles.contains(container.path) { library.otherFiles.append(container.path) }
            } else {
                missing += 1
            }
        }
        library.fontFolder = newLibrary
        if let newLibrary { library.fontFolderFiles = inLibrary.map { newLibrary + "/" + $0 } }
        if let backupFolder, newLibrary != nil {
            library.bundledFonts = bundled(in: backupFolder, files: inLibrary)
        } else if let newLibrary, !fm.fileExists(atPath: newLibrary), library.fontFolderCount > 0 {
            // A database from another Mac, its Font Library not here (yet), or on a disk that isn't connected: the
            // fonts in it can't be listed.
            absentLibrary = (newLibrary, library.fontFolderCount)
            library.fontFolderCount = 0
            library.fontFolderFiles = []
        }
        // FontExplorer X left the fonts where they were, or its Font Library isn't here: nothing to copy from there.
        if library.fontFolderCount == 0 { library.fontFolder = nil }

        // The sidebar: sets in folders get the folders' names, as Cicero's sets aren't in folders.
        var byID: [Int: SQLiteFile.Row] = [:]
        for item in items { byID[item.int("serialID")] = item }
        func name(_ item: SQLiteFile.Row) -> String {
            var parts = [item.text("title") ?? "Untitled"]
            var parent = byID[item.int("parentSerialID")]
            var seen: Set<Int> = [item.int("serialID")]
            while let folder = parent, folder.int("type") == 8, seen.insert(folder.int("serialID")).inserted {
                parts.insert(folder.text("title") ?? "Untitled", at: 0)
                parent = byID[folder.int("parentSerialID")]
            }
            return parts.joined(separator: " / ")
        }
        var members: [Int: [Int]] = [:]
        for row in memberRows { members[row.int("serialID"), default: []].append(row.int("containerID")) }
        func setFonts(_ serial: Int) -> [ImportedFont] {
            var seen = Set<ImportedFont>()
            return (members[serial] ?? []).flatMap(fonts).filter { seen.insert($0).inserted }
        }
        var apps: [Int: [String]] = [:]
        for row in appRows { if let path = row.text("path") { apps[row.int("serialID"), default: []].append(path) } }

        // A set's serial number → its ID, for smart sets' Contained In; an application set's fonts are its
        // Autoactivate item's.
        var setIDs: [Int: String] = [:]
        var deactivating = 0
        // Sets that had only files Cicero can't use, which would come over empty.
        var unreadableSets: [String] = []
        for item in items {
            let serial = item.int("serialID")
            switch item.int("type") {
            case 7:
                let fonts = setFonts(serial)
                if fonts.isEmpty, !(members[serial] ?? []).isEmpty {
                    unreadableSets.append(name(item))
                    continue
                }
                setIDs[serial] = String(serial)
                library.sets.append(ImportedSet(id: String(serial), name: name(item), fonts: fonts))
            case 31:
                let children = items.filter { $0.int("parentSerialID") == serial }
                var fonts: [ImportedFont] = []
                var hadFonts = false
                for child in children {
                    switch child.int("type") {
                    case 32:
                        setIDs[child.int("serialID")] = String(serial)
                        hadFonts = hadFonts || !(members[child.int("serialID")] ?? []).isEmpty
                        fonts += setFonts(child.int("serialID")).filter { !fonts.contains($0) }
                    case 33:
                        if !(members[child.int("serialID")] ?? []).isEmpty { deactivating += 1 }
                    default: break
                    }
                }
                if fonts.isEmpty, hadFonts {
                    unreadableSets.append(name(item))
                    continue
                }
                setIDs[serial] = String(serial)
                library.sets.append(ImportedSet(id: String(serial), name: name(item), fonts: fonts, apps: apps[serial] ?? [], isApplicationSet: true))
            default: break
            }
        }
        var rulesBySet: [Int: [SQLiteFile.Row]] = [:]
        for row in ruleRows { rulesBySet[row.int("serialID"), default: []].append(row) }
        var ruleLabels = Set<Int>()
        for item in items where item.int("type") == 6 && !FontExplorerImport.builtInSmartSets.contains(item.int("serialID")) {
            let serial = item.int("serialID")
            var rules: [SmartRule] = []
            var unsupported: [String] = []
            for row in rulesBySet[serial] ?? [] {
                let field = row.int("baseCriteria")
                let value = row.text("value") ?? ""
                switch FontExplorerImport.rule(field: field, comparison: row.int("subCriteria"), value: value, sets: setIDs) {
                case .success(let rule):
                    rules.append(rule)
                    if field == 600, let label = Int(value) { ruleLabels.insert(label) }
                case .failure(let rule):
                    if !unsupported.contains(rule.description) { unsupported.append(rule.description) }
                }
            }
            library.smartSets.append(ImportedSmartSet(id: String(serial), name: name(item), matchAll: item.int("specialFlag") != 0,
                                                      rules: rules, unsupported: unsupported))
        }

        // Labels in use, by fonts or smart sets, in FontExplorer X's order.
        for (number, color) in FontExplorerImport.labels.sorted(by: { $0.key < $1.key })
        where labelled[number] != nil || ruleLabels.contains(number) {
            library.tags.append(ImportedTag(name: FontExplorerImport.labelName(color), color: color, fonts: labelled[number] ?? []))
        }

        for kind in FontExplorerImport.UnreadableKind.allCases {
            if let count = unreadable[kind] { library.notes.append(kind.describe(count)) }
        }
        if !unreadableSets.isEmpty {
            let names = unreadableSets.map { "“\($0)”" }.formatted(.list(type: .and))
            library.notes.append("the \(unreadableSets.count == 1 ? "set" : "sets") \(names), whose fonts Cicero can’t use")
        }
        // The Font Library by where it was looked for, so it can be put there and imported again.
        if let absentLibrary {
            let place = absentLibrary.path.hasPrefix(home + "/") ? "~" + absentLibrary.path.dropFirst(home.count) : absentLibrary.path
            let files = absentLibrary.files == 1 ? "1 font file" : "\(absentLibrary.files.formatted()) font files"
            library.notes.append("\(files) in \(place) (not on this Mac)")
        }
        if missing > 0 {
            let other = absentLibrary == nil ? "" : "other "
            library.notes.append(missing == 1 ? "1 \(other)font file that isn’t on this Mac" : "\(missing.formatted()) \(other)font files that aren’t on this Mac")
        }
        let licensed = containers.values.count(where: \.hasLicense)
        if licensed > 0 { library.notes.append("license details of \(licensed == 1 ? "1 font" : "\(licensed.formatted()) fonts")") }
        if deactivating > 0 {
            library.notes.append("the fonts \(deactivating == 1 ? "an application set turns" : "\(deactivating) application sets turn") off (Autodeactivate)")
        }
        return library
    }

    /// Rows of a table with those of the columns it has, in `order`; none when there's no such table.
    private func select(_ wanted: [String], from table: String, orderedBy order: String? = nil) throws -> [SQLiteFile.Row] {
        let columns = file.columns(of: table)
        let present = wanted.filter(columns.contains)
        guard !present.isEmpty else { return [] }
        let list = present.map { "\"\($0)\"" }.joined(separator: ", ")
        return try file.rows("SELECT \(list) FROM \"\(table)\"" + (order.map { " ORDER BY \($0)" } ?? ""))
    }

    private func setting(_ key: String) -> String? {
        guard let value = preferences[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// The Font Library's folder as FontExplorer X had it: its setting, else the folder it makes by default, when files
    /// are in it.
    private func libraryFolder(oldHome: String?, paths: [String]) -> String? {
        if let location = setting("fontFolderLocation") {
            let expanded = location.hasPrefix("~/") ? (oldHome ?? home) + location.dropFirst() : location
            return expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
        }
        guard let oldHome else { return nil }
        let folder = oldHome + "/FontExplorer X/Font Library"
        return paths.contains { $0.hasPrefix(folder + "/") } ? folder : nil
    }

    /// Where the Font Library is on this Mac: the same place, in this home folder for one in the other's. Fonts from a
    /// backup go to a place on another disk only when it's there, else to the default place in this home folder.
    private func place(library: String, oldHome: String?) -> String {
        if let oldHome, library == oldHome || library.hasPrefix(oldHome + "/") { return home + library.dropFirst(oldHome.count) }
        if backupFolder == nil || FileManager.default.fileExists(atPath: library) { return library }
        return home + "/FontExplorer X/Font Library"
    }

    /// The fonts of a backup: the folder in the unzipped backup that has most of the Font Library's files at their
    /// paths under it (the database's own folder, or one in it), and those it has.
    private func bundled(in folder: URL, files: [String]) -> (folder: URL, files: [String])? {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)) ?? []
        let candidates = [folder] + children.filter { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
        let found = candidates.map { base in (base, files.filter { fm.fileExists(atPath: base.appendingPathComponent($0).path) }) }
        guard let best = found.max(by: { $0.1.count < $1.1.count }), !best.1.isEmpty else { return nil }
        return best
    }

    /// "/Users/name" for a path in a home folder; not the Shared folder.
    static func home(of path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "Users", parts[1] != "Shared", path.hasPrefix("/") else { return nil }
        return "/Users/\(parts[1])"
    }

    /// The home folder most of the paths are in.
    static func mostCommonHome(_ paths: [String]) -> String? {
        var counts: [String: Int] = [:]
        for path in paths { if let home = home(of: path) { counts[home, default: 0] += 1 } }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}
