import Foundation

/// Reads FontExplorer X Pro's library: the database it keeps on this Mac, a `.fexconfig` (a folder with a copy of the
/// database and the app's settings, from File → Local Backup) or a `.fexbackup` (the same as a ZIP, with the fonts in
/// its Font Library). A copy of the database is opened read-only, so FontExplorer X can stay open and nothing of it
/// changes.
///
/// The database (SQLite, the same in 7.x and its backups): `containers` has a row per font file, `fonts` a row per face,
/// `sourceItems` the sidebar (sets, folders, smart sets and application sets, nested by `parentSerialID`),
/// `setContainers` which files each set has, `smartGroupRules` each smart set's rules and `applicationSetPaths` the
/// apps of each application set. Dates are seconds since 2001.
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

    /// The name of the database in a backup, next to the app's settings.
    static let backupDatabase = "FontDatabase.db"
    static let backupPreferences = "com.linotype.FontExplorerX.plist"

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
        switch code {
        // The full name, style and all: only "begins with" picks the same families by their names.
        case 0: return text(.name, [4: .beginsWith])
        case 4: return text(.name, [0: .is, 4: .beginsWith, 6: .contains, 7: .doesNotContain])
        case 9:
            // A foundry is as Cicero tidies the files' names, "Rasmus Andersson" for "Rasmus Andersson Inc.".
            return text(.foundry, [0: .is, 1: .isNot, 6: .contains], value: comparison == 6 ? value : Foundry.normalized(value) ?? value)
        case 11: return text(.designer, [0: .is, 6: .contains, 7: .doesNotContain])
        case 100:
            // Is Activated, 1 for yes.
            guard comparison == 0 || comparison == 1 else { return .failure(unsupported) }
            let yes = (Int(value) ?? 1) != 0
            return .success(SmartRule(field: .status, comparison: yes == (comparison == 0) ? .is : .isNot, value: "active"))
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

    /// The name FontExplorer X shows for a rule's field.
    static func fieldName(field: Int) -> String {
        switch field {
        case 0: "Name"
        case 4: "Family Name"
        case 9: "Manufacturer"
        case 11: "Designer"
        case 100: "Is Activated"
        case 200: "Format"
        case 400: "Rating"
        case 500: "Contained In"
        case 600: "Label"
        case 700: "Number of Activations"
        case 701: "Last Activated"
        case 800: "Import Date"
        case 1100: "Language"
        case 1200: "OpenType Features"
        case 1600: "Last Deactivated"
        default: "a rule of another kind"
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
        var hasComment: Bool
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
        let fontRows = try select(["containerID", "psName", "familyName", "style", "rating", "labelColorID", "comment"], from: "fonts")
        let items = try select(["serialID", "type", "title", "parentSerialID", "specialFlag"], from: "sourceItems", orderedBy: "rowid")
        let memberRows = try select(["serialID", "containerID"], from: "setContainers")
        let ruleRows = try select(["serialID", "baseCriteria", "subCriteria", "value"], from: "smartGroupRules", orderedBy: "rowid")
        let appRows = try select(["serialID", "path"], from: "applicationSetPaths", orderedBy: "rowid")

        // Where the files are: FontExplorer X's Font Library, and the home folder of the account the database was made
        // in, which stand for this Mac's.
        let paths = containerRows.compactMap { $0.text("path") }
        let oldHome = Self.home(of: setting("fontFolderLocation") ?? "") ?? Self.mostCommonHome(paths)
        let oldLibrary = libraryFolder(oldHome: oldHome, paths: paths)
        let newLibrary = oldLibrary.map { place(library: $0, oldHome: oldHome) }
        func local(_ path: String) -> String {
            if let oldLibrary, let newLibrary, path.hasPrefix(oldLibrary + "/") { return newLibrary + path.dropFirst(oldLibrary.count) }
            if let oldHome, oldHome != home, path.hasPrefix(oldHome + "/") { return home + path.dropFirst(oldHome.count) }
            return path
        }

        var containers: [Int: Container] = [:]
        var order: [Int] = []
        for row in containerRows {
            guard let path = row.text("path") else { continue }
            let id = row.int("containerID")
            let last = row.double("lastActivated")
            containers[id] = Container(
                id: id, path: local(path),
                isSystem: row.int("isSystemFont") != 0 || row.int("isInSystemFolder") != 0,
                isCloud: row.int("isSkyFont") != 0 || row.int("isTypekit") != 0 || row.int("isMLSFont") != 0,
                isActive: row.int("activate") == 1, count: max(row.int("count"), 0),
                lastActivated: last > 0 ? Date(timeIntervalSinceReferenceDate: last) : nil,
                label: row.int("labelColorID"), hasComment: row.text("comment") != nil,
                hasLicense: ["licenseName", "licenseLocation", "licenseComment"].contains { row.text($0) != nil }
            )
            order.append(id)
        }

        // Each file's faces, as fonts; a file without any (FontExplorer X couldn't read it) by its path alone.
        var faces: [Int: [ImportedFont]] = [:]
        var labelled: [Int: [ImportedFont]] = [:]
        var library = ImportedLibrary(source: .fontExplorer)
        var comments = containers.values.count(where: \.hasComment)
        for row in fontRows {
            guard let container = containers[row.int("containerID")] else { continue }
            let font = ImportedFont(path: container.path, postScriptName: row.text("psName"), family: row.text("familyName"), style: row.text("style"))
            faces[container.id, default: []].append(font)
            let label = row.int("labelColorID")
            if FontExplorerImport.labels[label] != nil { labelled[label, default: []].append(font) }
            let stars = row.int("rating")
            if (1...5).contains(stars) { library.ratings.append(ImportedRating(font: font, stars: stars)) }
            if row.text("comment") != nil { comments += 1 }
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
            if container.count > 0 || container.lastActivated != nil {
                library.history.append(ImportedHistory(fonts: fonts(id), count: container.count, last: container.lastActivated))
            }
            if container.isActive, !container.isSystem, !container.isCloud { library.active += fonts(id) }
        }

        // The fonts to list: those in the Font Library as a folder, the others one by one, where they are. Fonts in the
        // Fonts folders Cicero reads anyway, and from SkyFonts, Adobe Fonts or Monotype's cloud, aren't added.
        let fm = FileManager.default
        var missing = 0
        for id in order {
            guard let container = containers[id], !container.isSystem, !container.isCloud else { continue }
            if let newLibrary, container.path.hasPrefix(newLibrary + "/") {
                library.fontFolderCount += 1
            } else if fm.fileExists(atPath: container.path) {
                if !library.otherFiles.contains(container.path) { library.otherFiles.append(container.path) }
            } else {
                missing += 1
            }
        }
        library.fontFolder = newLibrary
        if let backupFolder, let newLibrary {
            library.bundledFonts = bundled(in: backupFolder, files: order.compactMap { containers[$0]?.path }
                .filter { $0.hasPrefix(newLibrary + "/") }.map { String($0.dropFirst(newLibrary.count + 1)) })
        } else if let newLibrary, !fm.fileExists(atPath: newLibrary) {
            // A database from another Mac, its Font Library not here (yet): the fonts in it can't be listed.
            missing += library.fontFolderCount
            library.fontFolder = nil
            library.fontFolderCount = 0
        }
        // FontExplorer X left the fonts where they were: nothing to list there.
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
        for item in items {
            let serial = item.int("serialID")
            switch item.int("type") {
            case 7:
                setIDs[serial] = String(serial)
                library.sets.append(ImportedSet(id: String(serial), name: name(item), fonts: setFonts(serial)))
            case 31:
                setIDs[serial] = String(serial)
                let children = items.filter { $0.int("parentSerialID") == serial }
                var fonts: [ImportedFont] = []
                for child in children {
                    switch child.int("type") {
                    case 32:
                        setIDs[child.int("serialID")] = String(serial)
                        fonts += setFonts(child.int("serialID")).filter { !fonts.contains($0) }
                    case 33:
                        if !(members[child.int("serialID")] ?? []).isEmpty { deactivating += 1 }
                    default: break
                    }
                }
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

        if missing > 0 { library.notes.append(missing == 1 ? "1 font file that isn’t on this Mac" : "\(missing.formatted()) font files that aren’t on this Mac") }
        if comments > 0 { library.notes.append(comments == 1 ? "1 comment" : "\(comments.formatted()) comments") }
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
