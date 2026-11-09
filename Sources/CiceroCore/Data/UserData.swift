import Foundation

public struct UserData: Codable, Equatable, Sendable {
    public var version = 2
    public var folders: [WatchedFolder] = []
    public var folderNames: [String: String] = [:]
    public var fontFiles: [String] = []
    public var missingFontFiles: [String: Date] = [:]
    public var sets: [FontSet] = []
    public var smartSets: [SmartSet] = []
    public var tags: [String] = []
    public var familyTags: [String: [String]] = [:]
    public var tagColors: [String: TagColor] = [:]
    public var familyRatings: [String: Int] = [:]
    public var familyNotes: [String: String] = [:]
    public var activations: [String: ActivationHistory] = [:]
    public var licenseStatusesAdded = true
    public var formerLicenseTagsRemoved = true
    public var fontLibraryLocationChecked = true
    public var foundryOverrides: [String: String] = [:]
    public var foundryRenames: [String: String] = [:]
    public var classifications: [String] = []
    public var classificationOverrides: [String: String] = [:]
    public var classificationRenames: [String: String] = [:]
    public var customCharacterSets: [CustomCharacterSet] = []
    public var sidebar = SidebarPreferences()
    public var installMethod: InstallMethod = .copy
    public var installsIntoFontLibrary = false
    public var fontLibraryPath = ""
    public var duplicateHandling: DuplicateHandling = .ask
    public var asksBeforeActivatingMany = true
    public static let manyFamilies = 100
    public var asksBeforeMovingOutOfSharedFolders = true
    public var showSystemFonts = true
    public var showAdobeAppFolders = true
    public var showCreativeCloudFonts = true
    public var activatesDocumentFonts = false
    public var records = ActivationRecords()

    public init() {}

    public static var newLibrary: UserData {
        var data = UserData()
        data.licenseStatusesAdded = false
        data.updateLicenseTags()
        return data
    }

    public static let licenseTags: [(name: String, color: TagColor)] = [
        ("Licensed", .green), ("Unlicensed", .red), ("Open Source", .blue), ("Trial", .orange),
    ]

    public static let formerLicenseTags: [(name: String, color: TagColor)] = [
        ("Licensed + Non-Commercial", .sand), ("Partially Licensed", .yellow), ("Public Domain", .purple),
    ]

    public mutating func updateLicenseTags() {
        if !licenseStatusesAdded {
            licenseStatusesAdded = true
            formerLicenseTagsRemoved = true
            removeUnusedTags([TagColor.red, .yellow, .green].map { ($0.rawValue.capitalized, $0) })
            let missing = Self.licenseTags.filter { !tags.contains($0.name) }
            tags.insert(contentsOf: missing.map(\.name), at: 0)
            for tag in missing { tagColors[tag.name] = tag.color }
        }
        if !formerLicenseTagsRemoved {
            formerLicenseTagsRemoved = true
            removeUnusedTags(Self.formerLicenseTags)
        }
    }

    private mutating func removeUnusedTags(_ candidates: [(name: String, color: TagColor)]) {
        let used = Set(familyTags.values.joined())
            .union(smartSets.flatMap(\.rules).filter { $0.field == .tag }.map(\.value))
        for (name, color) in candidates {
            guard tags.contains(name), tagColors[name] == color, !used.contains(name) else { continue }
            tags.removeAll { $0 == name }
            tagColors[name] = nil
            sidebar.forget("tag.\(name)")
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserData()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        version = try value(.version, d.version)
        folders = try value(.folders, d.folders)
        folderNames = try value(.folderNames, d.folderNames)
        fontFiles = try value(.fontFiles, d.fontFiles).filter { FontFormat.fileExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        missingFontFiles = try value(.missingFontFiles, d.missingFontFiles)
        sets = try value(.sets, d.sets)
        smartSets = try value(.smartSets, d.smartSets)
        tags = try value(.tags, d.tags)
        familyTags = try value(.familyTags, d.familyTags)
        tagColors = try value(.tagColors, [String: String]()).compactMapValues(TagColor.init(rawValue:))
        familyRatings = try value(.familyRatings, d.familyRatings).filter { (1...5).contains($0.value) }
        familyNotes = try value(.familyNotes, d.familyNotes).filter { !$0.value.isEmpty }
        activations = try value(.activations, d.activations)
        licenseStatusesAdded = try value(.licenseStatusesAdded, false)
        formerLicenseTagsRemoved = try value(.formerLicenseTagsRemoved, false)
        fontLibraryLocationChecked = try value(.fontLibraryLocationChecked, false)
        foundryOverrides = try value(.foundryOverrides, d.foundryOverrides)
        foundryRenames = try value(.foundryRenames, d.foundryRenames)
        classifications = try value(.classifications, d.classifications)
        classificationOverrides = try value(.classificationOverrides, d.classificationOverrides)
        classificationRenames = try value(.classificationRenames, d.classificationRenames)
        customCharacterSets = try value(.customCharacterSets, d.customCharacterSets)
        sidebar = try value(.sidebar, d.sidebar)
        installMethod = try value(.installMethod, String?.none).map { InstallMethod(rawValue: $0) ?? .ask } ?? d.installMethod
        installsIntoFontLibrary = try value(.installsIntoFontLibrary, d.installsIntoFontLibrary)
        fontLibraryPath = try value(.fontLibraryPath, d.fontLibraryPath)
        if let location = fontLibraryLocation, let name = folderNames[location.id.uuidString], Self.formerFontLibraryNames.contains(name) {
            folderNames[location.id.uuidString] = nil
        }
        duplicateHandling = try value(.duplicateHandling, String?.none).flatMap(DuplicateHandling.init(rawValue:)) ?? d.duplicateHandling
        asksBeforeActivatingMany = try value(.asksBeforeActivatingMany, d.asksBeforeActivatingMany)
        asksBeforeMovingOutOfSharedFolders = try value(.asksBeforeMovingOutOfSharedFolders, d.asksBeforeMovingOutOfSharedFolders)
        showSystemFonts = try value(.showSystemFonts, d.showSystemFonts)
        showAdobeAppFolders = try c.decodeIfPresent(Bool.self, forKey: .showAdobeAppFolders)
            ?? decoder.container(keyedBy: FormerKeys.self).decodeIfPresent(Bool.self, forKey: .showAdobeFonts)
            ?? d.showAdobeAppFolders
        showCreativeCloudFonts = try value(.showCreativeCloudFonts, d.showCreativeCloudFonts)
        activatesDocumentFonts = try value(.activatesDocumentFonts, d.activatesDocumentFonts)
        records = try value(.records, d.records)
        let serif = classificationRenames[Classification.serif.rawValue] ?? Classification.serif.rawValue
        for set in smartSets.indices {
            for rule in smartSets[set].rules.indices where smartSets[set].rules[rule].field == .classification {
                let value = smartSets[set].rules[rule].value
                if !classifications.contains(value), Classification(saved: value) == .serif, value != Classification.serif.rawValue {
                    smartSets[set].rules[rule].value = serif
                }
            }
        }
    }

    public static let missingFileGrace: TimeInterval = 30 * 24 * 60 * 60

    public mutating func noteGoneFiles(_ gone: Set<String>, at now: Date = Date()) {
        var missing = missingFontFiles.filter { gone.contains($0.key) }
        for path in gone where missing[path] == nil && fontFiles.contains(path) { missing[path] = now }
        let expired = Set(missing.filter { now.timeIntervalSince($0.value) > Self.missingFileGrace }.keys)
        if !expired.isEmpty {
            fontFiles.removeAll(where: expired.contains)
            missing = missing.filter { !expired.contains($0.key) }
        }
        if missing != missingFontFiles { missingFontFiles = missing }
    }

    public func differs(besidesSidebar other: UserData) -> Bool {
        var other = other
        other.sidebar = sidebar
        return self != other
    }

    private enum FormerKeys: String, CodingKey { case showAdobeFonts }

    public func lists(_ family: Family) -> Bool {
        (showSystemFonts || family.state != .system) && (showCreativeCloudFonts || !family.isAdobeFonts)
    }

    public func scannedFolders(appFolders: @autoclosure () -> [WatchedFolder] = WatchedFolder.appFontFolders()) -> [WatchedFolder] {
        folders + (showAdobeAppFolders ? appFolders() : []) + [fontLibrary].compactMap(\.self)
    }

    public var fontLibrary: WatchedFolder? {
        guard installsIntoFontLibrary, !fontLibraryPath.isEmpty else { return nil }
        return WatchedFolder(id: WatchedFolder.fontLibraryID, path: fontLibraryPath)
    }

    static let formerFontLibraryNames: Set<String> = ["Font Library", "Cicero’s Font Library"]

    public var fontLibraryLocation: WatchedFolder? {
        guard !fontLibraryPath.isEmpty else { return nil }
        let path = URL(fileURLWithPath: fontLibraryPath).standardizedFileURL.path
        return folders.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }
    }

    @discardableResult
    public mutating func keepFontLibraryAsLocation(hasFonts: Bool) -> WatchedFolder? {
        guard hasFonts, !fontLibraryPath.isEmpty, fontLibraryLocation == nil else { return nil }
        let location = WatchedFolder(path: fontLibraryPath)
        folders.append(location)
        if let given = folderNames[WatchedFolder.fontLibraryID.uuidString] { folderNames[location.id.uuidString] = given }
        return location
    }

    @discardableResult
    public mutating func takeBackFontLibrary() -> WatchedFolder? {
        guard let location = fontLibraryLocation else { return nil }
        folders.removeAll { $0.id == location.id }
        folderNames[location.id.uuidString] = nil
        sidebar.forget("folder.\(location.id)")
        return location
    }

    public mutating func keepFormerFontLibraryAsLocation(hasFonts: (URL) -> Bool) {
        guard !fontLibraryLocationChecked else { return }
        fontLibraryLocationChecked = true
        guard !installsIntoFontLibrary, !fontLibraryPath.isEmpty else { return }
        keepFontLibraryAsLocation(hasFonts: hasFonts(URL(fileURLWithPath: fontLibraryPath, isDirectory: true)))
    }

    public func named(_ folder: WatchedFolder) -> WatchedFolder {
        var folder = folder
        folder.customName = folderNames[folder.id.uuidString]
        if folder.customName == nil, folder.id != WatchedFolder.fontLibraryID, folder.id == fontLibraryLocation?.id {
            folder.customName = WatchedFolder(id: WatchedFolder.fontLibraryID, path: fontLibraryPath).displayName
        }
        return folder
    }

    public var namedFolders: [WatchedFolder] { folders.map(named) }

    public mutating func recordActivations(from old: Library, to new: Library, at date: Date = Date()) {
        guard !old.families.isEmpty else { return }
        for family in new.families where family.hasActive && family.state != .system && !old.offlineFamilies.contains(family.id) {
            if old.family(family.id)?.hasActive == true { continue }
            var history = activations[family.id] ?? ActivationHistory()
            history.count += 1
            history.last = date
            activations[family.id] = history
        }
    }

    public func tags(of family: String) -> [String] {
        guard let names = familyTags[family], !names.isEmpty else { return [] }
        return tags.filter(names.contains)
    }
}

public struct ActivationHistory: Codable, Equatable, Sendable {
    public var count = 0
    public var last: Date?

    public init(count: Int = 0, last: Date? = nil) {
        self.count = count
        self.last = last
    }
}

public enum TagColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, gray, sand

    public static func next(after taken: some Sequence<TagColor>) -> TagColor {
        let used = Set(taken)
        return allCases.first { !used.contains($0) } ?? .red
    }
}

public struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    public var appName: String?
    public var isActive: Bool
    public var customName: String?

    public static let inactiveFolderID = UUID(uuidString: "00000000-0000-0000-0000-0000000DEAD0")!
    public static let fontLibraryID = UUID(uuidString: "00000000-0000-0000-0000-000000F0711B")!
    public static let adobeAppsID = UUID(uuidString: "00000000-0000-0000-0000-00000000AD0B")!
    public static let adobeFontsID = UUID(uuidString: "00000000-0000-0000-0000-0000AD0BEF00")!
    public static let addedFilesID = UUID(uuidString: "00000000-0000-0000-0000-0000000ADDED")!

    public init(id: UUID = UUID(), path: String, appName: String? = nil, isActive: Bool = false) {
        self.id = id
        self.path = path
        self.appName = appName
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey { case id, path, appName, isActive }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public var displayName: String {
        if let customName { return customName }
        if id == Self.inactiveFolderID { return "Inactive" }
        if id == Self.fontLibraryID { return "Cicero’s Library" }
        if id == Self.adobeAppsID { return "Proofing" }
        if id == Self.adobeFontsID { return "Adobe Fonts" }
        if id == Self.addedFilesID { return "Added Fonts" }
        let last = url.lastPathComponent
        guard last.caseInsensitiveCompare("Fonts") == .orderedSame else { return last }
        return url.deletingLastPathComponent().lastPathComponent + " Fonts"
    }

    private static let adobeFolderSuffix = "/application support/adobe/fonts"

    public static func detectAppName(forPath path: String) -> String? {
        let lower = path.lowercased()
        if lower.hasSuffix(adobeFolderSuffix) || lower.contains(adobeFolderSuffix + "/") { return "Adobe" }
        guard let match = path.firstMatch(of: #/^/Applications/Adobe ([^/]+?)(?: \d{4})?/Fonts(?:/|$)/#.ignoresCase()) else { return nil }
        return String(match.1)
    }

    public static func appFontFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [WatchedFolder] {
        let fm = FileManager.default
        var paths = [
            "/Library/Application Support/Adobe/Fonts",
            home.appendingPathComponent("Library/Application Support/Adobe/Fonts").path,
        ]
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for app in apps.sorted() where app.hasPrefix("Adobe ") {
            paths.append("/Applications/\(app)/Fonts")
        }
        return paths.compactMap { path in
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let app = detectAppName(forPath: path)
            else { return nil }
            return WatchedFolder(id: adobeAppsID, path: path, appName: app)
        }
    }
}

public struct FontSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var families: [String]
    public var styles: [String: [String]]
    public var apps: [LinkedApp]

    public init(id: UUID = UUID(), name: String, families: [String] = [], styles: [String: [String]] = [:], apps: [LinkedApp] = []) {
        self.id = id
        self.name = name
        self.families = families
        self.styles = styles
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        families = try c.decode([String].self, forKey: .families)
        styles = try c.decodeIfPresent([String: [String]].self, forKey: .styles) ?? [:]
        apps = try c.decodeIfPresent([LinkedApp].self, forKey: .apps) ?? []
    }

    public var memberFamilies: [String] {
        families + styles.filter { !$0.value.isEmpty && !families.contains($0.key) }.keys.sorted()
    }

    public func contains(style: String, of family: String) -> Bool {
        families.contains(family) || (styles[family] ?? []).contains(style)
    }

    public mutating func add(families names: [String]) {
        for name in names where !families.contains(name) { families.append(name) }
        for name in names { styles[name] = nil }
    }

    public mutating func remove(families names: Set<String>) {
        families.removeAll { names.contains($0) }
        for name in names { styles[name] = nil }
    }

    public mutating func add(style: String, of family: String) {
        guard !families.contains(family) else { return }
        var list = styles[family] ?? []
        if !list.contains(style) { list.append(style) }
        styles[family] = list
    }

    public mutating func remove(style: String, of family: String, all: [String]) {
        let left: [String]
        if let index = families.firstIndex(of: family) {
            families.remove(at: index)
            left = all.filter { $0 != style }
        } else {
            left = (styles[family] ?? []).filter { $0 != style }
        }
        styles[family] = left.isEmpty ? nil : left
    }
}

public struct LinkedApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }

    public var id: String { bundleID }
}

public struct SmartSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var matchAll: Bool
    public var rules: [SmartRule]

    public init(id: UUID = UUID(), name: String, matchAll: Bool = true, rules: [SmartRule] = [SmartRule()]) {
        self.id = id
        self.name = name
        self.matchAll = matchAll
        self.rules = rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        matchAll = try c.decode(Bool.self, forKey: .matchAll)
        rules = try c.decode([Readable<SmartRule>].self, forKey: .rules).compactMap(\.value)
    }
}

private struct Readable<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

public struct SmartRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var field: Field
    public var comparison: Comparison
    public var value: String

    public init(id: UUID = UUID(), field: Field = .name, comparison: Comparison? = nil, value: String = "") {
        self.id = id
        self.field = field
        self.comparison = comparison ?? field.comparisons[0]
        self.value = value
    }

    public enum Field: String, Codable, CaseIterable, Sendable {
        case name, foundry, designer, classification, tag, rating, note, hasNote, set, folder, status, kind, format, styles, feature, embedding
        case language, characterSet, added, timesActivated, lastActivated

        public static let offered = allCases.filter { $0 != .timesActivated && $0 != .lastActivated }

        public var comparisons: [Comparison] {
            switch self {
            case .name: [.contains, .doesNotContain, .beginsWith, .is]
            case .foundry: [.is, .isNot, .contains]
            case .designer: [.contains, .doesNotContain, .is]
            case .note: [.contains, .doesNotContain]
            case .rating: [.is, .isNot, .greaterThan, .lessThan]
            case .styles, .timesActivated: [.is, .greaterThan, .lessThan]
            case .added, .lastActivated: [.inLast, .notInLast]
            default: [.is, .isNot]
            }
        }
    }

    public enum Comparison: String, Codable, Sendable {
        case contains, doesNotContain, beginsWith, `is`, isNot, greaterThan, lessThan, inLast, notInLast
    }
}

public enum SmartRuleValue {
    public static let statuses = ["active", "partial", "inactive", "appOnly", "system"]
    public static let kinds = ["italics", "monospaced", "variable"]
}

public struct CustomCharacterSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var characters: String

    public init(id: UUID = UUID(), name: String, characters: String) {
        self.id = id
        self.name = name
        self.characters = characters
    }

    public var setID: String { "custom.\(id.uuidString)" }
}

public struct SidebarPreferences: Codable, Equatable, Sendable {
    public var hidden: Set<String> = []
    public var collapsed: Set<String> = ["foundries", "characterSets", "charsetgroup.unicode", "charsetgroup.google"]
    public var order: [String: [String]] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SidebarPreferences()
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? d.hidden
        collapsed = try c.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? d.collapsed
        order = try c.decodeIfPresent([String: [String]].self, forKey: .order) ?? d.order
    }

    public func ordered<T>(_ items: [T], in list: String, key: (T) -> String) -> [T] {
        guard let saved = order[list], !saved.isEmpty else { return items }
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let placed = items.compactMap { item in rank[key(item)].map { (item, $0) } }
        return placed.sorted { $0.1 < $1.1 }.map(\.0) + items.filter { rank[key($0)] == nil }
    }

    public mutating func move(_ source: IndexSet, to destination: Int, shown: [String], all: [String], in list: String) {
        let moving = source.map { shown[$0] }
        var reordered = shown.indices.filter { !source.contains($0) }.map { shown[$0] }
        reordered.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        let isShown = Set(shown)
        var next = reordered.makeIterator()
        setOrder(all.map { isShown.contains($0) ? next.next() ?? $0 : $0 }, of: list)
    }

    public mutating func setOrder(_ keys: [String], of list: String) {
        var result = keys
        let present = Set(keys)
        var previous: String?
        for key in order[list] ?? [] {
            if !present.contains(key) {
                let index = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                result.insert(key, at: index)
            }
            previous = key
        }
        order[list] = result
    }

    public mutating func forget(_ key: String) {
        hidden.remove(key)
        for list in order.keys { order[list]?.removeAll { $0 == key } }
    }

    public mutating func rename(_ old: String, to new: String) {
        if hidden.remove(old) != nil { hidden.insert(new) }
        for list in order.keys { order[list] = order[list]?.map { $0 == old ? new : $0 } }
    }
}

public enum InstallMethod: String, Codable, CaseIterable, Sendable {
    case ask
    case copy
    case move
    case inPlace
}

public struct ActivationRecords: Codable, Equatable, Sendable {
    public var installedCopies: [String: String] = [:]
    public var inPlace: Set<String> = []
    public var temporary: [String: TemporaryRecord] = [:]
    public var appFolderOrigins: [String: String] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installedCopies = try c.decodeIfPresent([String: String].self, forKey: .installedCopies) ?? [:]
        inPlace = try c.decodeIfPresent(Set<String>.self, forKey: .inPlace) ?? []
        temporary = try c.decodeIfPresent([String: TemporaryRecord].self, forKey: .temporary) ?? [:]
        appFolderOrigins = try c.decodeIfPresent([String: String].self, forKey: .appFolderOrigins) ?? [:]
    }
}

public struct TemporaryRecord: Codable, Equatable, Sendable {
    public var scope: TemporaryScope
    public var session: String
    public var apps: [String]?

    public init(scope: TemporaryScope, session: String, apps: [String]? = nil) {
        self.scope = scope
        self.session = session
        self.apps = apps
    }
}
