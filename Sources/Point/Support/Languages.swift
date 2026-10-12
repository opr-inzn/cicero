import Foundation

/// Language data from Rosetta's Hyperglot, bundled as Resources/Languages.json (see
/// Resources/Languages-README.txt and scripts/update-languages.py). Everything that reads that file
/// lives here, so the source could be swapped without touching the rest of the app.
enum Languages {
    /// Every language, in ISO code order. Empty when the data file is missing from the bundle.
    static let all: [Language] = loaded.languages
    static let version: String? = loaded.version
    static let byISO: [String: Language] = Dictionary(all.map { ($0.iso, $0) }, uniquingKeysWith: { first, _ in first })
    private static let indices: [String: Int] = Dictionary(all.enumerated().map { ($1.iso, $0) }, uniquingKeysWith: { first, _ in first })

    static func language(_ iso: String) -> Language? { byISO[iso] }

    /// Position in `all`, which `LanguageSet` bitsets are indexed by.
    static func index(of iso: String) -> Int? { indices[iso] }

    private static let loaded: (version: String?, languages: [Language]) = {
        guard let url = Bundle.main.url(forResource: "Languages", withExtension: "json") else { return (nil, []) }
        do {
            return try load(from: url)
        } catch {
            NSLog("Point: failed to load Languages.json: \(error)")
            return (nil, [])
        }
    }()

    static func load(from url: URL) throws -> (version: String?, languages: [Language]) {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return (file.version, file.languages.map(Language.init))
    }

    private struct File: Decodable {
        var version: String?
        var languages: [Language.Raw]
    }
}

enum LanguageStatus: String, Decodable, Sendable {
    case living, historical, constructed
}

/// How well a font covers a language, in Hyperglot's terms.
enum LanguageSupport: Int, Comparable, Sendable {
    /// Every base character (and the marks they need) is there.
    case base = 1
    /// The auxiliary characters are there too.
    case full = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Language: Identifiable, Hashable, Sendable {
    let iso: String
    let name: String
    let autonym: String?
    /// First-language speakers; 0 when unknown.
    let speakers: Int
    let validity: String
    let status: LanguageStatus
    /// The orthographies Hyperglot checks by default (primary ones, grouped where required).
    let orthographies: [LanguageOrthography]

    var id: String { iso }
    var scripts: [String] { orthographies.map(\.script).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    /// Living and constructed languages, which is what Hyperglot's command line counts by default.
    var isCurrent: Bool { status != .historical }

    /// A line to set in a font: the language's own name, or its first characters.
    var sampleText: String {
        if let autonym, !autonym.isEmpty { return autonym }
        return orthographies.first.map { String($0.base.unicodeScalars.prefix(24).map(Character.init)) } ?? name
    }

    struct Raw: Decodable {
        var iso: String
        var name: String
        var autonym: String?
        var speakers: Int
        var validity: String
        var status: LanguageStatus
        var orthographies: [LanguageOrthography.Raw]
    }

    init(_ raw: Raw) {
        iso = raw.iso
        name = raw.name
        autonym = raw.autonym
        speakers = raw.speakers
        validity = raw.validity
        status = raw.status
        orthographies = raw.orthographies.map(LanguageOrthography.init)
    }

    static func == (lhs: Language, rhs: Language) -> Bool { lhs.iso == rhs.iso }
    func hash(into hasher: inout Hasher) { hasher.combine(iso) }
}

/// One script a language is written in, with the characters Hyperglot requires for it.
struct LanguageOrthography: Sendable {
    let script: String
    /// ISO 15924 code, e.g. "Latn".
    let scriptCode: String
    let autonym: String?
    /// Encoded characters in Hyperglot's order (uppercase, lowercase, …).
    let base: String
    /// Combining marks the base needs that can't be derived from its characters.
    let marks: String
    let auxiliary: String
    let auxiliaryMarks: String
    /// Sorted unique scalars a font must have for base support.
    let baseScalars: [UInt32]
    /// Sorted unique scalars full support needs on top of `baseScalars`.
    let auxiliaryScalars: [UInt32]

    struct Raw: Decodable {
        var script: String
        var scriptCode: String
        var autonym: String?
        var base: String
        var marks: String?
        var auxiliary: String?
        var auxiliaryMarks: String?
    }

    init(_ raw: Raw) {
        script = raw.script
        scriptCode = raw.scriptCode
        autonym = raw.autonym
        base = raw.base
        marks = raw.marks ?? ""
        auxiliary = raw.auxiliary ?? ""
        auxiliaryMarks = raw.auxiliaryMarks ?? ""
        baseScalars = Self.scalars(base + marks)
        auxiliaryScalars = Self.scalars(auxiliary + auxiliaryMarks)
    }

    private static func scalars(_ text: String) -> [UInt32] {
        Array(Set(text.unicodeScalars.map(\.value))).sorted()
    }

    /// Characters spaced out for display, marks on a dotted circle.
    static func spaced(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: "\u{25CC}" + String(scalar)
            default: String(scalar)
            }
        }.joined(separator: " ")
    }
}
