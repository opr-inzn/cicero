import Foundation

public enum FontExplorerImport {
    public enum Failure: Error, Equatable {
        case notALibrary
    }

    public static let fileExtensions: Set<String> = ["fexdb", "fexconfig", "fexbackup"]

    public static func database(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let url = home.appendingPathComponent("Library/Application Support/Linotype/FontExplorer X/FontExplorer X.fexdb")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func preferences(home: URL) -> URL {
        home.appendingPathComponent("Library/Preferences/com.linotype.FontExplorerX.plist")
    }

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

    static let backupDatabase = "FontDatabase.db"
    static let backupPreferences = "com.linotype.FontExplorerX.plist"
    static let backupLibraryPrefix = "CLIENT_PATH/"

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
                let beside = url.deletingLastPathComponent().appendingPathComponent(backupPreferences)
                settings = fm.fileExists(atPath: beside.path) ? beside
                    : url.standardizedFileURL.path == Self.database(home: home)?.standardizedFileURL.path ? preferences(home: home) : nil
            }
            guard fm.fileExists(atPath: database.path) else { throw Failure.notALibrary }
            let copy = temporary.appendingPathComponent("Copy.db")
            do { try fm.copyItem(at: database, to: copy) } catch { throw Failure.notALibrary }
            // The log of a database FontExplorer X has open holds its newest changes; never its shared memory file, which only that process may use.
            for suffix in ["-wal", "-journal"] {
                let log = URL(fileURLWithPath: database.path + suffix)
                if fm.fileExists(atPath: log.path) { try? fm.copyItem(at: log, to: URL(fileURLWithPath: copy.path + suffix)) }
            }
            let preferences = settings.flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]
            let file: SQLiteFile
            do { file = try SQLiteFile(copy: copy) } catch { throw Failure.notALibrary }
            var library = try Reader(file: file, preferences: preferences, home: home.path, backupFolder: backupFolder).library()
            library.temporaryFolder = temporary
            if backupFolder == nil {
                for suffix in ["", "-wal", "-shm", "-journal"] { try? fm.removeItem(atPath: copy.path + suffix) }
            }
            return library
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    private static func find(_ name: String, in folder: URL, depth: Int = 2) -> URL? {
        let fm = FileManager.default
        let here = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: here.path) { return here }
        guard depth > 0 else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: Set(keys))
            // Never through a symbolic link, which could lead out of an unzipped backup.
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if let found = find(name, in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    // MARK: Labels

    static let classifications: [Int: Classification] = {
        var found: [Int: Classification] = [42: .monospaced, 48: .symbol, 17: .ornamental]
        for id in [1, 47, 3, 4, 5, 6, 7, 8] { found[id] = .serif }
        for id in [9, 45, 11, 12, 13, 14] { found[id] = .sansSerif }
        for id in [15, 46, 18, 19, 20, 69, 23, 24] { found[id] = .script }
        for id in [25, 40] + Array(27...37) { found[id] = .ornamental }
        return found
    }()

    static func classification(_ ids: String, of font: ImportedFont, custom: [Int: String]) -> ImportedClassification? {
        let numbers = ids.matches(of: /\d+/).compactMap { Int($0.output) }
        if let name = numbers.lazy.compactMap({ custom[$0] }).first { return ImportedClassification(font: font, custom: name) }
        let found = numbers.compactMap { classifications[$0] }
        guard let first = found.first(where: { $0 == .monospaced }) ?? found.first(where: { $0 == .symbol }) ?? found.first else { return nil }
        return ImportedClassification(font: font, builtIn: first)
    }

    static let labels: [Int: TagColor] = [1: .red, 2: .orange, 3: .yellow, 4: .green, 5: .blue, 6: .purple, 7: .gray]

    static func labelName(_ color: TagColor) -> String { color.rawValue.capitalized }

    // MARK: Smart set rules

    static let builtInSmartSets: Set<Int> = [1, 3, 4, 5, 6]

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
            guard let days = [1007: 7, 1030: 30][comparison] else { return .failure(unsupported) }
            return .success(SmartRule(field: field, comparison: .inLast, value: String(days)))
        }
        func yesOrNo(_ status: String) -> Result<SmartRule, UnsupportedRule> {
            guard comparison == 0 || comparison == 1 else { return .failure(unsupported) }
            let yes = (Int(value) ?? 1) != 0
            return .success(SmartRule(field: .status, comparison: yes == (comparison == 0) ? .is : .isNot, value: status))
        }
        switch code {
        case 0: return text(.name, [4: .beginsWith])
        case 4: return text(.name, [0: .is, 4: .beginsWith, 6: .contains, 7: .doesNotContain])
        case 9:
            return text(.foundry, [0: .is, 1: .isNot, 6: .contains], value: comparison == 6 ? value : Foundry.normalized(value) ?? value)
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

    private static let textComparisons = [
        "is", "is not", "ends with", "doesn’t end with", "begins with", "doesn’t begin with", "contains", "doesn’t contain",
    ]

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
            let number = count.plain
            return switch self {
            case .type1: count == 1 ? "1 PostScript Type 1 font or font suitcase, which Cicero can’t use"
                : "\(number) PostScript Type 1 fonts and font suitcases, which Cicero can’t use"
            case .web: count == 1 ? "1 web font, which Cicero can’t use" : "\(number) web fonts, which Cicero can’t use"
            case .other: count == 1 ? "1 other file Cicero can’t use" : "\(number) other files Cicero can’t use"
            }
        }
    }

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
    let home: String
    let backupFolder: URL?

    private struct Container {
        var id: Int
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

        // macOS's own files with hidden faces, like PingFangUI.ttc, have PostScript names that start with a dot.
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
                lastActivated: last > 0 && last < Date.now.timeIntervalSinceReferenceDate + 86400 ? Date(timeIntervalSinceReferenceDate: last) : nil,
                label: row.int("labelColorID"), comment: row.text("comment"),
                hasLicense: ["licenseName", "licenseLocation", "licenseComment"].contains { row.text($0) != nil }
            )
            order.append(id)
        }

        var unreadable: [FontExplorerImport.UnreadableKind: Int] = [:]
        for id in order {
            guard let container = containers[id], !container.isSystem, !container.isCloud else { continue }
            let ext = (container.path as NSString).pathExtension
            guard !FontFormat.fileExtensions.contains(ext.lowercased()) else { continue }
            unreadable[FontExplorerImport.UnreadableKind(extension: ext), default: 0] += 1
            containers[id] = nil
        }
        order.removeAll { containers[$0] == nil }

        var faces: [Int: [ImportedFont]] = [:]
        var labelled: [Int: [ImportedFont]] = [:]
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
            if !container.isSystem, container.count > 0 || container.lastActivated != nil {
                library.history.append(ImportedHistory(fonts: fonts(id), count: container.count, last: container.lastActivated))
            }
            if container.isActive, !container.isSystem, !container.isCloud { library.active += fonts(id) }
        }

        let fm = FileManager.default
        var missing = 0
        var inLibrary: [String] = []
        var absentLibrary: (path: String, files: Int)?
        let libraryIsHere = backupFolder == nil && newLibrary.map { fm.fileExists(atPath: $0) } == true
        for id in order {
            guard let container = containers[id], !container.isSystem, !container.isCloud else { continue }
            if let newLibrary, container.path.hasPrefix(newLibrary + "/") {
                if libraryIsHere, !fm.fileExists(atPath: container.path) {
                    missing += 1
                    continue
                }
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
            absentLibrary = (newLibrary, library.fontFolderCount)
            library.fontFolderCount = 0
            library.fontFolderFiles = []
        }
        if library.fontFolderCount == 0 { library.fontFolder = nil }

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

        var setIDs: [Int: String] = [:]
        var deactivating = 0
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

        for (number, color) in FontExplorerImport.labels.sorted(by: { $0.key < $1.key })
        where labelled[number] != nil || ruleLabels.contains(number) {
            library.tags.append(ImportedTag(name: FontExplorerImport.labelName(color), color: color, fonts: labelled[number] ?? []))
        }

        for kind in FontExplorerImport.UnreadableKind.allCases {
            if let count = unreadable[kind] { library.notes.append(kind.describe(count)) }
        }
        if !unreadableSets.isEmpty {
            let names = unreadableSets.map { "“\($0)”" }.listed()
            library.notes.append("the \(unreadableSets.count == 1 ? "set" : "sets") \(names), whose fonts Cicero can’t use")
        }
        if let absentLibrary {
            let place = absentLibrary.path.hasPrefix(home + "/") ? "~" + absentLibrary.path.dropFirst(home.count) : absentLibrary.path
            let files = absentLibrary.files == 1 ? "1 font file" : "\(absentLibrary.files.plain) font files"
            library.notes.append("\(files) in \(place) (not on this Mac)")
        }
        if missing > 0 {
            let other = absentLibrary == nil ? "" : "other "
            library.notes.append(missing == 1 ? "1 \(other)font file that isn’t on this Mac" : "\(missing.plain) \(other)font files that aren’t on this Mac")
        }
        let licensed = containers.values.count(where: \.hasLicense)
        if licensed > 0 { library.notes.append("license details of \(licensed == 1 ? "1 font" : "\(licensed.plain) fonts")") }
        if deactivating > 0 {
            library.notes.append("the fonts \(deactivating == 1 ? "an application set turns" : "\(deactivating) application sets turn") off (Autodeactivate)")
        }
        return library
    }

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

    private func libraryFolder(oldHome: String?, paths: [String]) -> String? {
        if let location = setting("fontFolderLocation") {
            let expanded = location.hasPrefix("~/") ? (oldHome ?? home) + location.dropFirst() : location
            return expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
        }
        guard let oldHome else { return nil }
        let folder = oldHome + "/FontExplorer X/Font Library"
        return paths.contains { $0.hasPrefix(folder + "/") } ? folder : nil
    }

    private func place(library: String, oldHome: String?) -> String {
        if let oldHome, library == oldHome || library.hasPrefix(oldHome + "/") { return home + library.dropFirst(oldHome.count) }
        if backupFolder == nil || FileManager.default.fileExists(atPath: library) { return library }
        return home + "/FontExplorer X/Font Library"
    }

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

    static func home(of path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "Users", parts[1] != "Shared", path.hasPrefix("/") else { return nil }
        return "/Users/\(parts[1])"
    }

    static func mostCommonHome(_ paths: [String]) -> String? {
        var counts: [String: Int] = [:]
        for path in paths { if let home = home(of: path) { counts[home, default: 0] += 1 } }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}
