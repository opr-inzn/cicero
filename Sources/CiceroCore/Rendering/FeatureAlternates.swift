import CoreText
import Foundation

public struct FeatureAlternate: Hashable, Sendable {
    public let glyph: CGGlyph
    public let character: UInt32
    public let features: [String]
    public let featureNames: [String]
    public let alongWith: [String]
    public let alongWithNames: [String]

    public init(glyph: CGGlyph, character: UInt32, features: [String], featureNames: [String], alongWith: [String] = [],
                alongWithNames: [String] = []) {
        self.glyph = glyph
        self.character = character
        self.features = features
        self.featureNames = featureNames
        self.alongWith = alongWith
        self.alongWithNames = alongWithNames
        isFigureStyle = GlyphGroup.of(character) == .proportionalFigures && features.contains(where: FeatureAlternates.figureStyles.contains)
            && alongWith.allSatisfy(FeatureAlternates.figureStyles.contains)
    }

    public var drawnWith: [String] { Array(features.prefix(1)) + alongWith }
    public var allFeatures: [String] { features + alongWith }
    public var allFeatureNames: [String] { featureNames + alongWithNames }
    public var listedNames: String { alongWith.isEmpty ? featureNames.listed("or") : allFeatureNames.listed() }
    public let isFigureStyle: Bool
}

public enum FeatureAlternates {
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
        default: return nil
        }
    }

    public static func read(_ face: FontFace, excluding: Set<CGGlyph> = []) -> [UInt32: [FeatureAlternate]] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [:] }
        let found = GSUBSubstitutions.read(table) { rank(of: $0) != nil }.mapValues { $0.filter { $0.components.count == 1 } }
        let glyphs = Set(found.values.flatMap { $0.flatMap { [$0.glyph] + $0.components } })
        guard !glyphs.isEmpty else { return [:] }
        return resolve(found, characters: LigatureGroup.characterGlyphs(of: font, needed: glyphs), excluding: excluding,
                       names: names(in: font))
    }

    public static let figureStyles: Set<String> = ["onum", "lnum", "pnum"]

    static let chainLength = 3

    static func resolve(_ found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32], excluding: Set<CGGlyph>,
                        names: [String: String]) -> [UInt32: [FeatureAlternate]] {
        var order: [CGGlyph] = []
        var drawnFor: [CGGlyph: UInt32] = [:]
        var tags: [CGGlyph: [String]] = [:]
        var together: [CGGlyph: [String]] = [:]
        let features = found.keys.sorted { (rank(of: $0) ?? .max, $0) < (rank(of: $1) ?? .max, $1) }
        for feature in features {
            for entry in found[feature] ?? [] {
                guard let input = entry.components.first, let character = characters[input], entry.glyph != input,
                      characters[entry.glyph] == nil, !excluding.contains(entry.glyph)
                else { continue }
                if let first = drawnFor[entry.glyph] {
                    if first == character, tags[entry.glyph]?.contains(feature) == false { tags[entry.glyph]?.append(feature) }
                    continue
                }
                order.append(entry.glyph)
                drawnFor[entry.glyph] = character
                tags[entry.glyph] = [feature]
            }
        }
        let rankOf = Dictionary(uniqueKeysWithValues: features.enumerated().map { ($1, $0) })
        var frontier = Set(order)
        for _ in 1..<chainLength where !frontier.isEmpty {
            var following: Set<CGGlyph> = []
            for feature in features {
                for entry in found[feature] ?? [] {
                    guard let input = entry.components.first, frontier.contains(input), let character = drawnFor[input],
                          entry.glyph != input, drawnFor[entry.glyph] == nil, characters[entry.glyph] == nil,
                          !excluding.contains(entry.glyph)
                    else { continue }
                    let before = together[input] ?? Array(tags[input]!.prefix(1))
                    guard !before.contains(feature) else { continue }
                    order.append(entry.glyph)
                    drawnFor[entry.glyph] = character
                    together[entry.glyph] = (before + [feature]).sorted { rankOf[$0]! < rankOf[$1]! }
                    following.insert(entry.glyph)
                }
            }
            frontier = following
        }
        var result: [UInt32: [FeatureAlternate]] = [:]
        for glyph in order {
            let character = drawnFor[glyph]!
            let alternate: FeatureAlternate
            if let all = together[glyph] {
                let along = Array(all.dropFirst())
                alternate = FeatureAlternate(glyph: glyph, character: character, features: [all[0]], featureNames: [name(of: all[0], in: names)],
                                             alongWith: along, alongWithNames: along.map { name(of: $0, in: names) })
            } else {
                let features = tags[glyph]!
                alternate = FeatureAlternate(glyph: glyph, character: character, features: features,
                                             featureNames: features.map { name(of: $0, in: names) })
            }
            result[character, default: []].append(alternate)
        }
        return result
    }

    static func names(in font: CTFont) -> [String: String] {
        var names: [String: String] = [:]
        for feature in CTFontCopyFeatures(font) as? [[String: Any]] ?? [] {
            // A feature CoreText has no type of its own for, like a character variant, has its tag and name on the feature, with On and Off as its options; the others have them on their option.
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
