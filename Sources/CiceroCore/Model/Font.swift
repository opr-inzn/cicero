import Foundation

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

public struct VariationAxis: Hashable, Codable, Sendable {
    public var tag: String
    public var name: String
    public var value: Double

    public init(tag: String, name: String, value: Double) {
        self.tag = tag
        self.name = AxisTag.name(of: tag, given: name)
        self.value = value
    }
}

public struct AxisRange: Hashable, Sendable, Identifiable {
    public var tag: String
    public var name: String
    public var minimum: Double
    public var maximum: Double
    public var defaultValue: Double
    public var isHidden: Bool

    public var id: String { tag }

    public init(tag: String, name: String, minimum: Double, maximum: Double, defaultValue: Double, isHidden: Bool = false) {
        self.tag = tag
        self.name = name
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
        self.isHidden = isHidden
    }
}

public enum Embedding: String, CaseIterable, Codable, Sendable {
    case installable
    case editable
    case previewAndPrint
    case restricted

    public var title: String {
        switch self {
        case .installable: "Installable"
        case .editable: "Editable"
        case .previewAndPrint: "Preview & Print"
        case .restricted: "Restricted"
        }
    }

    public var rank: Int { Self.allCases.firstIndex(of: self)! }

    public init(fsType: UInt16) {
        // Files from before version 3 of the OS/2 table can set more than one; the least restrictive applies.
        self = fsType & 0x0008 != 0 ? .editable
            : fsType & 0x0004 != 0 ? .previewAndPrint
            : fsType & 0x0002 != 0 ? .restricted
            : .installable
    }
}

// Saved by their place in this list, so new ones go at its end.
public enum OpenTypeFeature: String, CaseIterable, Sendable {
    case smallCaps = "smcp", capitalsToSmallCaps = "c2sc", petiteCaps = "pcap"
    case oldStyleFigures = "onum", liningFigures = "lnum", tabularFigures = "tnum", proportionalFigures = "pnum"
    case fractions = "frac", superscript = "sups", `subscript` = "subs", ordinals = "ordn", slashedZero = "zero"
    case caseSensitiveForms = "case", standardLigatures = "liga", discretionaryLigatures = "dlig"
    case contextualAlternates = "calt", stylisticAlternates = "salt"
    case stylisticSets = "ss"
    case characterVariants = "cv"
    case swashes = "swsh"
    case titling = "titl", historicalForms = "hist", localizedForms = "locl"

    public var title: String {
        switch self {
        case .smallCaps: "Small Capitals"
        case .capitalsToSmallCaps: "Capitals to Small Capitals"
        case .petiteCaps: "Petite Capitals"
        case .oldStyleFigures: "Old-Style Figures"
        case .liningFigures: "Lining Figures"
        case .tabularFigures: "Tabular Figures"
        case .proportionalFigures: "Proportional Figures"
        case .fractions: "Fractions"
        case .superscript: "Superscript"
        case .subscript: "Subscript"
        case .ordinals: "Ordinals"
        case .slashedZero: "Slashed Zero"
        case .caseSensitiveForms: "Case-Sensitive Forms"
        case .standardLigatures: "Standard Ligatures"
        case .discretionaryLigatures: "Discretionary Ligatures"
        case .contextualAlternates: "Contextual Alternates"
        case .stylisticAlternates: "Stylistic Alternates"
        case .stylisticSets: "Stylistic Sets"
        case .characterVariants: "Character Variants"
        case .swashes: "Swashes"
        case .titling: "Titling Alternates"
        case .historicalForms: "Historical Forms"
        case .localizedForms: "Localized Forms"
        }
    }

    public init?(tag: String) {
        guard tag.count == 4 else { return nil }
        if tag == "cswh" {
            self = .swashes
        } else if let number = Int(tag.dropFirst(2)), tag.hasPrefix("ss") || tag.hasPrefix("cv") {
            guard (1...(tag.hasPrefix("ss") ? 20 : 99)).contains(number) else { return nil }
            self = tag.hasPrefix("ss") ? .stylisticSets : .characterVariants
        } else if let feature = Self(rawValue: tag) {
            self = feature
        } else {
            return nil
        }
    }
}

public struct OpenTypeFeatures: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ feature: OpenTypeFeature) {
        rawValue = 1 << UInt64(OpenTypeFeature.allCases.firstIndex(of: feature)!)
    }

    public init(tags: some Sequence<String>) {
        self = tags.reduce(into: []) { features, tag in
            if let feature = OpenTypeFeature(tag: tag) { features.insert(Self(feature)) }
        }
    }

    public func contains(_ feature: OpenTypeFeature) -> Bool {
        contains(Self(feature))
    }
}

public struct Figures: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let tabular = Figures(rawValue: 1)
    public static let oldStyle = Figures(rawValue: 2)
}

public struct FontFace: Hashable, Codable, Sendable, Identifiable {
    public let id: FaceID
    public var postScriptName: String
    public var familyName: String
    public var styleName: String
    public var fullName: String
    public var weight: Int
    public var isItalic: Bool
    public var isMonospaced: Bool
    public var familyClass: Int
    public var panose: Classification?
    public var letterShape: Classification?
    public var manufacturer: String?
    public var version: String?
    public var designer: String?
    public var vendorID: String?
    public var weightAxis: WeightAxis?
    public var width: Int
    public var axes: [VariationAxis]
    public var isAtOrigin: Bool
    public var year: Int?
    public var embedding: Embedding?
    public var features: OpenTypeFeatures
    public var figures: Figures
    public var localizedFamilyNames: [String: String]

    public init(
        id: FaceID, postScriptName: String, familyName: String, styleName: String, fullName: String,
        weight: Int, isItalic: Bool, isMonospaced: Bool, familyClass: Int, panose: Classification? = nil, letterShape: Classification? = nil,
        manufacturer: String?, version: String?, designer: String? = nil, vendorID: String? = nil,
        weightAxis: WeightAxis?, width: Int = 5, axes: [VariationAxis] = [], isAtOrigin: Bool = false, year: Int? = nil,
        embedding: Embedding? = nil, features: OpenTypeFeatures = [], figures: Figures = [], localizedFamilyNames: [String: String] = [:]
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
        self.panose = panose
        self.letterShape = letterShape
        self.manufacturer = manufacturer
        self.version = version
        self.designer = designer
        self.vendorID = vendorID
        self.weightAxis = weightAxis
        self.width = width
        self.axes = axes
        self.isAtOrigin = isAtOrigin
        self.year = year
        self.embedding = embedding
        self.features = features
        self.figures = figures
        self.localizedFamilyNames = localizedFamilyNames
    }

    public var isOrnaments: Bool {
        let name = styleName.lowercased()
        return familyClass == 12 || name.contains("ornament") || name.contains("dingbat")
    }

    public var displayFamilyName: String {
        LocalizedNames.name(in: localizedFamilyNames) ?? familyName
    }

    public var styleWeight: Double {
        axes.first { $0.tag == "wght" }?.value ?? Double(weight)
    }

    public var styleWidth: Double {
        if let value = axes.first(where: { $0.tag == "wdth" })?.value { return value }
        return [50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200][min(max(width, 1), 9) - 1]
    }

    public func styleValue(on tag: String) -> Double? {
        tag == "wdth" ? styleWidth : axes.first { $0.tag == tag }?.value
    }

    public var path: String { id.path }
    public var url: URL { URL(fileURLWithPath: id.path, isDirectory: false) }

    public static func displayVersion(_ version: String) -> String {
        var value = version.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasPrefix("version ") { value = String(value.dropFirst("version ".count)) }
        if let end = value.firstIndex(of: ";") { value = String(value[..<end]) }
        return value.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - State

public enum TemporaryScope: String, Codable, Sendable, CaseIterable {
    case untilQuit
    case whileAppsRun

    public init(from decoder: Decoder) throws {
        // A scope a later version adds ends when Cicero quits here, rather than a file that doesn't load.
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .untilQuit
    }
}

public enum ActiveSource: Hashable, Sendable {
    case macOS
    case allUsers
    case app
    case adobeFonts
    case fontsFolder
    case inPlace
    case temporary(TemporaryScope)
    case otherApp

    public var canDeactivate: Bool {
        switch self {
        case .fontsFolder, .inPlace, .temporary, .otherApp: true
        case .macOS, .allUsers, .app, .adobeFonts: false
        }
    }

    public static func isAdobeFonts(_ path: String) -> Bool {
        path.utf8.withContiguousStorageIfAvailable { bytes in
            coreSyncMarker.withUnsafeBufferPointer { marker in
                memmem(bytes.baseAddress, bytes.count, marker.baseAddress, marker.count) != nil
            }
        } ?? path.contains("/Adobe/CoreSync/")
    }

    private static let coreSyncMarker = Array("/Adobe/CoreSync/".utf8)
}

public enum FaceState: Hashable, Sendable {
    case active(ActiveSource)
    case inactive
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
        case .active(.temporary(.whileAppsRun)): "Active while its app is open"
        case .active: "Active"
        case .inactive: "Inactive"
        case .appOnly(let app): "Active in \(FaceState.appDescription(app))"
        }
    }
}

public struct LibraryFace: Identifiable, Hashable, Sendable {
    public let face: FontFace
    public let state: FaceState
    public let otherCopies: [String]
    public let copies: [FaceCopy]
    public let dateAdded: Date?
    public let app: String?
    public let isAdobeFonts: Bool

    public init(face: FontFace, state: FaceState, otherCopies: [String] = [], copies: [FaceCopy] = [], dateAdded: Date? = nil, app: String? = nil) {
        self.face = face
        self.state = state
        self.otherCopies = copies.isEmpty ? otherCopies : copies.map(\.face.path)
        self.copies = copies
        self.dateAdded = dateAdded
        self.app = app
        isAdobeFonts = ActiveSource.isAdobeFonts(face.path)
    }

    public var id: FaceID { face.id }
    public var canActivate: Bool { !isAdobeFonts && (!state.isActive || state.temporaryScope != nil) }
    public var canActivateTemporarily: Bool { !isAdobeFonts && (!state.isActive || state.temporaryScope == .whileAppsRun) }
    public var canDeactivate: Bool {
        if case .appOnly = state { return !isAdobeFonts }
        return state.source?.canDeactivate ?? false
    }

    public var position: SwitchPosition {
        if state.isActive { return .on }
        return app != nil && state != .inactive ? .app : .off
    }
}

public enum SwitchPosition: Sendable {
    case off, app, on

    init(_ positions: some Sequence<SwitchPosition>) {
        let all = Set(positions)
        self = all == [.on] ? .on : all.isEmpty || all == [.off] ? .off : .app
    }
}

public enum FamilyState: Hashable, Sendable {
    case active
    case partial
    case inactive
    case appOnly(String)
    case system
}

public enum Classification: String, CaseIterable, Codable, Sendable {
    case serif = "Serif"
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
    case mixed = "Mixed"
    case other = "Other"

    public static let fileExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "dfont"]

    public static func isFontFile(_ path: String) -> Bool {
        fileExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    public static func of(path: String) -> FontFormat {
        switch (path as NSString).pathExtension.lowercased() {
        case "otf": .openTypePostScript
        case "ttf": .openTypeTrueType
        case "ttc", "otc": .collection
        case "dfont": .datafork
        default: .other
        }
    }
}

public struct Family: Identifiable, Hashable, Sendable {
    private let storage: Storage

    private final class Storage: Sendable {
        let fields: Fields
        init(_ fields: Fields) { self.fields = fields }
    }

    private struct Fields: Hashable, Sendable {
        let id: String
        let name: String
        let faces: [LibraryFace]
        let state: FamilyState
        let folderIDs: Set<UUID>
        let manufacturer: String?
        let dateAdded: Date?
        let classification: Classification
        let mixesSerifAndSans: Bool
        let format: FontFormat
        let isVariable: Bool
        let isMonospaced: Bool
        let hasItalics: Bool
        let rangeLabel: String
        let app: String?
        let isAdobeFonts: Bool
        let position: SwitchPosition
        let regular: LibraryFace
        let picks: [StylePick]
        let activeCount: Int
        let hasActive: Bool
        let hasActivatable: Bool
        let hasTemporarilyActivatable: Bool
        let hasDeactivatable: Bool
        let temporaryScope: TemporaryScope?

        init(name: String, faces: [LibraryFace], state: FamilyState, folderIDs: Set<UUID>, manufacturer: String?) {
            precondition(!faces.isEmpty, "A family has at least one face")
            id = name
            let picks = faces.map { StylePick($0.face) }
            let regular = Family.nearest(400, in: faces, picks: picks)
            self.name = LocalizedNames.name(in: regular.face.localizedFamilyNames)
                ?? faces.lazy.compactMap { LocalizedNames.name(in: $0.face.localizedFamilyNames) }.first ?? name
            self.faces = faces
            self.state = state
            self.folderIDs = folderIDs
            self.manufacturer = manufacturer
            dateAdded = faces.compactMap(\.dateAdded).min()
            isVariable = faces.contains { !$0.face.axes.isEmpty }
            isMonospaced = faces.contains { $0.face.isMonospaced }
            hasItalics = faces.contains { $0.face.isItalic }
            rangeLabel = Family.rangeLabel(of: faces.map(\.face))
            let apps = Set(faces.map(\.app))
            app = apps.count == 1 ? apps.first! : nil
            isAdobeFonts = faces.allSatisfy(\.isAdobeFonts)
            position = app == nil ? (faces.contains { $0.state.isActive } ? .on : .off) : SwitchPosition(faces.map(\.position))
            let formats = Set(faces.map { FontFormat.of(path: $0.face.path) })
            format = formats.count == 1 ? formats.first! : .mixed
            classification = Classification.of(name: name, faces: faces)
            mixesSerifAndSans = Set(Classification.judged(faces).compactMap(\.letterShape)).isSuperset(of: [.serif, .sansSerif])
            self.regular = regular
            self.picks = picks
            activeCount = faces.count { $0.state.isActive }
            hasActive = activeCount > 0
            hasActivatable = faces.contains(where: \.canActivate)
            hasTemporarilyActivatable = faces.contains(where: \.canActivateTemporarily)
            hasDeactivatable = faces.contains(where: \.canDeactivate)
            let scopes = Set(faces.filter(\.state.isActive).map(\.state.temporaryScope))
            temporaryScope = scopes.count == 1 ? scopes.first! : nil
        }
    }

    public var id: String { storage.fields.id }
    public var name: String { storage.fields.name }
    public var faces: [LibraryFace] { storage.fields.faces }
    public var state: FamilyState { storage.fields.state }
    public var folderIDs: Set<UUID> { storage.fields.folderIDs }
    public var manufacturer: String? { storage.fields.manufacturer }
    public var dateAdded: Date? { storage.fields.dateAdded }
    public var classification: Classification { storage.fields.classification }
    public var mixesSerifAndSans: Bool { storage.fields.mixesSerifAndSans }
    public var format: FontFormat { storage.fields.format }
    public var isVariable: Bool { storage.fields.isVariable }
    public var isMonospaced: Bool { storage.fields.isMonospaced }
    public var hasItalics: Bool { storage.fields.hasItalics }
    public var rangeLabel: String { storage.fields.rangeLabel }
    public var app: String? { storage.fields.app }
    public var isAdobeFonts: Bool { storage.fields.isAdobeFonts }
    public var position: SwitchPosition { storage.fields.position }
    public var regular: LibraryFace { storage.fields.regular }
    public var activeCount: Int { storage.fields.activeCount }
    public var hasActive: Bool { storage.fields.hasActive }
    public var hasActivatable: Bool { storage.fields.hasActivatable }
    public var hasTemporarilyActivatable: Bool { storage.fields.hasTemporarilyActivatable }
    public var hasDeactivatable: Bool { storage.fields.hasDeactivatable }
    public var temporaryScope: TemporaryScope? { storage.fields.temporaryScope }
    public var fileKinds: String {
        Set(faces.map { ($0.face.path as NSString).pathExtension.uppercased() }).sorted().joined(separator: " · ")
    }

    public static func == (a: Family, b: Family) -> Bool {
        a.storage === b.storage || a.storage.fields == b.storage.fields
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(storage.fields) }

    public var stylesLabel: String { faces.count == 1 ? "1 Style" : "\(faces.count) Styles" }
    public var styleAxes: [(tag: String, name: String)] {
        var names = ["wdth": "Width"]
        var tags: [String] = []
        for axis in faces.lazy.flatMap(\.face.axes) where !tags.contains(axis.tag) {
            tags.append(axis.tag)
            names[axis.tag] = axis.name
        }
        let designers = tags.filter { $0.first?.isUppercase == true }
        let registered = tags.filter { $0.first?.isUppercase != true && !["wght", "wdth", "ital", "slnt"].contains($0) }
        return (designers + ["wdth"] + registered)
            .filter { tag in Set(faces.map { $0.face.styleValue(on: tag) }).count > 1 }
            .map { (tag: $0, name: names[$0] ?? $0) }
    }
    public var stylesDifferInWeight: Bool { Set(faces.map { Int($0.face.styleWeight.rounded()) }).count > 1 }
    public var year: Int? { faces.lazy.compactMap(\.face.year).min() }
    public var lastAdded: Date? {
        faces.lazy.filter { $0.state.source != .macOS && $0.state.source != .app }.compactMap(\.dateAdded).max()
    }

    public static func latestFirst(_ families: [Family]) -> [Family] {
        let times = families.map { $0.lastAdded ?? .distantPast }
        let arrival = times.indices.sorted { times[$0] < times[$1] }
        var batch = Array(repeating: 0, count: times.count)
        for (previous, index) in zip(arrival, arrival.dropFirst()) {
            batch[index] = batch[previous] + (times[index].timeIntervalSince(times[previous]) < 600 ? 0 : 1)
        }
        return families.indices.sorted { batch[$0] != batch[$1] ? batch[$0] > batch[$1] : $0 < $1 }.map { families[$0] }
    }
    public var embedding: Embedding? { faces.lazy.compactMap(\.face.embedding).max { $0.rank < $1.rank } }
    public var features: OpenTypeFeatures { faces.reduce([]) { $0.union($1.face.features) } }

    public init(name: String, faces: [LibraryFace], state: FamilyState, folderIDs: Set<UUID>, manufacturer: String?) {
        storage = Storage(Fields(name: name, faces: faces, state: state, folderIDs: folderIDs, manufacturer: manufacturer))
    }

    public func position(overriding faces: [FaceID: SwitchPosition]) -> SwitchPosition {
        let positions = self.faces.map { faces[$0.id] ?? $0.position }
        return app == nil ? (positions.contains(.on) ? .on : .off) : SwitchPosition(positions)
    }

    public func face(nearestWeight weight: Double) -> LibraryFace {
        weight == 400 || regular.face.weightAxis != nil ? regular : Self.nearest(weight, in: faces, picks: storage.fields.picks)
    }

    private static func nearest(_ weight: Double, in faces: [LibraryFace], picks: [StylePick]) -> LibraryFace {
        // Not a style of ornaments, which ties with the Regular in Hoefler Text, unless that's all there is.
        let letters = faces.indices.filter { !faces[$0].face.isOrnaments }
        let candidates = letters.isEmpty ? Array(faces.indices) : letters
        let hasUpright = candidates.contains { !faces[$0].face.isItalic }
        var best: Int?
        var variable: LibraryFace?
        // A variable font without a weight axis has all its instances at one weight: the one at its origin, rather than the first one listed, which can be at the end of every axis.
        func rank(_ index: Int) -> (Int, Int, Int, Int, Double, Double) {
            let pick = picks[index], face = faces[index].face, distance = abs(pick.weight - weight)
            return (pick.isCompanion ? 1 : 0, Int(distance / 100), pick.weightIsNamed ? 0 : 1, (face.isAtOrigin ? 0 : 10) + abs(pick.width - 5),
                    distance, abs(Double(face.weight) - weight))
        }
        for index in candidates where !hasUpright || !faces[index].face.isItalic {
            let candidate = faces[index]
            if candidate.face.weightAxis != nil {
                // The instance at the font's origin, the regular weight of those there, rather than the first one, which in SF Pro is Compressed.
                guard let found = variable else { variable = candidate; continue }
                if candidate.face.isAtOrigin && (!found.face.isAtOrigin
                    || abs(candidate.face.styleWeight - 400) < abs(found.face.styleWeight - 400)) {
                    variable = candidate
                }
            } else if best.map({ rank(index) < rank($0) }) ?? true {
                best = index
            }
        }
        return variable ?? best.map { faces[$0] } ?? faces[0]
    }

    static func rangeLabel(of faces: [FontFace]) -> String {
        let styleNames = faces.map { StyleName($0.styleName) }
        func value(_ face: FontFace, _ tag: String) -> Double? { face.axes.first { $0.tag == tag }?.value }
        // Names come first: a variable font may nudge an instance off the round value, as Skia's Black Condensed is lighter than its Black.
        let rawWeights = faces.map { value($0, "wght") ?? Double($0.weight) }
        var namedByRaw: [Double: [Double]] = [:]
        for (name, raw) in zip(styleNames, rawWeights) {
            if let weight = name.weight { namedByRaw[raw, default: []].append(Double(weight)) }
        }
        let weights: [Double] = zip(styleNames, rawWeights).map { name, raw in
            if let weight = name.weight { return Double(weight) }
            if let named = namedByRaw[raw]?.min(by: { abs($0 - raw) < abs($1 - raw) }) { return named }
            return name.isRegular ? 400 : raw
        }
        // A width class other than normal was set on purpose, while normal is often just left.
        let widthGroups = Self.groups(zip(faces, styleNames).map { face, name in
            if let raw = value(face, "wdth") { return (raw, name.widthWords.isEmpty ? nil : name.widthWords) }
            return (Double(face.width == 5 ? name.width ?? 5 : face.width), nil)
        })
        var parts: [String] = []
        let weightCount = Set(weights).count, widthCount = Set(widthGroups).count
        if weightCount > 1 { parts.append("\(weightCount) Weights") }
        if widthCount > 1 { parts.append("\(widthCount) Widths") }
        let told = Set(faces.indices.map { [weights[$0], Double(widthGroups[$0])] })
        if told.count < faces.count || parts.isEmpty { parts.append(faces.count == 1 ? "1 Style" : "\(faces.count) Styles") }
        return parts.joined(separator: " · ")
    }

    private static func groups<Word: Hashable>(_ keys: [(place: Double, word: Word?)]) -> [Int] {
        var parent = Array(keys.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        var byPlace: [Double: Int] = [:]
        var byWord: [Word: Int] = [:]
        for (index, key) in keys.enumerated() {
            if let other = byPlace[key.place] { parent[root(index)] = root(other) } else { byPlace[key.place] = index }
            guard let word = key.word else { continue }
            if let other = byWord[word] { parent[root(index)] = root(other) } else { byWord[word] = index }
        }
        return keys.indices.map(root)
    }
}

struct StylePick: Hashable, Sendable {
    var weight: Double
    var weightIsNamed: Bool
    var width: Int
    var isCompanion: Bool

    // Older families give every font of a group of four the style name Regular, so the PostScript name's style part goes first: a Bold styled Regular, a Thin whose PostScript name is SansThin-Regular.
    init(_ face: FontFace) {
        let postScript = Self.postScriptStyle(of: face)
        let names = [postScript.map(StyleName.init), StyleName(face.styleName)].compactMap { $0 }
        var weights = names.compactMap(\.weight)
        if let own = postScript.map(StyleName.init), own.weight == nil, own.hasOther { weights.removeAll { $0 == 400 } }
        let named = weights.first { $0 != 400 } ?? weights.first
        weight = Double(named ?? face.weight)
        weightIsNamed = named != nil
        width = names.lazy.compactMap(\.width).first ?? face.width
        let words = [face.styleName, postScript ?? ""].flatMap { name in
            StyleName.spaced(name).lowercased().split { !$0.isLetter }.map(String.init)
        }
        isCompanion = !Self.companionWords.isDisjoint(with: words) || !face.isItalic && names.contains(where: \.hasSlope)
    }

    // Lig is also short for Light, so ligatures only in full.
    private static let companionWords: Set<String> = [
        "sc", "caps", "smallcaps", "expert", "exp", "alt", "alts", "alternate", "alternates", "alternative", "swash",
        "swashes", "ligatures", "ornaments", "orn", "pi", "euro", "fractions", "initials", "dingbats", "symbols",
        "outline", "inline", "shadow", "shaded", "stencil", "hollow",
    ]

    private static func postScriptStyle(of face: FontFace) -> String? {
        guard let hyphen = face.postScriptName.firstIndex(of: "-") else { return nil }
        let style = face.postScriptName[face.postScriptName.index(after: hyphen)...]
        return style.isEmpty ? nil : String(style)
    }
}

// Many files give every style the same classes, Bold and Light at 400 or Extended at normal width, so the name tells styles apart more reliably.
struct StyleName {
    var weight: Int?
    var width: Int?
    var widthWords: [String] = []
    private(set) var hasSlope = false
    private(set) var hasOther = false
    // A word Cicero doesn't know may be a weight, like Buch in "Buch Kursiv".
    var isRegular: Bool { weight == nil && !hasOther && (width != nil || hasSlope) }

    init(_ name: String) {
        var run = ""
        for word in Self.words(name) {
            if word.allSatisfy({ $0 == "x" }) {
                run += word
                continue
            }
            let written = run + word
            run = ""
            if let value = Self.weights[written] ?? Self.weights[word] {
                if weight == nil { weight = value }
            } else if let value = Self.widths[written] ?? Self.widths[word] {
                if width == nil { width = value }
                widthWords.append(written)
            } else if Self.slopes.contains(word) {
                hasSlope = true
            } else {
                hasOther = true
            }
        }
        if !run.isEmpty { hasOther = true }
    }

    private static let slopes: Set<String> = ["italic", "it", "ital", "oblique", "obl", "slanted", "slant", "inclined", "kursiv", "backslant"]

    static func words(_ name: String) -> [String] {
        var words: [String] = []
        var word = ""
        for character in name {
            if !character.isLetter || character.isUppercase && word.last?.isLowercase == true {
                if !word.isEmpty { words.append(word.lowercased()) }
                word = ""
            }
            if character.isLetter { word.append(character) }
        }
        if !word.isEmpty { words.append(word.lowercased()) }
        var joined: [String] = []
        for word in words {
            if let last = joined.last, prefixes.contains(last), weights[last + word] != nil || widths[last + word] != nil {
                joined[joined.count - 1] = last + word
            } else {
                joined.append(word)
            }
        }
        return joined
    }

    private static let prefixes: Set<String> = ["extra", "ultra", "semi", "demi", "x", "xx", "u"]

    // Old-style figures' OsF stays one word: "RegularSCOsF" is Regular SC Osf.
    static func spaced(_ name: String) -> String {
        let characters = Array(name.replacingOccurrences(of: "OsF", with: "Osf"))
        var spaced = ""
        for (index, character) in characters.enumerated() {
            if index > 0, character.isUppercase {
                let previous = characters[index - 1], next = index + 1 < characters.count ? characters[index + 1] : nil
                if previous.isLowercase || previous.isUppercase && next?.isLowercase == true { spaced.append(" ") }
            }
            spaced.append(character)
        }
        return spaced
    }

    static let weights: [String: Int] = [
        "hairline": 50, "extrathin": 70, "xthin": 70, "ultrathin": 80, "lazer": 85, "lz": 85, "thin": 100, "th": 100,
        "ultralight": 190, "ult": 190, "extralight": 200, "xlight": 200, "xlt": 200,
        "light": 300, "lt": 300, "semilight": 340, "book": 350, "bk": 350,
        "regular": 400, "rg": 400, "reg": 400, "roman": 400, "normal": 400, "plain": 400,
        "medium": 500, "md": 500, "med": 500,
        "semibold": 600, "sbd": 600, "demibold": 610, "demi": 610,
        "bold": 700, "bd": 700,
        "extrabold": 800, "xbold": 800, "xbd": 800, "ultrabold": 810, "ubd": 810, "heavy": 850, "hv": 850,
        "black": 900, "bl": 900, "blk": 900, "extrablack": 950, "xblack": 950, "ultrablack": 960, "ultra": 960, "super": 1000,
    ]

    static let widths: [String: Int] = [
        "ultracondensed": 1, "ultracompressed": 1, "xxcondensed": 1, "xxcompressed": 1, "xcm": 1,
        "extracondensed": 2, "extracompressed": 2, "xcondensed": 2, "xcompressed": 2, "compressed": 2, "comp": 2, "cm": 2,
        "condensed": 3, "cond": 3, "cn": 3, "narrow": 3,
        "semicondensed": 4, "semicompressed": 4, "semicond": 4,
        "semiextended": 6, "semiexpanded": 6, "semiwide": 6,
        "extended": 7, "ext": 7, "expanded": 7, "exp": 7, "wide": 7,
        "extraextended": 8, "extraexpanded": 8, "extrawide": 8, "xextended": 8, "xexpanded": 8, "xwide": 8, "xext": 8,
        "ultraextended": 9, "ultraexpanded": 9, "ultrawide": 9, "xxextended": 9, "xxexpanded": 9, "xxwide": 9, "xexp": 9,
    ]
}

extension Classification {
    static func of(name: String, faces: [LibraryFace]) -> Classification {
        if faces.contains(where: { $0.face.isMonospaced }) { return .monospaced }
        if let byClass = Classification(familyClass: judged(faces)[0].familyClass) { return byClass }
        let name = name.lowercased()
        let hints: [(Classification, [String])] = [
            (.monospaced, ["mono", "code"]),
            (.ornamental, ["stencil", "inline", "outline", "fraktur", "blackletter"]),
            (.sansSerif, ["sans", "grotesk", "grotesque", "gothic"]),
            (.serif, ["serif", "slab", "garamond", "antiqua"]),
            (.script, ["script", "brush", "hand"]),
            // Symbol fonts' letters, when they have any, are often plain.
            (.symbol, ["symbol", "dingbat", "emoji"]),
        ]
        for (classification, words) in hints where words.contains(where: name.contains) { return classification }
        let judged = judged(faces)
        func agreed(_ answers: [Classification?]) -> Classification? {
            let found = Set(answers.compactMap { $0 })
            return found.count == 1 ? found.first : nil
        }
        if judged.allSatisfy({ $0.letterShape == .monospaced }) { return .monospaced }
        let shapes = judged.map(\.letterShape).filter { $0 != .monospaced }
        // PANOSE digits are often copied from another font: where they and the letters differ, the letters are right.
        return agreed(shapes) ?? agreed(judged.map(\.panose)) ?? .unclassified
    }

    init?(familyClass: Int) {
        switch familyClass {
        case 1, 2, 3, 4, 5, 7: self = .serif
        case 8: self = .sansSerif
        case 9: self = .ornamental
        case 10: self = .script
        case 12: self = .symbol
        default: return nil
        }
    }

    static func judged(_ faces: [LibraryFace]) -> [FontFace] {
        let letters = faces.map(\.face).filter { !$0.isOrnaments }
        let candidates = letters.isEmpty ? faces.map(\.face) : letters
        let uprights = candidates.filter { !$0.isItalic }
        return uprights.isEmpty ? candidates : uprights
    }
}
