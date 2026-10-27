import CoreText
import Foundation

/// A glyph a feature offers in place of a character's own, like a single-storey a in a stylistic set, a swash or an
/// old-style figure: the font page lists it after the character's, marked as an alternate.
public struct FeatureAlternate: Hashable, Sendable {
    public let glyph: CGGlyph
    /// The character whose glyph it replaces.
    public let character: UInt32
    /// The features that draw it for the character, by tag ("ss01") and by name ("Single-storey a"), in the same order.
    public let features: [String]
    public let featureNames: [String]

    public init(glyph: CGGlyph, character: UInt32, features: [String], featureNames: [String]) {
        self.glyph = glyph
        self.character = character
        self.features = features
        self.featureNames = featureNames
    }
}

public enum FeatureAlternates {
    /// Keeps a font with alternates for thousands of characters to a sensible number.
    public static let limit = 3000

    /// The features that offer another design of a character, in the order a character's alternates are listed. Those
    /// that shape a script, set vertical text or the forms of East Asian characters are left out, but for the forms by
    /// place in a word that a Latin font can have too, and so are those with groups of their own (`FeatureGlyph`) and
    /// the ligatures'.
    static func rank(of tag: String) -> Int? {
        func numbered(_ prefix: String, through last: Int) -> Bool {
            tag.hasPrefix(prefix) && Int(tag.dropFirst(2)).map { (1...last).contains($0) } == true
        }
        if tag == "salt" { return 0 }
        if numbered("ss", through: 20) { return 1 }
        if numbered("cv", through: 99) { return 2 }
        switch tag {
        case "swsh", "cswh": return 3
        case "pcap", "unic": return 4
        case "c2pc": return 5
        case "onum", "lnum", "pnum", "zero": return 6
        case "titl", "hist", "calt", "rand", "nalt", "ornm", "jalt": return 7
        // A Latin font's forms for the start, middle and end of a word, and for a letter alone (see `positional`).
        case "init": return 8
        case "medi": return 9
        case "fina": return 10
        case "isol": return 11
        default: return nil
        }
    }

    /// The face's alternates by character, each glyph once, for the character its first feature draws it for; a
    /// glyph a character has too is left to the character, as are those in `excluding`, like the glyphs listed in
    /// groups of their own. Reads the font's GSUB table; call off the main thread.
    public static func read(_ face: FontFace, excluding: Set<CGGlyph> = []) -> [UInt32: [FeatureAlternate]] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [:] }
        let found = GSUBSubstitutions.read(table) { rank(of: $0) != nil }.mapValues { $0.filter { $0.components.count == 1 } }
        let glyphs = Set(found.values.flatMap { $0.flatMap { [$0.glyph] + $0.components } })
        guard !glyphs.isEmpty else { return [:] }
        return resolve(found, characters: LigatureGroup.characterGlyphs(of: font, needed: glyphs), excluding: excluding,
                       names: names(in: font))
    }

    /// Forms by place in a word: alternates for a Latin font's letters, figures or signs, but how a script like Arabic
    /// joins its letters, so not for those of a script with a group of its own.
    static let positional: Set<String> = ["init", "medi", "fina", "isol"]

    static func resolve(_ found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32], excluding: Set<CGGlyph>,
                        names: [String: String]) -> [UInt32: [FeatureAlternate]] {
        var inScript: [UInt32: Bool] = [:]
        func isInScript(_ character: UInt32) -> Bool {
            if let known = inScript[character] { return known }
            let found = GlyphGroup.of(character)?.isScript ?? false
            inScript[character] = found
            return found
        }
        var order: [CGGlyph] = []
        var drawnFor: [CGGlyph: UInt32] = [:]
        var tags: [CGGlyph: [String]] = [:]
        let features = found.keys.sorted { (rank(of: $0) ?? .max, $0) < (rank(of: $1) ?? .max, $1) }
        for feature in features {
            for entry in found[feature] ?? [] {
                guard let input = entry.components.first, let character = characters[input], entry.glyph != input,
                      characters[entry.glyph] == nil, !excluding.contains(entry.glyph),
                      !positional.contains(feature) || !isInScript(character)
                else { continue }
                if let first = drawnFor[entry.glyph] {
                    // Another feature that draws it for the same character.
                    if first == character, tags[entry.glyph]?.contains(feature) == false { tags[entry.glyph]?.append(feature) }
                    continue
                }
                guard order.count < limit else { continue }
                order.append(entry.glyph)
                drawnFor[entry.glyph] = character
                tags[entry.glyph] = [feature]
            }
        }
        var result: [UInt32: [FeatureAlternate]] = [:]
        for glyph in order {
            let character = drawnFor[glyph]!, features = tags[glyph]!
            result[character, default: []].append(FeatureAlternate(glyph: glyph, character: character, features: features,
                                                                   featureNames: features.map { name(of: $0, in: names) }))
        }
        return result
    }

    /// The names the font gives its OpenType features, as CoreText reads them, by tag: a stylistic set's own, like
    /// "Single-storey a", where it has one. A feature CoreText has no type of its own for, like a character variant,
    /// has its name on the feature, with On and Off as its options; the others on their option.
    static func names(in font: CTFont) -> [String: String] {
        var names: [String: String] = [:]
        for feature in CTFontCopyFeatures(font) as? [[String: Any]] ?? [] {
            if let tag = feature[kCTFontOpenTypeFeatureTag as String] as? String,
               let name = feature[kCTFontFeatureTypeNameKey as String] as? String {
                if names[tag] == nil { names[tag] = name }
                continue
            }
            for selector in feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? [] {
                guard let tag = selector[kCTFontOpenTypeFeatureTag as String] as? String,
                      let name = selector[kCTFontFeatureSelectorNameKey as String] as? String,
                      (selector[kCTFontOpenTypeFeatureValue as String] as? Int ?? 1) != 0, names[tag] == nil
                else { continue }
                names[tag] = name
            }
        }
        return names
    }

    /// A feature's name: the font's, else the one the OpenType specification gives it.
    static func name(of tag: String, in names: [String: String]) -> String {
        if let name = names[tag] { return name }
        if let number = Int(tag.dropFirst(2)) {
            if tag.hasPrefix("ss") { return "Stylistic Set \(number)" }
            if tag.hasPrefix("cv") { return "Character Variant \(number)" }
        }
        return standardNames[tag] ?? tag
    }

    private static let standardNames = [
        "salt": "Stylistic Alternates", "swsh": "Swash", "cswh": "Contextual Swash", "smcp": "Small Capitals",
        "pcap": "Petite Capitals", "unic": "Unicase", "c2sc": "Capitals to Small Capitals", "c2pc": "Capitals to Petite Capitals",
        "onum": "Old-Style Figures", "lnum": "Lining Figures", "pnum": "Proportional Figures", "zero": "Slashed Zero",
        "titl": "Titling Alternates", "hist": "Historical Forms", "calt": "Contextual Alternates", "rand": "Randomize",
        "nalt": "Alternate Annotation Forms", "ornm": "Ornaments", "jalt": "Justification Alternates",
        "locl": "Localized Forms", "tnum": "Tabular Figures", "init": "Initial Forms", "medi": "Medial Forms",
        "fina": "Terminal Forms", "isol": "Isolated Forms",
    ]
}
