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
    var url: URL { URL(fileURLWithPath: path) }
}

/// Where an active face is activated from. Decides whether Point may deactivate it.
enum ActiveKind: Sendable {
    case system        // ships with macOS: /System/Library/Fonts and Apple's downloadable fonts
    case allUsers      // /Library/Fonts, installed for every user (needs an admin to change)
    case application   // shipped inside an app bundle
    case adobeCloud    // Adobe Fonts synced by Creative Cloud
    case user          // ~/Library/Fonts
    case registered    // registered in place by Point
    case other         // registered by another app

    var isUserControllable: Bool {
        switch self {
        case .user, .registered, .other: true
        case .system, .allUsers, .application, .adobeCloud: false
        }
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

    var id: String { face.id }
    var canActivate: Bool { !status.isActive }
    var canDeactivate: Bool { status.activeKind?.isUserControllable ?? false }
}

struct FontFamily: Identifiable, Hashable, Sendable {
    var name: String
    var faces: [LibraryFace]
    var status: FamilyStatus
    var folderIDs: Set<UUID>
    var manufacturer: String?

    var id: String { name }

    var stylesLabel: String { faces.count == 1 ? "1 style" : "\(faces.count) styles" }
    var hasActiveFaces: Bool { faces.contains { $0.status.isActive } }
    var hasActivatableFaces: Bool { faces.contains(where: \.canActivate) }
    var hasDeactivatableFaces: Bool { faces.contains(where: \.canDeactivate) }

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
        let upright = faces.filter { !$0.face.isItalic }
        let pool = upright.isEmpty ? faces : upright
        if let variable = pool.first(where: { $0.face.weightAxis != nil }) {
            return variable
        }
        return pool.min { abs($0.face.weightClass - weight) < abs($1.face.weightClass - weight) } ?? faces[0]
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

struct StyleCategory: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var isBuiltIn: Bool

    static let defaults: [StyleCategory] = [
        .init(id: "serif", name: "Serif", isBuiltIn: true),
        .init(id: "sans", name: "Sans-Serif", isBuiltIn: true),
        .init(id: "display", name: "Display", isBuiltIn: true),
        .init(id: "mono", name: "Mono", isBuiltIn: true),
        .init(id: "script", name: "Script", isBuiltIn: true),
        .init(id: "decorative", name: "Decorative", isBuiltIn: true),
    ]

    var icon: String {
        switch id {
        case "serif": "textformat"
        case "sans": "textformat.alt"
        case "display": "textformat.size.larger"
        case "mono": "chevron.left.forwardslash.chevron.right"
        case "script": "scribble.variable"
        case "decorative": "paintbrush.pointed"
        default: "tag"
        }
    }
}

struct FontCollection: Codable, Hashable, Identifiable, Sendable {
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
    var styles: [StyleCategory] = StyleCategory.defaults
    /// Family name → style id. An empty string means "explicitly unclassified".
    var styleAssignments: [String: String] = [:]
    var collections: [FontCollection] = []
    /// Family name → foundry name, overriding the font's manufacturer metadata.
    var foundryOverrides: [String: String] = [:]
    /// Foundry name from metadata → display name.
    var foundryRenames: [String: String] = [:]
    var hiddenSidebarItems: Set<String> = []
    var collapsedSections: Set<String> = ["foundries"]
    var installMethod: InstallMethod = .ask
    /// Installed copy in ~/Library/Fonts → the file it was copied from.
    var installedCopies: [String: String] = [:]
    var registeredPaths: Set<String> = []
    var showSystemFonts = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserLibraryData()
        watchedFolders = try c.decodeIfPresent([WatchedFolder].self, forKey: .watchedFolders) ?? d.watchedFolders
        styles = try c.decodeIfPresent([StyleCategory].self, forKey: .styles) ?? d.styles
        styleAssignments = try c.decodeIfPresent([String: String].self, forKey: .styleAssignments) ?? d.styleAssignments
        collections = try c.decodeIfPresent([FontCollection].self, forKey: .collections) ?? d.collections
        foundryOverrides = try c.decodeIfPresent([String: String].self, forKey: .foundryOverrides) ?? d.foundryOverrides
        foundryRenames = try c.decodeIfPresent([String: String].self, forKey: .foundryRenames) ?? d.foundryRenames
        hiddenSidebarItems = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenSidebarItems) ?? d.hiddenSidebarItems
        collapsedSections = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedSections) ?? d.collapsedSections
        installMethod = try c.decodeIfPresent(InstallMethod.self, forKey: .installMethod) ?? d.installMethod
        installedCopies = try c.decodeIfPresent([String: String].self, forKey: .installedCopies) ?? d.installedCopies
        registeredPaths = try c.decodeIfPresent(Set<String>.self, forKey: .registeredPaths) ?? d.registeredPaths
        showSystemFonts = try c.decodeIfPresent(Bool.self, forKey: .showSystemFonts) ?? d.showSystemFonts
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
