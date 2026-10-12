import Foundation

/// Everything the user has set up, saved as one JSON file. Version 2; version 1 (`library.json`)
/// is imported once and never modified.
public struct UserData: Codable, Equatable, Sendable {
    public var version = 2
    public var folders: [WatchedFolder] = []
    public var sets: [FontSet] = []
    public var smartSets: [SmartSet] = []
    /// Tag names in sidebar order.
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
    public var records = ActivationRecords()

    public init() {}
}

public struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    /// When set, the folder's fonts count as active inside this app (e.g. "Adobe") rather than inactive.
    public var appName: String?

    /// Point's own folder for fonts it moved out of ~/Library/Fonts.
    public static let deactivatedID = UUID(uuidString: "00000000-0000-0000-0000-0000000DEAD0")!

    public init(id: UUID = UUID(), path: String, appName: String? = nil) {
        self.id = id
        self.path = path
        self.appName = appName
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// "Adobe Fonts" for …/Adobe/Fonts, else the folder's name.
    public var displayName: String {
        if id == Self.deactivatedID { return "Deactivated" }
        let last = url.lastPathComponent
        guard last.caseInsensitiveCompare("Fonts") == .orderedSame else { return last }
        return url.deletingLastPathComponent().lastPathComponent + " Fonts"
    }

    /// Adobe apps load fonts in Application Support/Adobe/Fonts by themselves; nothing else sees them.
    public static func detectAppName(forPath path: String) -> String? {
        let lower = path.lowercased()
        let adobe = "/application support/adobe/fonts"
        return lower.hasSuffix(adobe) || lower.contains(adobe + "/") ? "Adobe" : nil
    }
}

/// A hand-picked group of families.
public struct FontSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var families: [String]

    public init(id: UUID = UUID(), name: String, families: [String] = []) {
        self.id = id
        self.name = name
        self.families = families
    }
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
    /// "tag.<name>", "foundry.<name>", "classification.<name>", "folder.<uuid>". Character sets use `shownCharacterSets`.
    public var hidden: Set<String> = []
    /// Section keys ("folders", "sets", "tags", "foundries", "classifications", "characterSets") that are collapsed.
    public var collapsed: Set<String> = ["foundries", "classifications"]
    /// Character set ids listed in the sidebar; opt-in because there are many.
    public var shownCharacterSets: Set<String> = ["latin-s", "latin-m", "latin-l", "latin-xl"]

    public init() {}
}

public enum InstallMethod: String, Codable, CaseIterable, Sendable {
    case ask
    /// Copy into ~/Library/Fonts.
    case copy
    /// Register the files where they are.
    case inPlace
}

/// What Point did to turn fonts on, so it can turn them off again correctly.
public struct ActivationRecords: Codable, Equatable, Sendable {
    /// Installed copy in ~/Library/Fonts → the file it was copied from.
    public var installedCopies: [String: String] = [:]
    /// Files registered where they are (persistent).
    public var inPlace: Set<String> = []
    /// Files registered for this session.
    public var temporary: [String: TemporaryRecord] = [:]

    public init() {}
}

public struct TemporaryRecord: Codable, Equatable, Sendable {
    public var scope: TemporaryScope
    /// Identifies the login session it was made in (see `ActivationEngine.currentSession`).
    public var session: String

    public init(scope: TemporaryScope, session: String) {
        self.scope = scope
        self.session = session
    }
}
