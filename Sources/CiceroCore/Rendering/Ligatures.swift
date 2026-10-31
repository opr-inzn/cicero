import CoreText
import Foundation

/// A ligature a font makes: the characters it stands for and the glyph it draws instead.
public struct Ligature: Hashable, Sendable, Identifiable {
    public let glyph: CGGlyph
    /// The characters it replaces, in order ("f", "f", "i").
    public let characters: [UInt32]

    public init(glyph: CGGlyph, characters: [UInt32]) {
        self.glyph = glyph
        self.characters = characters
    }

    public var id: [UInt32] { characters }

    /// The characters as text, "ffi".
    public var text: String {
        String(String.UnicodeScalarView(characters.compactMap(Unicode.Scalar.init)))
    }
}

/// The ligatures of one OpenType feature, as the font page lists them.
public struct LigatureGroup: Identifiable, Sendable {
    /// The feature's tag, "liga".
    public let tag: String
    public let ligatures: [Ligature]
    public var id: String { tag }

    public init(tag: String, ligatures: [Ligature]) {
        self.tag = tag
        self.ligatures = ligatures
    }

    /// The features that make ligatures, in the order the font page shows them, with their names.
    public static let features: [(tag: String, name: String)] = [
        ("liga", "Standard Ligatures"), ("dlig", "Discretionary Ligatures"), ("hlig", "Historical Ligatures"),
        ("clig", "Contextual Ligatures"), ("rlig", "Required Ligatures"),
    ]

    public var name: String { Self.features.first { $0.tag == tag }?.name ?? tag }

    /// Keeps icon fonts, whose ligatures turn thousands of words into symbols, to a sensible number.
    public static let limit = 3000

    /// The face's ligatures by feature, those whose every component is a character (or another ligature of
    /// characters); ligatures of alternates and contextual forms that no character maps to are left out. Reads
    /// the font's GSUB table; call off the main thread.
    public static func read(_ face: FontFace) -> [LigatureGroup] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [] }
        // Only ligatures: a feature's lookups can substitute single glyphs too.
        let found = GSUBSubstitutions.read(table, features: Set(features.map(\.tag))).mapValues { $0.filter { $0.components.count >= 2 } }.filter { !$0.value.isEmpty }
        guard !found.isEmpty else { return [] }
        return resolve(found, characters: characterGlyphs(of: font, needed: Set(found.values.flatMap { $0.flatMap(\.components) })))
    }

    /// Turns glyph ligatures into character ligatures, in feature order. A component that's itself a ligature
    /// ("f_f" in "f_f_i") stands for its characters.
    static func resolve(_ found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32]) -> [LigatureGroup] {
        var made: [CGGlyph: [UInt32]] = [:]
        var pending = features.flatMap { feature in (found[feature.tag] ?? []).map { (feature.tag, $0) } }
        var resolved: [(String, GSUBSubstitutions.Entry, [UInt32])] = []
        // Each pass resolves the ligatures whose components are known by now, so ligatures of ligatures follow.
        while true {
            var next: [(String, GSUBSubstitutions.Entry)] = []
            for (tag, entry) in pending {
                var text: [UInt32] = []
                for component in entry.components {
                    if let scalar = characters[component] {
                        text.append(scalar)
                    } else if let ligature = made[component] {
                        text += ligature
                    } else {
                        text = []
                        break
                    }
                }
                if text.isEmpty {
                    next.append((tag, entry))
                } else {
                    resolved.append((tag, entry, text))
                    if made[entry.glyph] == nil { made[entry.glyph] = text }
                }
            }
            guard !next.isEmpty, next.count < pending.count else { break }
            pending = next
        }
        return features.compactMap { feature in
            var seen = Set<[UInt32]>()
            var ligatures: [Ligature] = []
            for (tag, entry, text) in resolved where tag == feature.tag && ligatures.count < limit && seen.insert(text).inserted {
                ligatures.append(Ligature(glyph: entry.glyph, characters: text))
            }
            return ligatures.isEmpty ? nil : LigatureGroup(tag: feature.tag, ligatures: ligatures)
        }
    }

    /// The character each needed glyph is drawn for: the lowest one when several share a glyph.
    static func characterGlyphs(of font: CTFont, needed: Set<CGGlyph>) -> [CGGlyph: UInt32] {
        var result: [CGGlyph: UInt32] = [:]
        forEachCharacter(of: font) { scalar, glyph in
            if needed.contains(glyph), result[glyph] == nil { result[glyph] = scalar }
            return result.count < needed.count
        }
        return result
    }

    /// Every character each needed glyph is drawn for, in code point order, like the Latin ĸ and the Cyrillic к of a
    /// font that draws them alike.
    static func allCharacters(of font: CTFont, needed: Set<CGGlyph>) -> [CGGlyph: [UInt32]] {
        var result: [CGGlyph: [UInt32]] = [:]
        forEachCharacter(of: font) { scalar, glyph in
            if needed.contains(glyph) { result[glyph, default: []].append(scalar) }
            return true
        }
        return result
    }

    /// The font's characters and their glyphs, in code point order, while `body` says to go on.
    private static func forEachCharacter(of font: CTFont, _ body: (UInt32, CGGlyph) -> Bool) {
        var units: [UniChar] = [0, 0]
        var glyphs: [CGGlyph] = [0, 0]
        for range in CharacterMap.characters(of: font).ranges {
            for scalar in range {
                let count: Int
                if scalar < 0x10000 {
                    units[0] = UniChar(scalar)
                    count = 1
                } else {
                    let value = scalar - 0x10000
                    units[0] = UniChar(0xD800 + (value >> 10))
                    units[1] = UniChar(0xDC00 + (value & 0x3FF))
                    count = 2
                }
                guard CTFontGetGlyphsForCharacters(font, units, &glyphs, count) else { continue }
                if !body(scalar, glyphs[0]) { return }
            }
        }
    }
}

/// Reads single, alternate and ligature substitutions (lookup types 1, 3 and 4) from a GSUB table, by feature: a single
/// substitution, or each choice of an alternate one, is an entry of one component. Lookups an extension (type 7) wraps
/// are read through it, and contextual lookups (types 5 and 6) are followed to the lookups they apply.
/// Every offset and count is checked against the table, so a damaged one gives fewer ligatures, never a crash.
enum GSUBSubstitutions {
    struct Entry: Hashable {
        var glyph: CGGlyph
        var components: [CGGlyph]
    }

    static func read(_ table: Data, features tags: Set<String>) -> [String: [Entry]] {
        read(table) { tags.contains($0) }
    }

    /// The features the table lists that `includes` says to read.
    static func read(_ table: Data, including includes: (String) -> Bool) -> [String: [Entry]] {
        let reader = Reader(bytes: [UInt8](table))
        // Header: version (4 bytes), then the offsets of the script, feature and lookup lists.
        guard let featureList = reader.u16(6), let lookupList = reader.u16(8) else { return [:] }
        let lookups = Lookups(reader: reader, list: lookupList)
        var result: [String: [Entry]] = [:]
        var done: [String: Set<Int>] = [:]
        for record in 0..<(reader.u16(featureList) ?? 0) {
            let at = featureList + 2 + record * 6
            guard let tag = reader.tag(at), includes(tag), let offset = reader.u16(at + 4) else { continue }
            let feature = featureList + offset
            for index in 0..<(reader.u16(feature + 2) ?? 0) {
                guard let lookup = reader.u16(feature + 4 + index * 2), done[tag, default: []].insert(lookup).inserted else { continue }
                var visited = Set<Int>()
                result[tag, default: []] += lookups.ligatures(in: lookup, visited: &visited)
            }
        }
        return result.filter { !$0.value.isEmpty }
    }

    /// A feature's substitutions by the languages its records are for, by their OpenType tags, like ["TRK", "AZE"], as
    /// the script list's language systems name them: a font's localized forms. Records only a script's default
    /// language system lists, which are on for every language, are left out.
    static func readByLanguage(_ table: Data, feature tag: String) -> [(languages: [String], entries: [Entry])] {
        let reader = Reader(bytes: [UInt8](table))
        guard let scriptList = reader.u16(4), let featureList = reader.u16(6), let lookupList = reader.u16(8) else { return [] }
        // Feature index → the languages whose language systems list it.
        var languages: [Int: [String]] = [:]
        for script in 0..<(reader.u16(scriptList) ?? 0) {
            guard let offset = reader.u16(scriptList + 2 + script * 6 + 4) else { continue }
            let start = scriptList + offset
            for system in 0..<(reader.u16(start + 2) ?? 0) {
                let at = start + 4 + system * 6
                guard let language = reader.tag(at)?.trimmingCharacters(in: .whitespaces), let offset = reader.u16(at + 4) else { continue }
                let langSys = start + offset
                // Lookup order (reserved), then the required feature's index, then the others'.
                let required = reader.u16(langSys + 2).flatMap { $0 == 0xFFFF ? nil : $0 }
                let indices = (0..<(reader.u16(langSys + 4) ?? 0)).compactMap { reader.u16(langSys + 6 + $0 * 2) }
                for index in (required.map { [$0] } ?? []) + indices where !languages[index, default: []].contains(language) {
                    languages[index, default: []].append(language)
                }
            }
        }
        let lookups = Lookups(reader: reader, list: lookupList)
        var result: [(languages: [String], entries: [Entry])] = []
        for record in 0..<(reader.u16(featureList) ?? 0) {
            let at = featureList + 2 + record * 6
            guard reader.tag(at) == tag, let names = languages[record], let offset = reader.u16(at + 4) else { continue }
            let feature = featureList + offset
            var entries: [Entry] = []
            for index in 0..<(reader.u16(feature + 2) ?? 0) {
                guard let lookup = reader.u16(feature + 4 + index * 2) else { continue }
                var visited = Set<Int>()
                entries += lookups.ligatures(in: lookup, visited: &visited)
            }
            if !entries.isEmpty { result.append((names, entries)) }
        }
        return result
    }

    private struct Lookups {
        let reader: Reader
        let list: Int

        /// A lookup's ligatures, and those of the lookups it applies in context.
        func ligatures(in index: Int, visited: inout Set<Int>) -> [Entry] {
            guard visited.insert(index).inserted, visited.count < 64,
                  index < reader.u16(list) ?? 0, let offset = reader.u16(list + 2 + index * 2)
            else { return [] }
            let lookup = list + offset
            guard let type = reader.u16(lookup), let count = reader.u16(lookup + 4) else { return [] }
            var entries: [Entry] = []
            for subtable in 0..<count {
                guard let offset = reader.u16(lookup + 6 + subtable * 2) else { continue }
                entries += self.subtable(lookup + offset, type: type, visited: &visited)
            }
            return entries
        }

        private func subtable(_ start: Int, type: Int, visited: inout Set<Int>) -> [Entry] {
            switch type {
            case 1:
                return singleSubstitution(start)
            case 3:
                return alternateSubstitution(start)
            case 4:
                return ligatureSubstitution(start)
            case 5, 6:
                return applied(in: start, chained: type == 6).flatMap { ligatures(in: $0, visited: &visited) }
            case 7:
                guard reader.u16(start) == 1, let type = reader.u16(start + 2), type != 7, let offset = reader.u32(start + 4) else { return [] }
                return subtable(start + offset, type: type, visited: &visited)
            default:
                return []
            }
        }

        /// SingleSubstFormat1, a delta added to each glyph in the coverage, and SingleSubstFormat2, a substitute for each.
        private func singleSubstitution(_ start: Int) -> [Entry] {
            guard let format = reader.u16(start), let coverage = reader.u16(start + 2) else { return [] }
            let inputs = reader.coverage(start + coverage)
            switch format {
            case 1:
                guard let delta = reader.u16(start + 4) else { return [] }
                return inputs.map { Entry(glyph: CGGlyph((Int($0) + delta) & 0xFFFF), components: [$0]) }
            case 2:
                guard let count = reader.u16(start + 4) else { return [] }
                return inputs.enumerated().compactMap { index, input in
                    guard index < count, let glyph = reader.u16(start + 6 + index * 2) else { return nil }
                    return Entry(glyph: CGGlyph(glyph), components: [input])
                }
            default:
                return []
            }
        }

        /// AlternateSubstFormat1: per glyph in the coverage, a set of glyphs to choose from in its place.
        private func alternateSubstitution(_ start: Int) -> [Entry] {
            guard reader.u16(start) == 1, let coverage = reader.u16(start + 2), let setCount = reader.u16(start + 4) else { return [] }
            return reader.coverage(start + coverage).enumerated().flatMap { index, input -> [Entry] in
                guard index < setCount, let offset = reader.u16(start + 6 + index * 2), let count = reader.u16(start + offset) else { return [] }
                return (0..<count).compactMap { choice in
                    reader.u16(start + offset + 2 + choice * 2).map { Entry(glyph: CGGlyph($0), components: [input]) }
                }
            }
        }

        /// LigatureSubstFormat1: per first glyph in the coverage, a set of ligatures of the glyphs after it.
        private func ligatureSubstitution(_ start: Int) -> [Entry] {
            guard reader.u16(start) == 1, let coverage = reader.u16(start + 2), let setCount = reader.u16(start + 4) else { return [] }
            let firsts = reader.coverage(start + coverage)
            var entries: [Entry] = []
            for (index, first) in firsts.enumerated() where index < setCount {
                guard let setOffset = reader.u16(start + 6 + index * 2) else { continue }
                let set = start + setOffset
                for ligature in 0..<(reader.u16(set) ?? 0) {
                    guard let offset = reader.u16(set + 2 + ligature * 2), let glyph = reader.u16(set + offset),
                          let count = reader.u16(set + offset + 2), count >= 2
                    else { continue }
                    let rest = (0..<count - 1).compactMap { reader.u16(set + offset + 4 + $0 * 2) }
                    guard rest.count == count - 1 else { continue }
                    entries.append(Entry(glyph: CGGlyph(glyph), components: [first] + rest.map(CGGlyph.init)))
                }
            }
            return entries
        }

        /// The lookups a contextual subtable applies: the lookup list index of every SubstLookupRecord in it.
        private func applied(in start: Int, chained: Bool) -> [Int] {
            guard let format = reader.u16(start) else { return [] }
            switch format {
            case 1, 2:
                // Rule sets, each a list of rules, each ending in its records.
                let first = start + (chained && format == 2 ? 10 : format == 2 ? 6 : 4)
                guard let setCount = reader.u16(first) else { return [] }
                var indices: [Int] = []
                for set in 0..<setCount {
                    guard let setOffset = reader.u16(first + 2 + set * 2), setOffset != 0 else { continue }
                    let ruleSet = start + setOffset
                    for rule in 0..<(reader.u16(ruleSet) ?? 0) {
                        guard let offset = reader.u16(ruleSet + 2 + rule * 2) else { continue }
                        indices += chained ? chainedRuleRecords(ruleSet + offset) : ruleRecords(ruleSet + offset)
                    }
                }
                return indices
            case 3:
                if chained {
                    guard let backtrack = reader.u16(start + 2) else { return [] }
                    var at = start + 4 + backtrack * 2
                    guard let input = reader.u16(at) else { return [] }
                    at += 2 + input * 2
                    guard let lookahead = reader.u16(at) else { return [] }
                    at += 2 + lookahead * 2
                    return records(at)
                }
                guard let glyphs = reader.u16(start + 2), let count = reader.u16(start + 4) else { return [] }
                return records(start + 6 + glyphs * 2, count: count)
            default:
                return []
            }
        }

        /// SubRule and SubClassRule: glyph count, record count, the input after the first, then the records.
        private func ruleRecords(_ rule: Int) -> [Int] {
            guard let glyphs = reader.u16(rule), glyphs >= 1, let count = reader.u16(rule + 2) else { return [] }
            return records(rule + 4 + (glyphs - 1) * 2, count: count)
        }

        /// ChainSubRule and ChainSubClassRule: backtrack, input after the first, lookahead, then the records.
        private func chainedRuleRecords(_ rule: Int) -> [Int] {
            guard let backtrack = reader.u16(rule) else { return [] }
            var at = rule + 2 + backtrack * 2
            guard let input = reader.u16(at), input >= 1 else { return [] }
            at += 2 + (input - 1) * 2
            guard let lookahead = reader.u16(at) else { return [] }
            return records(at + 2 + lookahead * 2)
        }

        /// A count followed by that many SubstLookupRecords (sequence index, lookup list index).
        private func records(_ at: Int) -> [Int] {
            guard let count = reader.u16(at) else { return [] }
            return records(at + 2, count: count)
        }

        private func records(_ at: Int, count: Int) -> [Int] {
            (0..<count).compactMap { reader.u16(at + $0 * 4 + 2) }
        }
    }

    /// Big-endian reads that return nil past the end of the table.
    struct Reader {
        let bytes: [UInt8]

        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= bytes.count else { return nil }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }

        func u32(_ offset: Int) -> Int? {
            guard let high = u16(offset), let low = u16(offset + 2) else { return nil }
            return high << 16 | low
        }

        func tag(_ offset: Int) -> String? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
        }

        /// The glyphs a Coverage table lists, in coverage index order.
        func coverage(_ start: Int) -> [CGGlyph] {
            switch u16(start) {
            case 1:
                guard let count = u16(start + 2) else { return [] }
                return (0..<count).compactMap { u16(start + 4 + $0 * 2) }.map(CGGlyph.init)
            case 2:
                guard let count = u16(start + 2) else { return [] }
                var glyphs: [(index: Int, glyph: CGGlyph)] = []
                for range in 0..<count {
                    let at = start + 4 + range * 6
                    guard let first = u16(at), let last = u16(at + 2), let index = u16(at + 4), first <= last else { continue }
                    // No more than a font has glyphs: a damaged table's ranges could otherwise add up to billions.
                    guard glyphs.count + (last - first + 1) <= 0x10000 else { break }
                    for glyph in first...last { glyphs.append((index + glyph - first, CGGlyph(glyph))) }
                }
                return glyphs.sorted { $0.index < $1.index }.map(\.glyph)
            default:
                return []
            }
        }
    }
}

/// A glyph an OpenType feature puts in place of a character's, like a small capital, a tabular figure or a hyphen for
/// capitals, which has no character of its own.
public struct FeatureGlyph: Hashable, Sendable {
    public let glyph: CGGlyph
    /// The character whose glyph it replaces.
    public let character: UInt32
    /// The feature's tag, "tnum".
    public let feature: String
    /// The features it takes on top of that one, like Old-Style Figures for a tabular old-style figure.
    public let alongWith: [String]
    /// Their names, the font's own where it has them, like "Single-storey a" for ss01.
    public let alongWithNames: [String]
    /// Whether it's an alternate of another of these glyphs, like a stylistic set's small capital a of the small
    /// capital a: listed after it, marked as an alternate.
    public let isAlternate: Bool
    /// The languages a localized form is for, by their OpenType tags, like ["SRB", "MKD"].
    public let languages: [String]

    public init(glyph: CGGlyph, character: UInt32, feature: String, alongWith: [String] = [], alongWithNames: [String]? = nil,
                isAlternate: Bool = false, languages: [String] = []) {
        self.glyph = glyph
        self.character = character
        self.feature = feature
        self.alongWith = alongWith
        self.alongWithNames = alongWithNames ?? alongWith.map { FeatureAlternates.name(of: $0, in: [:]) }
        self.isAlternate = isAlternate
        self.languages = languages
    }

    /// The features read for the font page's glyphs, in the order it lists their glyphs, with their names and the
    /// groups they go in.
    public static let features: [(tag: String, name: String, group: GlyphGroup)] = [
        ("smcp", "Small Capitals", .smallCaps), ("c2sc", "Capitals to Small Capitals", .smallCaps),
        ("tnum", "Tabular Figures", .tabularFigures),
        ("sups", "Superscript", .superscripts), ("subs", "Subscript", .subscripts), ("sinf", "Scientific Inferiors", .subscripts),
        ("numr", "Numerators", .numerators), ("dnom", "Denominators", .denominators), ("ordn", "Ordinals", .ordinals),
        ("case", "Case-Sensitive Forms", .caseSensitiveForms), ("locl", "Localized Forms", .localizedForms),
    ]

    /// The feature's name, or for a localized form the languages it's for, like "Serbian and Macedonian".
    public var featureName: String {
        if feature == "locl", !languages.isEmpty { return OpenTypeLanguages.names(of: languages) }
        return Self.features.first { $0.tag == feature }?.name ?? feature
    }
    /// Its feature's tag and those it takes along with it, and their names, in the same order.
    public var featureTags: [String] { [feature] + alongWith }
    public var featureNames: [String] { [featureName] + alongWithNames }
    public var group: GlyphGroup { Self.features.first { $0.tag == feature }?.group ?? .graphical }

    /// Keeps a font with features over thousands of glyphs to a sensible number.
    public static let limit = 3000

    /// The face's glyphs that only those features draw, each once, by feature, then character, the case-sensitive forms
    /// as their characters are listed (see `GlyphSection.signPrecedes`) and superscripts, subscripts, numerators and
    /// denominators figures first (see `GlyphSection.valueOrder`), but the small capitals first, in their letters'
    /// order (see `letterOrder`), each followed by its alternates (see `smallCapAlternates`), and the localized forms by
    /// language (see `localizedForms`); a glyph a character has too, like a superscript two the font maps U+00B2 to, is
    /// left to the character, and accents' case-sensitive forms are left out. Reads the font's GSUB table; call off the
    /// main thread.
    public static func read(_ face: FontFace) -> [FeatureGlyph] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [] }
        let tags = Set(features.map(\.tag)).union(figureStyles)
        let found = GSUBSubstitutions.read(table) { tags.contains($0) || drawsSmallCapAlternates($0) }
            .mapValues { $0.filter { $0.components.count == 1 } }
        let glyphs = Set(found.values.flatMap { $0.flatMap { [$0.glyph] + $0.components } })
        guard !glyphs.isEmpty else { return [] }
        let localized = found["locl"] == nil ? [] : GSUBSubstitutions.readByLanguage(table, feature: "locl")
            .map { (languages: $0.languages, entries: $0.entries.filter { $0.components.count == 1 }) }
        let shared = localized.isEmpty ? [:] : LigatureGroup.allCharacters(of: font, needed: Set(localized.flatMap { $0.entries.compactMap(\.components.first) }))
        return resolve(found, characters: LigatureGroup.characterGlyphs(of: font, needed: glyphs), names: FeatureAlternates.names(in: font),
                       localized: localized, shared: shared)
    }

    /// The features whose glyphs for small capitals are small capitals too: those that offer alternates, like a stylistic
    /// set, but Lining Figures, which can give a small capital figure's full-size one, the forms for a language, like a
    /// Turkish small capital i, and tabular figures.
    static func drawsSmallCapAlternates(_ tag: String) -> Bool {
        FeatureAlternates.rank(of: tag) != nil && tag != "lnum" || tag == "locl" || tag == "tnum"
    }

    /// Whether a character is a private-use one, where an older font can keep its small capitals too, like U+F761 for a
    /// small capital a: those are listed as small capitals, by the letter they're for, not as characters.
    static func isPrivateUse(_ character: UInt32) -> Bool {
        Unicode.Scalar(character)?.properties.generalCategory == .privateUse
    }

    /// The features that draw figures in another style, which tabular figures can take on too.
    static let figureStyles = ["onum", "lnum", "zero"]

    static func resolve(_ found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32],
                        names: [String: String] = [:],
                        localized: [(languages: [String], entries: [GSUBSubstitutions.Entry])] = [],
                        shared: [CGGlyph: [UInt32]] = [:]) -> [FeatureGlyph] {
        var seen = Set<CGGlyph>()
        var result: [FeatureGlyph] = []
        for feature in features {
            if feature.tag == "locl" {
                for glyph in localizedForms(localized, characters: characters, shared: shared) where result.count < limit && seen.insert(glyph.glyph).inserted {
                    result.append(glyph)
                }
                continue
            }
            let entries = (found[feature.tag] ?? []).compactMap { entry -> FeatureGlyph? in
                guard let input = entry.components.first, let character = characters[input], entry.glyph != input,
                      characters[entry.glyph] == nil || feature.group == .smallCaps && isPrivateUse(characters[entry.glyph]!)
                else { return nil }
                // Accents for capitals are the accented capitals' business, not worth a cell each; Greek's too, like the
                // tonos, which the Greek group lists.
                if feature.tag == "case", let group = GlyphGroup.of(character), group == .diacriticalMarks || group == .combiningMarks
                    || (group == .greek && Unicode.Scalar(character)?.properties.generalCategory == .modifierSymbol) {
                    return nil
                }
                return FeatureGlyph(glyph: entry.glyph, character: character, feature: feature.tag)
            }
            // Case-sensitive forms as their characters are listed, brackets in pairs (see `GlyphSection.signPrecedes`);
            // superscripts, subscripts, numerators and denominators as their groups' characters are, figures first (see
            // `GlyphSection.valueOrder`).
            let byValue: Set<GlyphGroup> = [.superscripts, .subscripts, .numerators, .denominators]
            let sorted = feature.tag == "case" ? entries.sorted { GlyphSection.signPrecedes($0.character, $1.character) }
                : byValue.contains(feature.group) ? entries.sorted { a, b in
                    let (x, y) = (GlyphSection.valueOrder(of: a.character, in: feature.group), GlyphSection.valueOrder(of: b.character, in: feature.group))
                    return x != y ? x < y : a.glyph < b.glyph
                }
                : entries.sorted { $0.character < $1.character }
            let combined = feature.tag == "tnum" ? tabularFigures(in: found, characters: characters) : []
            for glyph in sorted + combined where result.count < limit && seen.insert(glyph.glyph).inserted {
                result.append(glyph)
            }
        }
        // Each small capital followed by its alternates; those of none the font draws, where their letters go.
        let smallCaps = result.filter { $0.group == .smallCaps }
        var after: [CGGlyph: [FeatureGlyph]] = [:]
        var blocks = smallCaps.map { [$0] }
        for (alternate, of) in smallCapAlternates(in: found, characters: characters, smallCaps: smallCaps, names: names)
        where result.count < limit && seen.insert(alternate.glyph).inserted {
            result.append(alternate)
            if let of { after[of, default: []].append(alternate) } else { blocks.append([alternate]) }
        }
        let ordered = blocks.map { (order: letterOrder(of: $0[0].character), then: ($0[0].isAlternate ? 1 : 0, $0[0].glyph), block: $0) }
            .sorted { $0.order != $1.order ? $0.order < $1.order : $0.then < $1.then }
        return ordered.flatMap { $0.block + (after[$0.block[0].glyph] ?? []) } + result.filter { $0.group != .smallCaps }
    }

    /// A font's localized forms, each once, for the languages of every record of the feature that draws it for the same
    /// character, in a run for each of those, the runs of Latin letters first, then by the script of their first
    /// character, then the languages' names; each in its letters' order (see `letterOrder`). Records that draw the same
    /// form for another character, and glyphs a character has too, like the ș Romanian's draw for ş, are left out. A
    /// glyph several characters share, in `shared`, is the one of the script most of its record's are in: a Bulgarian
    /// к, not the Latin ĸ a font draws like it.
    static func localizedForms(_ localized: [(languages: [String], entries: [GSUBSubstitutions.Entry])],
                               characters: [CGGlyph: UInt32], shared: [CGGlyph: [UInt32]] = [:]) -> [FeatureGlyph] {
        var order: [CGGlyph] = []
        var forms: [CGGlyph: (character: UInt32, languages: [String])] = [:]
        for (languages, entries) in localized {
            let scripts = entries.compactMap { $0.components.first.flatMap { characters[$0] }.flatMap(UnicodeScripts.script(of:)) }
            let main = Dictionary(grouping: scripts, by: { $0 }).max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
            for entry in entries {
                guard let input = entry.components.first, var character = characters[input], entry.glyph != input,
                      characters[entry.glyph] == nil
                else { continue }
                if let main, UnicodeScripts.script(of: character) != main,
                   let other = shared[input]?.first(where: { UnicodeScripts.script(of: $0) == main }) {
                    character = other
                }
                if let form = forms[entry.glyph] {
                    guard form.character == character else { continue }
                    forms[entry.glyph]!.languages += languages.filter { !form.languages.contains($0) }
                } else {
                    order.append(entry.glyph)
                    forms[entry.glyph] = (character, languages)
                }
            }
        }
        let glyphs = order.map { FeatureGlyph(glyph: $0, character: forms[$0]!.character, feature: "locl", languages: forms[$0]!.languages) }
        let runs = Dictionary(grouping: glyphs, by: \.languages).values.map { run in
            let sorted = run.map { (order: letterOrder(of: $0.character), glyph: $0) }
                .sorted { $0.order != $1.order ? $0.order < $1.order : $0.glyph.glyph < $1.glyph.glyph }.map(\.glyph)
            return (script: letterOrder(of: sorted[0].character).0, name: OpenTypeLanguages.names(of: sorted[0].languages), glyphs: sorted)
        }
        return runs.sorted { ($0.script, $0.name) < ($1.script, $1.name) }.flatMap(\.glyphs)
    }

    /// The small capitals other features draw, with the one each is an alternate of, if any: a stylistic set's small
    /// capital a, which the set draws for the small capital a or Small Capitals for the set's a, of the small capital a,
    /// or a Turkish small capital i, of the small capital i. Each takes a small capitals feature and one other, found
    /// from a small capital in `smallCaps`, then from a character, lowercase letters before capitals, and not through
    /// another character's glyph; a glyph the small capitals features draw a small capital for is full-size, like the
    /// lining alternate of a currency sign whose small capital is its old-style one. A small capital's alternates are in
    /// the order of their features.
    static func smallCapAlternates(in found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32],
                                   smallCaps: [FeatureGlyph], names: [String: String]) -> [(FeatureGlyph, of: CGGlyph?)] {
        let smallCapTags: Set<String> = ["smcp", "c2sc"]
        guard !smallCaps.isEmpty || smallCapTags.contains(where: { found[$0] != nil }) else { return [] }
        var next: [CGGlyph: [(glyph: CGGlyph, tag: String)]] = [:]
        for tag in found.keys.filter({ smallCapTags.contains($0) || drawsSmallCapAlternates($0) }).sorted() {
            for entry in found[tag] ?? [] {
                guard let input = entry.components.first, input != entry.glyph,
                      characters[entry.glyph].map(isPrivateUse) ?? true
                else { continue }
                next[input, default: []].append((entry.glyph, tag))
            }
        }
        guard !next.isEmpty else { return [] }
        // From a small capital, another feature's way first: a contextual lookup of Small Capitals can draw a stylistic
        // set's small capital from the small capital too, and that's the set's.
        for (input, edges) in next {
            next[input] = edges.filter { !smallCapTags.contains($0.tag) } + edges.filter { smallCapTags.contains($0.tag) }
        }
        let fullSize = Set(smallCapTags.flatMap { found[$0] ?? [] }.compactMap(\.components.first))
        struct Step: Hashable {
            let glyph: CGGlyph
            /// Whether a small capitals feature is on the way.
            let small: Bool
        }
        struct Path {
            let character: UInt32
            let tags: [String]
            /// The small capital of `smallCaps` on the way.
            let through: CGGlyph?
        }
        var paths: [Step: Path] = [:]
        var frontier: [Step] = []
        for smallCap in smallCaps {
            let step = Step(glyph: smallCap.glyph, small: true)
            paths[step] = Path(character: smallCap.character, tags: [smallCap.feature], through: smallCap.glyph)
            frontier.append(step)
        }
        let listed = Set(smallCaps.map(\.glyph))
        let starts = characters.filter { next[$0.key] != nil && !listed.contains($0.key) }.map { glyph, character in
            let group = GlyphGroup.of(character)
            return (key: (group == .uppercase || group == .uppercaseAccents ? 1 : 0, character, glyph), glyph: glyph, character: character)
        }
        for (_, glyph, character) in starts.sorted(by: { $0.key < $1.key }) {
            let step = Step(glyph: glyph, small: false)
            paths[step] = Path(character: character, tags: [], through: nil)
            frontier.append(step)
        }
        var reached: [Step] = []
        for _ in 0..<2 {
            var following: [Step] = []
            for step in frontier {
                let path = paths[step]!
                guard path.tags.count < 2 else { continue }
                for (glyph, tag) in next[step.glyph] ?? [] {
                    let to = Step(glyph: glyph, small: step.small || smallCapTags.contains(tag))
                    guard paths[to] == nil else { continue }
                    paths[to] = Path(character: path.character, tags: path.tags + [tag],
                                     through: path.through ?? (listed.contains(glyph) ? glyph : nil))
                    following.append(to)
                    if to.small, !listed.contains(glyph), !fullSize.contains(glyph) { reached.append(to) }
                }
            }
            frontier = following
        }
        // A small capital reached from an alternate, like Small Capitals' for a stylistic set's a, is the alternate of the
        // character's own small capital, or its lowercase letter's.
        var own: [UInt32: CGGlyph] = [:]
        for smallCap in smallCaps where own[smallCap.character] == nil { own[smallCap.character] = smallCap.glyph }
        func ownSmallCap(of character: UInt32) -> CGGlyph? {
            if let glyph = own[character] { return glyph }
            let lowercase = Unicode.Scalar(character).map { Array(String(Character($0)).lowercased().unicodeScalars) } ?? []
            return lowercase.count == 1 ? own[lowercase[0].value] : nil
        }
        let alternates = reached.map { step -> (FeatureGlyph, of: CGGlyph?) in
            let path = paths[step]!
            var others: [String] = []
            for tag in path.tags where !smallCapTags.contains(tag) && !others.contains(tag) { others.append(tag) }
            let glyph = FeatureGlyph(glyph: step.glyph, character: path.character, feature: path.tags.first { smallCapTags.contains($0) }!,
                                     alongWith: others, alongWithNames: others.map { FeatureAlternates.name(of: $0, in: names) },
                                     isAlternate: true)
            return (glyph, path.through ?? ownSmallCap(of: path.character))
        }
        // Stylistic alternates, sets and character variants, then swashes and so on, then the forms for a language, like
        // FeatureAlternates.rank has them; each by its tags, then glyph.
        func order(_ glyph: FeatureGlyph) -> [Int] { glyph.alongWith.map { FeatureAlternates.rank(of: $0) ?? ($0 == "locl" ? 20 : 21) } }
        return alternates.sorted { a, b in
            let (x, y) = (order(a.0), order(b.0))
            if x != y { return x.lexicographicallyPrecedes(y) }
            if a.0.alongWith != b.0.alongWith { return a.0.alongWith.lexicographicallyPrecedes(b.0.alongWith) }
            return a.0.glyph < b.0.glyph
        }
    }

    /// Where a small capital or localized form goes in its group: the letters first, in their lowercase letters' order
    /// (see `GlyphSection.letterOrder`), as Glyphs names small capitals after those, like aacute.sc, a capital's after
    /// its lowercase letter's, whichever feature draws it, like İ's after i's; then figures and signs.
    static func letterOrder(of character: UInt32) -> (GlyphGroup, UInt32, UInt32, UInt32, Int, UInt32) {
        let group: GlyphGroup = switch GlyphGroup.of(character) ?? .graphical {
        case .uppercase, .lowercase, .uppercaseAccents, .lowercaseAccents: .lowercase
        case let other: other
        }
        let lowercase = Unicode.Scalar(character).flatMap { String(Character($0)).lowercased().unicodeScalars.first?.value } ?? character
        let (base, kind, letter, _, _) = GlyphSection.letterOrder(of: lowercase)
        return (group, base, kind, letter, lowercase == character ? 0 : 1, character)
    }

    /// Tabular figures in another style, like old-style ones, by style, then character: glyphs of their own (a
    /// zero.osf.tf, New York's zero.onum.tnum) that neither feature draws for a character alone. Tabular Figures draws
    /// them for the style's figures, or the style's feature for the tabular ones; fonts tend to do both.
    static func tabularFigures(in found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32]) -> [FeatureGlyph] {
        let tabular = found["tnum"] ?? []
        /// What `entries` draw for characters' own glyphs, glyph → character.
        func drawn(by entries: [GSUBSubstitutions.Entry]) -> [CGGlyph: UInt32] {
            entries.reduce(into: [:]) { drawn, entry in
                if let input = entry.components.first, let character = characters[input], characters[entry.glyph] == nil {
                    drawn[entry.glyph] = character
                }
            }
        }
        let tabularFor = drawn(by: tabular)
        return figureStyles.flatMap { style -> [FeatureGlyph] in
            let styled = found[style] ?? []
            let styledFor = drawn(by: styled)
            let entries = tabular.map { ($0, styledFor) } + styled.map { ($0, tabularFor) }
            return entries.compactMap { entry, from -> FeatureGlyph? in
                guard let input = entry.components.first, let character = from[input], characters[entry.glyph] == nil,
                      entry.glyph != input
                else { return nil }
                return FeatureGlyph(glyph: entry.glyph, character: character, feature: "tnum", alongWith: [style])
            }
            .sorted { $0.character < $1.character }
        }
    }
}
