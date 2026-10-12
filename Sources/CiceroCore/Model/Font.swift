import Foundation

/// A face inside a font file: the file's path and the face's position in it (collections hold several).
public struct FaceID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let path: String
    public let index: Int

    public init(path: String, index: Int) {
        self.path = path
        self.index = index
    }

    public var description: String { "\(path)#\(index)" }

    public static func < (a: FaceID, b: FaceID) -> Bool { (a.path, a.index) < (b.path, b.index) }
}

/// The range of a variable font's weight axis.
public struct WeightAxis: Hashable, Codable, Sendable {
    public var minimum: Double
    public var maximum: Double
    public var defaultValue: Double

    public init(minimum: Double, maximum: Double, defaultValue: Double) {
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
    }
}

/// What a font file says about one of its faces. Read once and cached by file stamp.
public struct FontFace: Hashable, Codable, Sendable, Identifiable {
    public let id: FaceID
    public var postScriptName: String
    public var familyName: String
    public var styleName: String
    public var fullName: String
    /// OS/2 weight class, 1…1000.
    public var weight: Int
    public var isItalic: Bool
    public var isMonospaced: Bool
    /// OS/2 family class (high byte of sFamilyClass); 0 when unknown.
    public var familyClass: Int
    public var manufacturer: String?
    public var version: String?
    public var weightAxis: WeightAxis?

    public init(
        id: FaceID, postScriptName: String, familyName: String, styleName: String, fullName: String,
        weight: Int, isItalic: Bool, isMonospaced: Bool, familyClass: Int,
        manufacturer: String?, version: String?, weightAxis: WeightAxis?
    ) {
        self.id = id
        self.postScriptName = postScriptName
        self.familyName = familyName
        self.styleName = styleName
        self.fullName = fullName
        self.weight = weight
        self.isItalic = isItalic
        self.isMonospaced = isMonospaced
        self.familyClass = familyClass
        self.manufacturer = manufacturer
        self.version = version
        self.weightAxis = weightAxis
    }

    public var path: String { id.path }
    public var url: URL { URL(fileURLWithPath: id.path, isDirectory: false) }

    /// "Version 1.001;FEAKit 1.0" → "1.001": the version string without its label or build notes.
    public static func displayVersion(_ version: String) -> String {
        var value = version.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasPrefix("version ") { value = String(value.dropFirst("version ".count)) }
        if let end = value.firstIndex(of: ";") { value = String(value[..<end]) }
        return value.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - State

public enum TemporaryScope: String, Codable, Sendable, CaseIterable {
    case untilQuit, untilLogout
}

/// Where an active face is activated from, which decides whether Cicero may turn it off.
public enum ActiveSource: Hashable, Sendable {
    /// Ships with macOS (/System/Library/Fonts, Apple's downloadable fonts).
    case macOS
    /// /Library/Fonts.
    case allUsers
    /// Inside an app bundle.
    case app
    /// Synced by Adobe Creative Cloud (CoreSync).
    case adobeFonts
    /// ~/Library/Fonts.
    case fontsFolder
    /// Registered where it is by Cicero.
    case inPlace
    /// Registered by Cicero for this session only.
    case temporary(TemporaryScope)
    /// Registered by some other app.
    case otherApp

    public var canDeactivate: Bool {
        switch self {
        case .fontsFolder, .inPlace, .temporary, .otherApp: true
        case .macOS, .allUsers, .app, .adobeFonts: false
        }
    }
}

public enum FaceState: Hashable, Sendable {
    case active(ActiveSource)
    case inactive
    /// Not active for the system, but loaded by one app from its own folder (e.g. "Adobe").
    case appOnly(String)

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    public var source: ActiveSource? {
        if case .active(let source) = self { return source }
        return nil
    }

    public var temporaryScope: TemporaryScope? {
        if case .active(.temporary(let scope)) = self { return scope }
        return nil
    }

    /// "Adobe apps" for Adobe's shared folders, else the app's name ("InDesign").
    public static func appDescription(_ app: String) -> String {
        app == "Adobe" ? "Adobe apps" : app
    }

    public var label: String {
        switch self {
        case .active(.macOS): "Installed with macOS"
        case .active(.allUsers): "Installed for all users"
        case .active(.app): "Comes with an app"
        case .active(.adobeFonts): "Adobe Fonts"
        case .active(.temporary(.untilQuit)): "Active until Cicero quits"
        case .active(.temporary(.untilLogout)): "Active until you log out"
        case .active: "Active"
        case .inactive: "Not activated"
        case .appOnly(let app): "Active in \(FaceState.appDescription(app))"
        }
    }
}

/// A face as it is in the library: its state, other files with the same PostScript name, and
/// when it arrived.
public struct LibraryFace: Identifiable, Hashable, Sendable {
    public let face: FontFace
    public let state: FaceState
    /// Other files containing the same PostScript name (e.g. the original of an installed copy).
    public let otherCopies: [String]
    public let dateAdded: Date?

    public init(face: FontFace, state: FaceState, otherCopies: [String] = [], dateAdded: Date? = nil) {
        self.face = face
        self.state = state
        self.otherCopies = otherCopies
        self.dateAdded = dateAdded
    }

    public var id: FaceID { face.id }
    public var canActivate: Bool { !state.isActive || state.temporaryScope != nil }
    public var canDeactivate: Bool { state.source?.canDeactivate ?? false }
}

public enum FamilyState: Hashable, Sendable {
    case active
    case partial
    case inactive
    case appOnly(String)
    /// Every face comes with macOS.
    case system
}

public enum Classification: String, CaseIterable, Codable, Sendable {
    case serif = "Serif"
    case slabSerif = "Slab Serif"
    case sansSerif = "Sans Serif"
    case monospaced = "Monospaced"
    case script = "Script"
    case ornamental = "Ornamental"
    case symbol = "Symbol"
    case unclassified = "Unclassified"
}

public enum FontFormat: String, CaseIterable, Codable, Sendable {
    case openTypePostScript = "OpenType PostScript"
    case openTypeTrueType = "OpenType TrueType"
    case collection = "Font Collection"
    case datafork = "Datafork TrueType"
    case web = "Web Font"
    case mixed = "Mixed"
    case other = "Other"

    public static func of(path: String) -> FontFormat {
        switch (path as NSString).pathExtension.lowercased() {
        case "otf": .openTypePostScript
        case "ttf": .openTypeTrueType
        case "ttc", "otc": .collection
        case "dfont": .datafork
        case "woff", "woff2": .web
        default: .other
        }
    }
}

/// A font family with everything lists, sorting and filters need worked out once, when the library
/// is built, so views never recompute it.
public struct Family: Identifiable, Hashable, Sendable {
    /// The family name.
    public let id: String
    /// Sorted by weight, then upright before italic, then style name.
    public let faces: [LibraryFace]
    public let state: FamilyState
    /// Watched folders (and Cicero's Deactivated folder) that contain the family.
    public let folderIDs: Set<UUID>
    /// The foundry the files name, tidied (no "Inc.", URLs or copyright lines). User renames are applied by the app.
    public let manufacturer: String?
    public let dateAdded: Date?
    public let classification: Classification
    public let format: FontFormat
    public let isVariable: Bool
    public let isMonospaced: Bool
    public let hasItalics: Bool
    /// The regular upright face, which stands for the family in previews and coverage.
    public let regular: LibraryFace
    public let activeCount: Int
    public let hasActive: Bool
    public let hasActivatable: Bool
    public let hasDeactivatable: Bool
    /// Set when every active face is temporarily active with this scope.
    public let temporaryScope: TemporaryScope?

    public var name: String { id }
    public var stylesLabel: String { faces.count == 1 ? "1 style" : "\(faces.count) styles" }

    public init(name: String, faces: [LibraryFace], state: FamilyState, folderIDs: Set<UUID>, manufacturer: String?) {
        precondition(!faces.isEmpty, "A family has at least one face")
        id = name
        self.faces = faces
        self.state = state
        self.folderIDs = folderIDs
        self.manufacturer = manufacturer
        dateAdded = faces.compactMap(\.dateAdded).min()
        isVariable = faces.contains { $0.face.weightAxis != nil }
        isMonospaced = faces.contains { $0.face.isMonospaced }
        hasItalics = faces.contains { $0.face.isItalic }
        let formats = Set(faces.map { FontFormat.of(path: $0.face.path) })
        format = formats.count == 1 ? formats.first! : .mixed
        classification = Classification.of(name: name, faces: faces)
        regular = Self.nearest(400, in: faces)
        activeCount = faces.count { $0.state.isActive }
        hasActive = activeCount > 0
        hasActivatable = faces.contains(where: \.canActivate)
        hasDeactivatable = faces.contains(where: \.canDeactivate)
        let scopes = Set(faces.filter(\.state.isActive).map(\.state.temporaryScope))
        temporaryScope = scopes.count == 1 ? scopes.first! : nil
    }

    /// The face to preview at a weight: a variable face when there is one, else the closest upright weight.
    public func face(nearestWeight weight: Double) -> LibraryFace {
        weight == 400 ? regular : Self.nearest(weight, in: faces)
    }

    private static func nearest(_ weight: Double, in faces: [LibraryFace]) -> LibraryFace {
        let hasUpright = faces.contains { !$0.face.isItalic }
        var best: LibraryFace?
        for candidate in faces where !hasUpright || !candidate.face.isItalic {
            if candidate.face.weightAxis != nil { return candidate }
            if best == nil || abs(Double(candidate.face.weight) - weight) < abs(Double(best!.face.weight) - weight) {
                best = candidate
            }
        }
        return best ?? faces[0]
    }
}

extension Classification {
    /// The OS/2 family class of the regular upright face, then hints in the name.
    static func of(name: String, faces: [LibraryFace]) -> Classification {
        if faces.contains(where: { $0.face.isMonospaced }) { return .monospaced }
        let upright = faces.first { !$0.face.isItalic } ?? faces[0]
        switch upright.face.familyClass {
        case 1, 2, 3, 7: return .serif
        case 4, 5: return .slabSerif
        case 8: return .sansSerif
        case 9: return .ornamental
        case 10: return .script
        case 12: return .symbol
        default: break
        }
        let name = name.lowercased()
        let hints: [(Classification, [String])] = [
            (.monospaced, ["mono", "code"]),
            (.slabSerif, ["slab"]),
            (.sansSerif, ["sans", "grotesk", "grotesque", "gothic"]),
            (.serif, ["serif", "garamond", "antiqua"]),
            (.script, ["script", "brush", "hand"]),
        ]
        for (classification, words) in hints where words.contains(where: name.contains) { return classification }
        return .unclassified
    }
}
