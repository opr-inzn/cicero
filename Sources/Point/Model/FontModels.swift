import Foundation

/// A variation axis, used for continuous weight on variable fonts.
struct VariationAxis: Codable, Hashable, Sendable {
    var tag: UInt32
    var min: Double
    var max: Double
}

/// One face (style) inside a font file, as read from disk. Cached between launches.
struct FontFace: Codable, Hashable, Sendable, Identifiable {
    var path: String
    var index: Int
    var postScriptName: String
    var familyName: String
    var styleName: String
    var fullName: String
    var weightClass: Int
    var isItalic: Bool
    var isMonospace: Bool
    var fontClass: Int
    var manufacturer: String?
    var weightAxis: VariationAxis?

    var id: String { "\(path)#\(index)" }
    var url: URL { URL(fileURLWithPath: path, isDirectory: false) }
}

/// Where an active face is activated from. Decides whether Point may deactivate it.
enum ActiveKind: Hashable, Sendable {
    case system        // ships with macOS: /System/Library/Fonts and Apple's downloadable fonts
    case allUsers      // /Library/Fonts, installed for every user (needs an admin to change)
    case application   // shipped inside an app bundle
    case adobeCloud    // Adobe Fonts synced by Creative Cloud
    case user          // ~/Library/Fonts
    case registered    // registered in place by Point
    case temporary(TemporaryScope)  // registered in place by Point for this session only
    case other         // registered by another app

    var isUserControllable: Bool {
        switch self {
        case .user, .registered, .temporary, .other: true
        case .system, .allUsers, .application, .adobeCloud: false
        }
    }

    var isTemporary: Bool {
        if case .temporary = self { return true }
        return false
    }
}

enum FaceStatus: Hashable, Sendable {
    case active(ActiveKind)
    case inactive
    /// Not active system-wide, but loaded privately by specific apps (e.g. Adobe's Fonts folder).
    case appOnly(String)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var activeKind: ActiveKind? {
        if case .active(let kind) = self { return kind }
        return nil
    }

    var label: String {
        switch self {
        case .active(.system): "Installed with macOS"
        case .active(.allUsers): "Installed for all users"
        case .active(.application): "App font"
        case .active(.adobeCloud): "Adobe Fonts"
        case .active(.temporary(let scope)): scope.statusLabel
        case .active: "Active"
        case .inactive: "Inactive"
        case .appOnly(let app): "Active in \(app) apps"
        }
    }
}

enum FamilyStatus: Hashable, Sendable {
    case active
    case partial
    case inactive
    case appOnly(String)
    case system
}

struct LibraryFace: Identifiable, Hashable, Sendable {
    var face: FontFace
    var status: FaceStatus
    /// Other files on disk containing the same PostScript name (e.g. the original of an installed copy).
    var otherPaths: [String] = []
    /// When the earliest of those files arrived in its folder.
    var added: Date?

    var id: String { face.id }
    var canActivate: Bool { !status.isActive }
    var canDeactivate: Bool { status.activeKind?.isUserControllable ?? false }
    var isTemporary: Bool { status.activeKind?.isTemporary ?? false }
}

/// A standard typeface classification, read from the font's own metadata (OS/2 family class) with
/// a few name-based fallbacks. Users organise further with tags.
enum FontClassification: String, CaseIterable, Sendable {
    case serif = "Serif"
    case slabSerif = "Slab Serif"
    case sansSerif = "Sans Serif"
    case monospaced = "Monospaced"
    case script = "Script"
    case ornamental = "Ornamental"
    case symbol = "Symbol"
    case unclassified = "Unclassified"

    var icon: String {
        switch self {
        case .serif: "textformat"
        case .slabSerif: "rectangle.split.3x1"
        case .sansSerif: "textformat.alt"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        case .script: "scribble.variable"
        case .ornamental: "sparkles"
        case .symbol: "star.square.on.square"
        case .unclassified: "questionmark.square.dashed"
        }
    }
}

struct FontFamily: Identifiable, Hashable, Sendable {
    let name: String
    let faces: [LibraryFace]
    let status: FamilyStatus
    let folderIDs: Set<UUID>
    let manufacturer: String?
    /// When the family's first file arrived in its folder.
    let dateAdded: Date?
    // Worked out once: lists, sorting and smart sets read these for every family on every render.
    let classification: FontClassification
    /// File format, or "Mixed" when styles come in different formats.
    let format: String
    let isVariable: Bool
    let isMonospaced: Bool
    /// The regular upright style, which stands for the family in coverage checks.
    let regularFace: FontFace

    init(name: String, faces: [LibraryFace], status: FamilyStatus, folderIDs: Set<UUID>, manufacturer: String?, dateAdded: Date? = nil) {
        self.name = name
        self.faces = faces
        self.status = status
        self.folderIDs = folderIDs
        self.manufacturer = manufacturer
        self.dateAdded = dateAdded
        isVariable = faces.contains { $0.face.weightAxis != nil }
        isMonospaced = faces.contains { $0.face.isMonospace }
        let formats = Set(faces.map { FontMetadata.format(ofExtension: ($0.face.path as NSString).pathExtension) })
        format = formats.count == 1 ? formats.first! : "Mixed"
        classification = Self.classify(name: name, faces: faces, isMonospaced: isMonospaced)
        regularFace = Self.nearest(400, in: faces).face
    }

    var id: String { name }

    var stylesLabel: String { faces.count == 1 ? "1 style" : "\(faces.count) styles" }
    var activeFaceCount: Int { faces.filter { $0.status.isActive }.count }

    private static func classify(name: String, faces: [LibraryFace], isMonospaced: Bool) -> FontClassification {
        if isMonospaced { return .monospaced }
        let upright = faces.first { !$0.face.isItalic } ?? faces[0]
        switch upright.face.fontClass {
        case 1, 2, 3, 7: return .serif
        case 4, 5: return .slabSerif
        case 8: return .sansSerif
        case 9: return .ornamental
        case 10: return .script
        case 12: return .symbol
        default: break
        }
        let name = name.lowercased()
        if name.contains("mono") || name.contains("code") { return .monospaced }
        if name.contains("slab") { return .slabSerif }
        if name.contains("sans") || name.contains("grotesk") || name.contains("grotesque") || name.contains("gothic") { return .sansSerif }
        if name.contains("serif") || name.contains("garamond") || name.contains("antiqua") { return .serif }
        if name.contains("script") || name.contains("brush") || name.contains("hand") { return .script }
        return .unclassified
    }

    var hasActiveFaces: Bool { faces.contains { $0.status.isActive } }
    var hasActivatableFaces: Bool { faces.contains(where: \.canActivate) }
    var hasDeactivatableFaces: Bool { faces.contains(where: \.canDeactivate) }
    var hasTemporaryFaces: Bool { faces.contains(where: \.isTemporary) }
    /// Every active style is on for this session only.
    var isTemporarilyActive: Bool { hasActiveFaces && faces.allSatisfy { !$0.status.isActive || $0.isTemporary } }

    /// Every file belonging to the family, active copy first.
    var revealURLs: [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for face in faces {
            for path in [face.face.path] + face.otherPaths where seen.insert(path).inserted {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    /// The face to preview at a given weight: a variable face if there is one, else the closest static weight.
    func face(nearestWeight weight: Int) -> LibraryFace {
        if weight == 400, let regular = faces.first(where: { $0.face.path == regularFace.path && $0.face.index == regularFace.index }) {
            return regular
        }
        return Self.nearest(weight, in: faces)
    }

    private static func nearest(_ weight: Int, in faces: [LibraryFace]) -> LibraryFace {
        var best: LibraryFace?
        var hasUpright = false
        for face in faces where !face.face.isItalic { hasUpright = true; break }
        for face in faces where !hasUpright || !face.face.isItalic {
            if face.face.weightAxis != nil { return face }
            if best == nil || abs(face.face.weightClass - weight) < abs(best!.face.weightClass - weight) { best = face }
        }
        return best ?? faces[0]
    }

    static func status(of faces: [LibraryFace]) -> FamilyStatus {
        let activeCount = faces.filter { $0.status.isActive }.count
        if activeCount == faces.count {
            return faces.allSatisfy { $0.status == .active(.system) } ? .system : .active
        }
        if activeCount > 0 { return .partial }
        var apps = Set<String>()
        for face in faces {
            guard case .appOnly(let app) = face.status else { return .inactive }
            apps.insert(app)
        }
        return apps.count == 1 ? .appOnly(apps.first!) : .inactive
    }
}

// MARK: - User data

struct WatchedFolder: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var path: String
    /// When set, fonts in this folder are treated as active inside that app (e.g. "Adobe") rather than inactive.
    var appOnlyName: String?

    static let deactivatedID = UUID(uuidString: "00000000-0000-0000-0000-0000000DEAD0")!

    var url: URL { URL(fileURLWithPath: path) }

    var displayName: String {
        if id == Self.deactivatedID { return "Deactivated" }
        let last = url.lastPathComponent
        if last.caseInsensitiveCompare("Fonts") == .orderedSame {
            return url.deletingLastPathComponent().lastPathComponent + " Fonts"
        }
        return last
    }

    /// Adobe apps load fonts from `Application Support/Adobe/Fonts` privately; nothing else sees them.
    static func detectAppOnlyName(forPath path: String) -> String? {
        let lower = path.lowercased()
        if lower.hasSuffix("/application support/adobe/fonts") || lower.contains("/application support/adobe/fonts/") {
            return "Adobe"
        }
        return nil
    }
}

/// A hand-picked group of families.
struct FontSet: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var familyNames: [String] = []
}

enum InstallMethod: String, Codable, CaseIterable, Sendable {
    case ask, copy, register

    var settingsLabel: String {
        switch self {
        case .ask: "Ask each time"
        case .copy: "Copy into ~/Library/Fonts"
        case .register: "Use the files where they are"
        }
    }
}

struct UserLibraryData: Codable, Sendable {
    var watchedFolders: [WatchedFolder] = []
    var sets: [FontSet] = []
    var smartSets: [SmartSet] = []
    var customCharacterSets: [CustomCharacterSet] = []
    /// Character sets listed in the sidebar. Unlike other rows they're opt-in, since there are many.
    var shownCharacterSets: Set<String> = CharacterSetCatalog.defaultShownIDs
    /// Tag names in sidebar order.
    var tags: [String] = []
    /// Family name → its tags.
    var familyTags: [String: [String]] = [:]
    /// Family name → foundry name, overriding the font's manufacturer metadata.
    var foundryOverrides: [String: String] = [:]
    /// Foundry name from metadata → display name.
    var foundryRenames: [String: String] = [:]
    var hiddenSidebarItems: Set<String> = []
    var collapsedSections: Set<String> = ["foundries", "classifications"]
    var installMethod: InstallMethod = .ask
    /// Installed copy in ~/Library/Fonts → the file it was copied from.
    var installedCopies: [String: String] = [:]
    var registeredPaths: Set<String> = []
    /// File path → its session-only registration (see TemporaryActivation).
    var temporaryActivations: [String: TemporaryActivation] = [:]
    var showSystemFonts = true

    init() {}

    /// Keys from earlier versions, which had Collections and hand-assigned Styles instead of Sets and Tags.
    private enum LegacyKeys: String, CodingKey {
        case collections, styles, styleAssignments
    }

    private struct LegacyStyle: Decodable {
        var id: String
        var name: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let d = UserLibraryData()
        watchedFolders = try c.decodeIfPresent([WatchedFolder].self, forKey: .watchedFolders) ?? d.watchedFolders
        sets = try c.decodeIfPresent([FontSet].self, forKey: .sets)
            ?? legacy.decodeIfPresent([FontSet].self, forKey: .collections) ?? d.sets
        smartSets = try c.decodeIfPresent([SmartSet].self, forKey: .smartSets) ?? d.smartSets
        customCharacterSets = try c.decodeIfPresent([CustomCharacterSet].self, forKey: .customCharacterSets) ?? d.customCharacterSets
        shownCharacterSets = try c.decodeIfPresent(Set<String>.self, forKey: .shownCharacterSets) ?? d.shownCharacterSets
        foundryOverrides = try c.decodeIfPresent([String: String].self, forKey: .foundryOverrides) ?? d.foundryOverrides
        foundryRenames = try c.decodeIfPresent([String: String].self, forKey: .foundryRenames) ?? d.foundryRenames
        hiddenSidebarItems = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenSidebarItems) ?? d.hiddenSidebarItems
        collapsedSections = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedSections) ?? d.collapsedSections
        installMethod = try c.decodeIfPresent(InstallMethod.self, forKey: .installMethod) ?? d.installMethod
        installedCopies = try c.decodeIfPresent([String: String].self, forKey: .installedCopies) ?? d.installedCopies
        registeredPaths = try c.decodeIfPresent(Set<String>.self, forKey: .registeredPaths) ?? d.registeredPaths
        temporaryActivations = try c.decodeIfPresent([String: TemporaryActivation].self, forKey: .temporaryActivations) ?? d.temporaryActivations
        showSystemFonts = try c.decodeIfPresent(Bool.self, forKey: .showSystemFonts) ?? d.showSystemFonts

        if let tags = try c.decodeIfPresent([String].self, forKey: .tags) {
            self.tags = tags
            familyTags = try c.decodeIfPresent([String: [String]].self, forKey: .familyTags) ?? [:]
        } else if let assignments = try legacy.decodeIfPresent([String: String].self, forKey: .styleAssignments) {
            // Each old style becomes a tag of the same name.
            let styles = try legacy.decodeIfPresent([LegacyStyle].self, forKey: .styles) ?? []
            let names = Dictionary(styles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            for (family, styleID) in assignments where !styleID.isEmpty {
                familyTags[family] = [names[styleID] ?? styleID]
            }
            let used = Set(familyTags.values.joined())
            tags = styles.map(\.name).filter(used.contains) + used.subtracting(styles.map(\.name)).sorted()
            let tagForStyle = names
            hiddenSidebarItems = Set(hiddenSidebarItems.map { key in
                if key == "section.styles" { return "section.tags" }
                if key == "section.collections" { return "section.sets" }
                if key.hasPrefix("collection.") { return "set." + key.dropFirst("collection.".count) }
                if key.hasPrefix("style.") { return "tag." + (tagForStyle[String(key.dropFirst("style.".count))] ?? "") }
                return key
            })
            collapsedSections = Set(collapsedSections.map { $0 == "styles" ? "tags" : $0 == "collections" ? "sets" : $0 })
        }
    }
}

enum Persistence {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Point", isDirectory: true)
    }

    static var deactivatedDirectory: URL { supportDirectory.appendingPathComponent("Deactivated", isDirectory: true) }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Point", isDirectory: true)
    }

    private static var libraryFile: URL { supportDirectory.appendingPathComponent("library.json") }

    static func load() -> UserLibraryData? {
        guard let data = try? Data(contentsOf: libraryFile) else { return nil }
        return try? JSONDecoder().decode(UserLibraryData.self, from: data)
    }

    static func save(_ library: UserLibraryData) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(library).write(to: libraryFile, options: .atomic)
        } catch {
            NSLog("Point: failed to save library: \(error)")
        }
    }
}

extension FontMetadata {
    /// The format named by a file extension; reads no file.
    static func format(ofExtension ext: String) -> String {
        switch ext.lowercased() {
        case "otf": "OpenType PostScript"
        case "ttf": "OpenType TrueType"
        case "ttc", "otc": "Font Collection"
        case "dfont": "Datafork TrueType"
        case "woff", "woff2": "Web Font"
        default: ext.uppercased()
        }
    }
}
