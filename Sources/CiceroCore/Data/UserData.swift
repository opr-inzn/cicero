import Foundation

/// Everything the user has set up, saved as one JSON file. Version 2; version 1 (`library.json`)
/// is imported once and never modified.
public struct UserData: Codable, Equatable, Sendable {
    public var version = 2
    public var folders: [WatchedFolder] = []
    public var sets: [FontSet] = []
    public var smartSets: [SmartSet] = []
    /// Tag names in sidebar order. Tags have no UI for now; they're kept so none are lost.
    public var tags: [String] = []
    /// Family name → its tags.
    public var familyTags: [String: [String]] = [:]
    /// Family name → foundry, overriding the files' manufacturer.
    public var foundryOverrides: [String: String] = [:]
    /// Manufacturer as the files name it → the name to show.
    public var foundryRenames: [String: String] = [:]
    public var customCharacterSets: [CustomCharacterSet] = []
    public var sidebar = SidebarPreferences()
    public var installMethod: InstallMethod = .ask
    public var showSystemFonts = true
    /// List the fonts in the folders Adobe apps load by themselves, as one Adobe Apps item.
    public var showAdobeFonts = true
    public var records = ActivationRecords()

    public init() {}

    /// Missing keys take their defaults, so files from older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserData()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        version = try value(.version, d.version)
        folders = try value(.folders, d.folders)
        sets = try value(.sets, d.sets)
        smartSets = try value(.smartSets, d.smartSets)
        tags = try value(.tags, d.tags)
        familyTags = try value(.familyTags, d.familyTags)
        foundryOverrides = try value(.foundryOverrides, d.foundryOverrides)
        foundryRenames = try value(.foundryRenames, d.foundryRenames)
        customCharacterSets = try value(.customCharacterSets, d.customCharacterSets)
        sidebar = try value(.sidebar, d.sidebar)
        installMethod = try value(.installMethod, d.installMethod)
        showSystemFonts = try value(.showSystemFonts, d.showSystemFonts)
        showAdobeFonts = try value(.showAdobeFonts, d.showAdobeFonts)
        records = try value(.records, d.records)
    }

    /// Whether anything but the sidebar's choices (order, hidden and collapsed items) differs.
    public func differs(besidesSidebar other: UserData) -> Bool {
        var other = other
        other.sidebar = sidebar
        return self != other
    }

    /// The folders a scan reads: the user's, plus the ones Adobe apps load by themselves when shown.
    public func scannedFolders() -> [WatchedFolder] {
        folders + (showAdobeFonts ? WatchedFolder.appFontFolders() : [])
    }
}

public struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    /// When set, the folder's fonts count as active inside this app (e.g. "Adobe") rather than inactive.
    public var appName: String?

    /// Cicero's own folder for fonts it moved out of ~/Library/Fonts.
    public static let deactivatedID = UUID(uuidString: "00000000-0000-0000-0000-0000000DEAD0")!
    /// The folders Adobe apps load fonts from by themselves. They share this ID: the sidebar shows
    /// them as one item.
    public static let adobeAppsID = UUID(uuidString: "00000000-0000-0000-0000-00000000AD0B")!

    public init(id: UUID = UUID(), path: String, appName: String? = nil) {
        self.id = id
        self.path = path
        self.appName = appName
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// "Deactivated" and "Adobe Apps" for Cicero's own items, "<Parent> Fonts" for other folders
    /// called Fonts, else the name.
    public var displayName: String {
        if id == Self.deactivatedID { return "Deactivated" }
        if id == Self.adobeAppsID { return "Adobe Apps" }
        let last = url.lastPathComponent
        guard last.caseInsensitiveCompare("Fonts") == .orderedSame else { return last }
        return url.deletingLastPathComponent().lastPathComponent + " Fonts"
    }

    private static let adobeFolderSuffix = "/application support/adobe/fonts"

    /// Which app loads a folder's fonts by itself, so they count as active there rather than inactive:
    /// Adobe's shared font folders (all Adobe apps) and the Fonts folder next to an Adobe app
    /// ("Adobe InDesign 2026/Fonts" → "InDesign").
    public static func detectAppName(forPath path: String) -> String? {
        let lower = path.lowercased()
        if lower.hasSuffix(adobeFolderSuffix) || lower.contains(adobeFolderSuffix + "/") { return "Adobe" }
        guard let match = path.firstMatch(of: #/^/Applications/Adobe ([^/]+?)(?: \d{4})?/Fonts(?:/|$)/#.ignoresCase()) else { return nil }
        return String(match.1)
    }

    /// The folders on this Mac that Adobe apps load fonts from by themselves: Adobe's shared folder for
    /// all users and for this account, and the Fonts folder next to any Adobe app (InDesign has one).
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

/// A hand-picked group of families. With apps, it's an application set: Cicero activates its fonts
/// while one of those apps is open.
public struct FontSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var families: [String]
    public var apps: [LinkedApp]

    public init(id: UUID = UUID(), name: String, families: [String] = [], apps: [LinkedApp] = []) {
        self.id = id
        self.name = name
        self.families = families
        self.apps = apps
    }

    /// Sets saved before apps existed load without them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        families = try c.decode([String].self, forKey: .families)
        apps = try c.decodeIfPresent([LinkedApp].self, forKey: .apps) ?? []
    }
}

/// An app an application set is for.
public struct LinkedApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    /// Where the app was when it was picked; for its icon.
    public var path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }

    public var id: String { bundleID }
}

/// A set whose families are picked by rules.
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
}

public struct SmartRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var field: Field
    public var comparison: Comparison
    /// Text, a number, or the id of the chosen option, depending on the field.
    public var value: String

    public init(id: UUID = UUID(), field: Field = .name, comparison: Comparison? = nil, value: String = "") {
        self.id = id
        self.field = field
        self.comparison = comparison ?? field.comparisons[0]
        self.value = value
    }

    public enum Field: String, Codable, CaseIterable, Sendable {
        case name, foundry, classification, tag, set, folder, status, kind, format, styles, language, characterSet, added

        public var comparisons: [Comparison] {
            switch self {
            case .name: [.contains, .doesNotContain, .beginsWith, .is]
            case .foundry: [.is, .isNot, .contains]
            case .styles: [.is, .greaterThan, .lessThan]
            case .added: [.inLast, .notInLast]
            default: [.is, .isNot]
            }
        }
    }

    public enum Comparison: String, Codable, Sendable {
        case contains, doesNotContain, beginsWith, `is`, isNot, greaterThan, lessThan, inLast, notInLast
    }
}

/// Values a smart rule's status, kind and format fields can take.
public enum SmartRuleValue {
    public static let statuses = ["active", "partial", "inactive", "appOnly", "system"]
    public static let kinds = ["variable", "monospaced", "italics"]
}

public struct CustomCharacterSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// What the user typed or pasted: characters, U+ / 0x codes, ranges.
    public var characters: String

    public init(id: UUID = UUID(), name: String, characters: String) {
        self.id = id
        self.name = name
        self.characters = characters
    }

    /// The id used for it among all character sets.
    public var setID: String { "custom.\(id.uuidString)" }
}

public struct SidebarPreferences: Codable, Equatable, Sendable {
    /// Keys of hidden rows and sections: "library.all", "section.sets", "set.<uuid>", "smartset.<uuid>",
    /// "tag.<name>", "foundry.<name>", "classification.<name>", "folder.<uuid>", "charset.<id>".
    public var hidden: Set<String> = []
    /// Collapsed sections ("folders", "sets", "tags", "foundries", "classifications", "characterSets")
    /// and character set groups ("charsetgroup.<group id>").
    public var collapsed: Set<String> = ["foundries", "classifications", "charsetgroup.unicode", "charsetgroup.google"]
    /// Keys in the order the user dragged them into, per list: "sections" (section keys, from when sections
    /// could be dragged; still followed), "library",
    /// a section's rows ("folders", "sets", "foundries", "classifications"), "characterSets" (group keys
    /// "charsetgroup.<group id>") and a group's rows ("charsetgroup.<group id>").
    public var order: [String: [String]] = [:]

    public init() {}

    /// Missing keys take their defaults, so files from before a key existed keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SidebarPreferences()
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? d.hidden
        collapsed = try c.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? d.collapsed
        order = try c.decodeIfPresent([String: [String]].self, forKey: .order) ?? d.order
    }

    /// `items` in the user's order for `list`: the ones placed there, as placed, then the others as given.
    public func ordered<T>(_ items: [T], in list: String, key: (T) -> String) -> [T] {
        guard let saved = order[list], !saved.isEmpty else { return items }
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let placed = items.compactMap { item in rank[key(item)].map { (item, $0) } }
        return placed.sorted { $0.1 < $1.1 }.map(\.0) + items.filter { rank[key($0)] == nil }
    }

    /// Moves the items at `source` in `shown` to `destination`, as a list's onMove gives them. `shown`
    /// is what the list shows, `all` every item in it in its current order: hidden ones keep their places.
    public mutating func move(_ source: IndexSet, to destination: Int, shown: [String], all: [String], in list: String) {
        let moving = source.map { shown[$0] }
        var reordered = shown.indices.filter { !source.contains($0) }.map { shown[$0] }
        reordered.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        let isShown = Set(shown)
        var next = reordered.makeIterator()
        setOrder(all.map { isShown.contains($0) ? next.next() ?? $0 : $0 }, of: list)
    }

    /// Saves `keys` as the order of `list`. Keys saved before that it leaves out, for items that are
    /// gone for now (System Fonts while system fonts are off), stay after the key they followed.
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

    /// For an item that's gone for good.
    public mutating func forget(_ key: String) {
        hidden.remove(key)
        for list in order.keys { order[list]?.removeAll { $0 == key } }
    }

    /// A renamed item stays hidden, and in its place.
    public mutating func rename(_ old: String, to new: String) {
        if hidden.remove(old) != nil { hidden.insert(new) }
        for list in order.keys { order[list] = order[list]?.map { $0 == old ? new : $0 } }
    }
}

public enum InstallMethod: String, Codable, CaseIterable, Sendable {
    case ask
    /// Copy into ~/Library/Fonts.
    case copy
    /// Register the files where they are.
    case inPlace
}

/// What Cicero did to turn fonts on, so it can turn them off again correctly.
public struct ActivationRecords: Codable, Equatable, Sendable {
    /// Installed copy in ~/Library/Fonts → the file it was copied from.
    public var installedCopies: [String: String] = [:]
    /// Files registered where they are (persistent).
    public var inPlace: Set<String> = []
    /// Files registered for this session.
    public var temporary: [String: TemporaryRecord] = [:]
    /// File in Cicero's Deactivated folder → where it was in an app's own folder (Adobe's), which it
    /// left so the app stops loading it.
    public var appFolderOrigins: [String: String] = [:]

    public init() {}

    /// Missing keys take their defaults, so files from older versions keep loading.
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
    /// Identifies the login session it was made in (see `ActivationEngine.currentSession`), so an
    /// application set's record from before a logout is forgotten.
    public var session: String
    /// For `.whileAppsRun`: the bundle IDs of the open apps whose application sets have the file.
    public var apps: [String]?

    public init(scope: TemporaryScope, session: String, apps: [String]? = nil) {
        self.scope = scope
        self.session = session
        self.apps = apps
    }
}
