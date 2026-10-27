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
        var units: [UniChar] = [0, 0]
        var glyphs: [CGGlyph] = [0, 0]
        for range in ScalarRanges(characterSet: CTFontCopyCharacterSet(font)).ranges {
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
                let glyph = glyphs[0]
                if needed.contains(glyph), result[glyph] == nil {
                    result[glyph] = scalar
                    if result.count == needed.count { return result }
                }
            }
        }
        return result
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

    public init(glyph: CGGlyph, character: UInt32, feature: String, alongWith: [String] = []) {
        self.glyph = glyph
        self.character = character
        self.feature = feature
        self.alongWith = alongWith
    }

    /// The features read for the font page's glyphs, in the order it lists their glyphs, with their names and the
    /// groups they go in.
    public static let features: [(tag: String, name: String, group: GlyphGroup)] = [
        ("smcp", "Small Capitals", .smallCaps), ("c2sc", "Capitals to Small Capitals", .smallCaps),
        ("tnum", "Tabular Figures", .tabularFigures),
        ("sups", "Superscript", .superscripts), ("subs", "Subscript", .subscripts), ("sinf", "Scientific Inferiors", .subscripts),
        ("numr", "Numerators", .numerators), ("dnom", "Denominators", .denominators), ("ordn", "Ordinals", .ordinals),
        ("case", "Case-Sensitive Forms", .caseSensitiveForms),
    ]

    public var featureName: String { Self.features.first { $0.tag == feature }?.name ?? feature }
    /// Its feature's tag and those it takes along with it, and their names, in the same order.
    public var featureTags: [String] { [feature] + alongWith }
    public var featureNames: [String] { [featureName] + alongWith.map { FeatureAlternates.name(of: $0, in: [:]) } }
    public var group: GlyphGroup { Self.features.first { $0.tag == feature }?.group ?? .graphical }

    /// Keeps a font with features over thousands of glyphs to a sensible number.
    public static let limit = 3000

    /// The face's glyphs that only those features draw, each once, by feature, then character, but the small capitals
    /// first, in their letters' order (see `smallCapOrder`); a glyph a character has too, like a superscript two the
    /// font maps U+00B2 to, is left to the character, and accents' case-sensitive forms are left out. Reads the font's
    /// GSUB table; call off the main thread.
    public static func read(_ face: FontFace) -> [FeatureGlyph] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data? else { return [] }
        let tags = Set(features.map(\.tag)).union(figureStyles)
        let found = GSUBSubstitutions.read(table, features: tags).mapValues { $0.filter { $0.components.count == 1 } }
        let glyphs = Set(found.values.flatMap { $0.flatMap { [$0.glyph] + $0.components } })
        guard !glyphs.isEmpty else { return [] }
        return resolve(found, characters: LigatureGroup.characterGlyphs(of: font, needed: glyphs))
    }

    /// The features that draw figures in another style, which tabular figures can take on too.
    static let figureStyles = ["onum", "lnum", "zero"]

    static func resolve(_ found: [String: [GSUBSubstitutions.Entry]], characters: [CGGlyph: UInt32]) -> [FeatureGlyph] {
        var seen = Set<CGGlyph>()
        var result: [FeatureGlyph] = []
        for feature in features {
            let entries = (found[feature.tag] ?? []).compactMap { entry -> FeatureGlyph? in
                guard let input = entry.components.first, let character = characters[input], characters[entry.glyph] == nil,
                      entry.glyph != input
                else { return nil }
                // Accents for capitals are the accented capitals' business, not worth a cell each; Greek's too, like the
                // tonos, which the Greek group lists.
                if feature.tag == "case", let group = GlyphGroup.of(character), group == .diacriticalMarks || group == .combiningMarks
                    || (group == .greek && Unicode.Scalar(character)?.properties.generalCategory == .modifierSymbol) {
                    return nil
                }
                return FeatureGlyph(glyph: entry.glyph, character: character, feature: feature.tag)
            }
            let sorted = entries.sorted { $0.character < $1.character }
            let combined = feature.tag == "tnum" ? tabularFigures(in: found, characters: characters) : []
            for glyph in sorted + combined where result.count < limit && seen.insert(glyph.glyph).inserted {
                result.append(glyph)
            }
        }
        let smallCaps = result.filter { $0.group == .smallCaps }
            .sorted { smallCapOrder(of: $0.character) < smallCapOrder(of: $1.character) }
        return smallCaps + result.filter { $0.group != .smallCaps }
    }

    /// Where a small capital goes in its group: where its letter goes on the page, a capital's where its lowercase
    /// letter does, whichever feature draws it, so a and A's are together, from A to Z, then the accented ones, a
    /// capital İ's among them, then figures and signs.
    static func smallCapOrder(of character: UInt32) -> (GlyphGroup, UInt32, UInt32) {
        let group: GlyphGroup = switch GlyphGroup.of(character) ?? .graphical {
        case .uppercase: .lowercase
        case .uppercaseAccents: .lowercaseAccents
        case let other: other
        }
        let lowercase = Unicode.Scalar(character).map { Array(String(Character($0)).lowercased().unicodeScalars) } ?? []
        return (group, lowercase.count == 1 ? lowercase[0].value : character, character)
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
