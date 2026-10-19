import Foundation

/// Everything the user has set up, saved as one JSON file. Version 2; version 1 (`library.json`)
/// is imported once and never modified.
public struct UserData: Codable, Equatable, Sendable {
    public var version = 2
    public var folders: [WatchedFolder] = []
    /// Folder ID → the name the user gave it in the sidebar, in place of its own (`WatchedFolder.displayName`); the
    /// folder on disk keeps its name. Cicero's own items (Testing, Adobe Fonts, Added Fonts, Deactivated) take one too.
    public var folderNames: [String: String] = [:]
    /// Font files added one at a time (Add Fonts…, dropped on the window, or opened from the Finder), listed
    /// where they are, like the fonts in a folder.
    public var fontFiles: [String] = []
    /// Added files the last scans found gone, and since when (see `noteGoneFiles`).
    public var missingFontFiles: [String: Date] = [:]
    public var sets: [FontSet] = []
    public var smartSets: [SmartSet] = []
    /// Tags, in the order they were made; the license tags to begin with (see `licenseTags`). From 1.5 to 1.6 they were
    /// license statuses, one to a family; a family can have any number again.
    public var tags: [String] = []
    /// Family name → its tags (see `tags`).
    public var familyTags: [String: [String]] = [:]
    /// Tag → its colour. A tag without one has none.
    public var tagColors: [String: TagColor] = [:]
    /// Family name → the stars the user gave it, 1…5. A family without any has no rating.
    public var familyRatings: [String: Int] = [:]
    /// Family name → the user's note on it. A family without one has none, never an empty one.
    public var familyNotes: [String: String] = [:]
    /// Family name → how often it was turned on, and when last, since Cicero began counting (see `recordActivations`).
    public var activations: [String: ActivationHistory] = [:]
    /// False only for libraries saved before there were license tags (license statuses, as they were in 1.5), which get
    /// them once as they load (see `addLicenseTags`).
    public var licenseStatusesAdded = true
    /// Family name → foundry, overriding the files' manufacturer.
    public var foundryOverrides: [String: String] = [:]
    /// Manufacturer as the files name it → the name to show.
    public var foundryRenames: [String: String] = [:]
    /// Classifications the user made, in the order they were made.
    public var classifications: [String] = []
    /// Family name → the classification the user put it in, overriding the one its fonts suggest.
    public var classificationOverrides: [String: String] = [:]
    /// A built-in classification (`Classification.rawValue`) → the name to show.
    public var classificationRenames: [String: String] = [:]
    public var customCharacterSets: [CustomCharacterSet] = []
    public var sidebar = SidebarPreferences()
    public var installMethod: InstallMethod = .ask
    /// The fonts Cicero installs go into its Font Library (`fontLibraryPath`), a folder for each family, and are used from
    /// there, rather than copied into ~/Library/Fonts (see `ActivationEngine.installsIntoFontLibrary`).
    public var installsIntoFontLibrary = false
    /// Where Cicero's Font Library is: `Locations.defaultFontLibrary` unless the user moved it. Empty in files from before
    /// there was one, until the app fills in the default.
    public var fontLibraryPath = ""
    /// What to do with an added font file whose fonts the library has already, from another file.
    public var duplicateHandling: DuplicateHandling = .ask
    /// Ask before turning on more than `manyFamilies` families at once.
    public var asksBeforeActivatingMany = true
    /// How many families at once turning on can be without asking first (see `asksBeforeActivatingMany`).
    public static let manyFamilies = 100
    public var showSystemFonts = true
    /// List the fonts in the folders Adobe apps load by themselves, where type designers put fonts to test them,
    /// as one Testing item. Not Adobe Fonts from Creative Cloud (see `showCreativeCloudFonts`).
    public var showAdobeAppFolders = true
    /// List the Adobe Fonts Creative Cloud turned on, as Adobe Fonts: those on in every app and those Adobe apps turned
    /// on for themselves. A family the user also has a copy of is theirs, and listed either way. Not `showAdobeFonts`,
    /// the key `showAdobeAppFolders` was saved as before.
    public var showCreativeCloudFonts = true
    public var records = ActivationRecords()

    public init() {}

    /// What a new library starts with: the license tags, in their colours, on no family.
    public static var newLibrary: UserData {
        var data = UserData()
        data.licenseStatusesAdded = false
        data.addLicenseTags()
        return data
    }

    /// The tags a library starts with, for keeping track of what may be done with each family, in their order and
    /// colours. Tags like any other: the user can rename or delete them.
    public static let licenseTags: [(name: String, color: TagColor)] = [
        ("Licensed", .green), ("Licensed + Non-Commercial", .sand), ("Unlicensed", .red), ("Partially Licensed", .yellow),
        ("Public Domain", .purple), ("Open Source", .blue), ("Trial", .orange),
    ]

    /// Puts the license tags it doesn't have yet first, in their colours, once. Red, Yellow and Green, the tags a
    /// library started with before, go when they're as they came: in their colours, on no family and in no smart set.
    /// Tags of the user's own stay, after these.
    public mutating func addLicenseTags() {
        guard !licenseStatusesAdded else { return }
        licenseStatusesAdded = true
        let used = Set(familyTags.values.joined())
            .union(smartSets.flatMap(\.rules).filter { $0.field == .tag }.map(\.value))
        for color in [TagColor.red, .yellow, .green] {
            let name = color.rawValue.capitalized
            guard tags.contains(name), tagColors[name] == color, !used.contains(name) else { continue }
            tags.removeAll { $0 == name }
            tagColors[name] = nil
            sidebar.forget("tag.\(name)")
        }
        let missing = Self.licenseTags.filter { !tags.contains($0.name) }
        tags.insert(contentsOf: missing.map(\.name), at: 0)
        for tag in missing { tagColors[tag.name] = tag.color }
    }

    /// Missing keys take their defaults, so files from older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserData()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        version = try value(.version, d.version)
        folders = try value(.folders, d.folders)
        folderNames = try value(.folderNames, d.folderNames)
        // Web fonts, which versions before 1.6 added, are no longer read.
        fontFiles = try value(.fontFiles, d.fontFiles).filter { FontFormat.fileExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        missingFontFiles = try value(.missingFontFiles, d.missingFontFiles)
        sets = try value(.sets, d.sets)
        smartSets = try value(.smartSets, d.smartSets)
        tags = try value(.tags, d.tags)
        familyTags = try value(.familyTags, d.familyTags)
        // A colour a later version adds is no colour here, rather than a file that doesn't load.
        tagColors = try value(.tagColors, [String: String]()).compactMapValues(TagColor.init(rawValue:))
        familyRatings = try value(.familyRatings, d.familyRatings).filter { (1...5).contains($0.value) }
        familyNotes = try value(.familyNotes, d.familyNotes).filter { !$0.value.isEmpty }
        activations = try value(.activations, d.activations)
        // Missing in files from before there were license tags, which are yet to get them.
        licenseStatusesAdded = try value(.licenseStatusesAdded, false)
        foundryOverrides = try value(.foundryOverrides, d.foundryOverrides)
        foundryRenames = try value(.foundryRenames, d.foundryRenames)
        classifications = try value(.classifications, d.classifications)
        classificationOverrides = try value(.classificationOverrides, d.classificationOverrides)
        classificationRenames = try value(.classificationRenames, d.classificationRenames)
        customCharacterSets = try value(.customCharacterSets, d.customCharacterSets)
        sidebar = try value(.sidebar, d.sidebar)
        // A way a later version adds is Ask here, rather than a file that doesn't load.
        installMethod = try value(.installMethod, String?.none).flatMap(InstallMethod.init(rawValue:)) ?? d.installMethod
        installsIntoFontLibrary = try value(.installsIntoFontLibrary, d.installsIntoFontLibrary)
        fontLibraryPath = try value(.fontLibraryPath, d.fontLibraryPath)
        // The same for a choice a later version adds.
        duplicateHandling = try value(.duplicateHandling, String?.none).flatMap(DuplicateHandling.init(rawValue:)) ?? d.duplicateHandling
        asksBeforeActivatingMany = try value(.asksBeforeActivatingMany, d.asksBeforeActivatingMany)
        showSystemFonts = try value(.showSystemFonts, d.showSystemFonts)
        // Saved as showAdobeFonts before, a name that sounded like Adobe Fonts from Creative Cloud.
        showAdobeAppFolders = try c.decodeIfPresent(Bool.self, forKey: .showAdobeAppFolders)
            ?? decoder.container(keyedBy: FormerKeys.self).decodeIfPresent(Bool.self, forKey: .showAdobeFonts)
            ?? d.showAdobeAppFolders
        showCreativeCloudFonts = try value(.showCreativeCloudFonts, d.showCreativeCloudFonts)
        records = try value(.records, d.records)
        // Rules for Slab Serif, a classification there used to be, pick Serif, which it's part of now; unless
        // Slab Serif is one of the user's.
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

    /// How long an added file can be gone before it leaves the list of added files.
    public static let missingFileGrace: TimeInterval = 30 * 24 * 60 * 60

    /// Takes the added files a scan found gone (deleted, or their folder moved): they're out of the library at once, but
    /// stay listed for `missingFileGrace`, so one that's back by then, as after its folder is renamed back or a cloud
    /// service is signed in to again, is in the library again. Files found again are no longer missing.
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

    /// Whether anything but the sidebar's choices (order, hidden and collapsed items) differs.
    public func differs(besidesSidebar other: UserData) -> Bool {
        var other = other
        other.sidebar = sidebar
        return self != other
    }

    private enum FormerKeys: String, CodingKey { case showAdobeFonts }

    /// Whether the library lists a family: those that come with macOS, and those from Creative Cloud, only when shown.
    public func lists(_ family: Family) -> Bool {
        (showSystemFonts || family.state != .system) && (showCreativeCloudFonts || !family.isAdobeFonts)
    }

    /// The folders a scan reads: the user's, plus the ones Adobe apps load by themselves when shown, and the Font Library.
    public func scannedFolders() -> [WatchedFolder] {
        folders + (showAdobeAppFolders ? WatchedFolder.appFontFolders() : []) + [fontLibrary].compactMap(\.self)
    }

    /// Cicero's Font Library as a folder the scan reads, whether or not fonts are installed into it now: the fonts in it
    /// stay in the library. nil until it has a place.
    public var fontLibrary: WatchedFolder? {
        fontLibraryPath.isEmpty ? nil : WatchedFolder(id: WatchedFolder.fontLibraryID, path: fontLibraryPath)
    }

    /// A folder with the name the user gave it, if any, as its `displayName`.
    public func named(_ folder: WatchedFolder) -> WatchedFolder {
        var folder = folder
        folder.customName = folderNames[folder.id.uuidString]
        return folder
    }

    /// The user's folders, with the names given them.
    public var namedFolders: [WatchedFolder] { folders.map(named) }

    /// Counts the families that came on between two libraries, the one before a scan and the one after: those with no
    /// style on before (or not there before, as when they're installed) and some after, wherever they were turned on, by
    /// Cicero, an application set or another app. Not those that come with macOS, nor ones on a disk that wasn't there
    /// before; and none at all without a library before to compare with, as at the first launch.
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

    /// The tags a family has, in the order they were made.
    public func tags(of family: String) -> [String] {
        guard let names = familyTags[family], !names.isEmpty else { return [] }
        return tags.filter(names.contains)
    }
}

/// How often a family was turned on, and when last.
public struct ActivationHistory: Codable, Equatable, Sendable {
    public var count = 0
    public var last: Date?

    public init(count: Int = 0, last: Date? = nil) {
        self.count = count
        self.last = last
    }
}

/// The colours a tag can have: the Finder's, and sand, for Licensed + Non-Commercial.
public enum TagColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, gray, sand

    /// The first colour no tag has yet, in this order, so new ones tell apart; red again once all are taken.
    public static func next(after taken: some Sequence<TagColor>) -> TagColor {
        let used = Set(taken)
        return allCases.first { !used.contains($0) } ?? .red
    }
}

public struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    /// When set, the folder's fonts count as active inside this app (e.g. "Adobe") rather than inactive.
    public var appName: String?
    /// Active: Cicero keeps every font in the folder on, where it is, including ones added to it later.
    public var isActive: Bool
    /// The name the user gave it (`UserData.folderNames`), set on copies made to show; not saved with the folder.
    public var customName: String?

    /// Cicero's own folder for fonts it moved out of ~/Library/Fonts.
    public static let deactivatedID = UUID(uuidString: "00000000-0000-0000-0000-0000000DEAD0")!
    /// Cicero's Font Library (see `UserData.fontLibraryPath`).
    public static let fontLibraryID = UUID(uuidString: "00000000-0000-0000-0000-000000F0711B")!
    /// The folders Adobe apps load fonts from by themselves. They share this ID: the sidebar shows
    /// them as one item.
    public static let adobeAppsID = UUID(uuidString: "00000000-0000-0000-0000-00000000AD0B")!
    /// Adobe Fonts from Creative Cloud, wherever it keeps them: an item of their own, apart from Adobe's folders.
    public static let adobeFontsID = UUID(uuidString: "00000000-0000-0000-0000-0000AD0BEF00")!
    /// The font files added one at a time, which the sidebar lists as one item with the folders.
    public static let addedFilesID = UUID(uuidString: "00000000-0000-0000-0000-0000000ADDED")!

    public init(id: UUID = UUID(), path: String, appName: String? = nil, isActive: Bool = false) {
        self.id = id
        self.path = path
        self.appName = appName
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey { case id, path, appName, isActive }

    /// Folders saved before there was Active have no `isActive`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The name the user gave it; else "Deactivated", "Font Library", "Testing" (Adobe's folders, where type designers
    /// test fonts), "Adobe Fonts" and "Added Fonts" for Cicero's own items, "<Parent> Fonts" for other folders called Fonts,
    /// else the name.
    public var displayName: String {
        if let customName { return customName }
        if id == Self.deactivatedID { return "Deactivated" }
        if id == Self.fontLibraryID { return "Font Library" }
        if id == Self.adobeAppsID { return "Testing" }
        if id == Self.adobeFontsID { return "Adobe Fonts" }
        if id == Self.addedFilesID { return "Added Fonts" }
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

/// A hand-picked group of families, or of some of their styles. With apps, it's an application set: Cicero activates its
/// fonts while one of those apps is open.
public struct FontSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The families it has whole.
    public var families: [String]
    /// Family name → the styles of it the set has, by PostScript name, for families only some of whose styles are in it.
    public var styles: [String: [String]]
    public var apps: [LinkedApp]

    public init(id: UUID = UUID(), name: String, families: [String] = [], styles: [String: [String]] = [:], apps: [LinkedApp] = []) {
        self.id = id
        self.name = name
        self.families = families
        self.styles = styles
        self.apps = apps
    }

    /// Sets saved before apps, or styles, existed load without them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        families = try c.decode([String].self, forKey: .families)
        styles = try c.decodeIfPresent([String: [String]].self, forKey: .styles) ?? [:]
        apps = try c.decodeIfPresent([LinkedApp].self, forKey: .apps) ?? []
    }

    /// Every family it has, whole or in part: the whole ones in their order, then the others by name.
    public var memberFamilies: [String] {
        families + styles.filter { !$0.value.isEmpty && !families.contains($0.key) }.keys.sorted()
    }

    /// Whether it has this style of the family (by PostScript name): the whole family, or that style.
    public func contains(style: String, of family: String) -> Bool {
        families.contains(family) || (styles[family] ?? []).contains(style)
    }

    /// Puts families in whole, after the others, in place of the styles of them it had.
    public mutating func add(families names: [String]) {
        for name in names where !families.contains(name) { families.append(name) }
        for name in names { styles[name] = nil }
    }

    /// Takes families out, whole or in part.
    public mutating func remove(families names: Set<String>) {
        families.removeAll { names.contains($0) }
        for name in names { styles[name] = nil }
    }

    /// Adds a style of a family; a family it has whole stays so.
    public mutating func add(style: String, of family: String) {
        guard !families.contains(family) else { return }
        var list = styles[family] ?? []
        if !list.contains(style) { list.append(style) }
        styles[family] = list
    }

    /// Takes a style out. A family it has whole keeps its other styles, `all` of them (by PostScript name) but this one.
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

    /// A rule on a field, or with a comparison, a later version adds is left out here, rather than a file that doesn't load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        matchAll = try c.decode(Bool.self, forKey: .matchAll)
        rules = try c.decode([Readable<SmartRule>].self, forKey: .rules).compactMap(\.value)
    }
}

/// An element of a list as this version can read it; nil for one it can't, as one a later version saved, so the rest
/// of the list loads.
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
    /// Text, a number, or the id of the chosen option, depending on the field.
    public var value: String

    public init(id: UUID = UUID(), field: Field = .name, comparison: Comparison? = nil, value: String = "") {
        self.id = id
        self.field = field
        self.comparison = comparison ?? field.comparisons[0]
        self.value = value
    }


    public enum Field: String, Codable, CaseIterable, Sendable {
        case name, foundry, designer, classification, tag, rating, note, set, folder, status, kind, format, styles, feature, embedding
        case language, characterSet, added, timesActivated, lastActivated

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
    /// Move files added one at a time into ~/Library/Fonts, leaving the folders they were in;
    /// copy the rest, so the user's folders stay as they are.
    case move
    /// Register the files where they are.
    case inPlace
}

/// What Cicero did to turn fonts on, so it can turn them off again correctly.
public struct ActivationRecords: Codable, Equatable, Sendable {
    /// Installed copy → the file it was copied from: in ~/Library/Fonts, or in Cicero's Font Library, where it's
    /// registered where it is (in `inPlace`) while it's on.
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
