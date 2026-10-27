import CoreText
import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, A to Z then the rest, the small
/// capitals its features draw for them, the figures, Roman numerals among them, then punctuation, which any text has,
/// before currency and the other signs, then each other script, Greek first, as Unicode lists them, then the forms
/// its features draw for languages, which can be of any script, then what's in no script, like the private-use glyphs,
/// and last the accents and marks, which have no letter to sit on and are looked for least. A font without Latin
/// letters starts with its scripts (see `GlyphSection.sections`).
public enum GlyphGroup: Hashable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, smallCaps, ligatures, proportionalFigures, tabularFigures
    case circledFigures, romanNumerals, punctuationAndSymbols, currency, mathematicalOperators, superscripts, subscripts, fractions, numerators, denominators, ordinals
    case caseSensitiveForms, arrows
    /// A script's own characters, by its Unicode name, like "Arabic": its letters, figures, marks and punctuation, those
    /// in the Unicode blocks for it.
    case script(String)
    case localizedForms, graphical, diacriticalMarks, combiningMarks

    public static let greek = GlyphGroup.script("Greek")

    public var isScript: Bool {
        if case .script = self { true } else { false }
    }

    public var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .uppercaseAccents: "Uppercase Accents"
        case .lowercaseAccents: "Lowercase Accents"
        case .smallCaps: "Small Caps"
        case .ligatures: "Ligatures"
        case .proportionalFigures: "Proportional Figures"
        case .tabularFigures: "Tabular Figures"
        case .circledFigures: "Circled Figures"
        case .romanNumerals: "Roman Numerals"
        case .punctuationAndSymbols: "Punctuation and Symbols"
        case .currency: "Currency"
        case .mathematicalOperators: "Mathematical Operators"
        case .superscripts: "Superscript"
        case .subscripts: "Subscript"
        case .fractions: "Fractions"
        case .numerators: "Numerators"
        case .denominators: "Denominators"
        case .ordinals: "Ordinals"
        case .caseSensitiveForms: "Case Sensitive Forms"
        case .arrows: "Arrows"
        case .script(let name): name
        case .localizedForms: "Localized Forms"
        case .graphical: "Graphical"
        case .diacriticalMarks: "Diacritical Marks"
        case .combiningMarks: "Combining Marks"
        }
    }

    /// Scripts in the order Unicode lists them, by their first block.
    public static func < (left: GlyphGroup, right: GlyphGroup) -> Bool {
        if case .script(let a) = left, case .script(let b) = right {
            return (UnicodeBlock.firstCodePoint(of: a), a) < (UnicodeBlock.firstCodePoint(of: b), b)
        }
        return left.rank < right.rank
    }

    private var rank: Int {
        switch self {
        case .uppercase: 0
        case .lowercase: 1
        case .uppercaseAccents: 2
        case .lowercaseAccents: 3
        case .smallCaps: 4
        case .ligatures: 5
        case .proportionalFigures: 6
        case .tabularFigures: 7
        case .circledFigures: 8
        case .romanNumerals: 9
        case .punctuationAndSymbols: 10
        case .currency: 11
        case .mathematicalOperators: 12
        case .superscripts: 13
        case .subscripts: 14
        case .fractions: 15
        case .numerators: 16
        case .denominators: 17
        case .ordinals: 18
        case .caseSensitiveForms: 19
        case .arrows: 20
        case .script: 21
        case .localizedForms: 22
        case .graphical: 23
        case .diacriticalMarks: 24
        case .combiningMarks: 25
        }
    }

    /// The group a character goes in, in a font with as many letters of each script as `scripts` says (see `scripts(of:)`);
    /// nil for those with nothing to show, like spaces and controls.
    public static func of(_ value: UInt32, in scripts: [String: Int]? = nil) -> GlyphGroup? {
        guard let scalar = Unicode.Scalar(value) else { return nil }
        let properties = scalar.properties
        let category = properties.generalCategory
        switch category {
        case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: return nil
        default: break
        }
        let name = properties.name ?? ""
        let unicodeBlock = UnicodeBlock.containing(value)
        let block = unicodeBlock?.name ?? ""
        let isMark = category == .nonspacingMark || category == .spacingMark || category == .enclosingMark
        if block == "Alphabetic Presentation Forms" && name.contains("LIGATURE") { return .ligatures }
        // Every script's currency signs together, like ฿ and ؋.
        if category == .currencySymbol { return .currency }
        // Letters to Unicode but signs to a type designer, like Ω OHM SIGN, K KELVIN SIGN, ℓ for litres and ℝ: with ℮,
        // not with other scripts' letters; and mathematics' letters and figures, like 𝐀, with its operators.
        if block == "Letterlike Symbols" && properties.isAlphabetic { return .punctuationAndSymbols }
        if block == "Mathematical Alphanumeric Symbols" { return .mathematicalOperators }
        // A script's own characters. In the blocks for it, all of them: Arabic's letters, figures and tatweel, Greek's tonos
        // and question mark. Elsewhere, its letters, marks and figures, like Greek's small capitals among the phonetic
        // letters, the Coptic letters in Greek's block, 々 among CJK punctuation or halfwidth katakana, but not those
        // Unicode calls superscripts or subscripts. A character several scripts share, like the danda of Devanagari,
        // Bengali and others, Arabic's comma and vowel marks, which Syriac has too, or its digits, which Thaana has, goes
        // with the one the font has the most letters of; with none of them, with its own script, if it has one, or the
        // punctuation or marks. Latin's are listed by kind, like a combining grave in a Latin font with Greek letters too.
        let ownScript = UnicodeScripts.script(of: value)
        let blockScript = unicodeBlock?.script
        let script: String?, all: Bool
        if let shared = UnicodeScripts.sharing(value) {
            if let scripts {
                func letters(_ script: String) -> Int { scripts[script, default: 0] }
                let others = shared.filter { $0 != "Latin" && letters($0) > 0 }
                let most = others.max { letters($0) < letters($1) }
                if let blockScript, let most, others.contains(blockScript), letters(blockScript) * 2 >= letters(most) {
                    // Its block's script, like Devanagari for its stress signs in a font with more Latin letters, unless the
                    // font has far more letters of another, like a Syriac font with an Arabic letter or two.
                    script = blockScript
                } else if blockScript != nil || shared.max(by: { letters($0) < letters($1) }) != "Latin" {
                    script = most ?? ownScript
                } else {
                    // Shared with Latin, which the font has the most letters of, like a combining acute in a font with Greek
                    // and Cyrillic too: with the marks or punctuation.
                    script = nil
                }
            } else {
                script = blockScript.flatMap { shared.contains($0) ? $0 : nil } ?? ownScript
            }
            // In a script's block, like the danda, all of them; elsewhere, like the CJK comma 、, only letters, marks and figures.
            all = blockScript != nil
        } else if let ownScript {
            script = ownScript
            all = blockScript == ownScript
        } else {
            // A sign every script could use in a script's block, like Greek's question mark, goes with that script; in a
            // font without its letters, like the svasti sign of Tibetan's block in a Japanese font, with the symbols.
            let hasLetters = scripts.map { $0[blockScript ?? "", default: 0] > 0 } ?? true
            script = hasLetters ? blockScript : nil
            all = true
        }
        if let script, script != "Latin", all || Self.isLetterMarkOrFigure(category) && !Self.isRaisedOrLowered(name) {
            return .script(script)
        }
        if name.contains("SUBSCRIPT") { return .subscripts }
        if Self.isRaisedOrLowered(name) { return .superscripts }
        if name.contains("ORDINAL INDICATOR") || value == 0x2116 { return .ordinals }
        if name.contains("FRACTION") { return .fractions }
        // Arrows, but not the combining ones, which are marks.
        if name.contains("ARROW") && !isMark { return .arrows }
        // Figures in circles, like ① and ❶, and the blocks' other numbered ones, like ⑴ and ⒈. The letters there, like Ⓐ
        // or the Ⓟ some fonts have for ℗, go with the symbols.
        if (block.hasPrefix("Enclosed Alphanumeric") || block == "Dingbats") && properties.numericType != nil { return .circledFigures }
        // Ⅰ to Ⅿ and ⅰ to ⅿ, and the old forms, like ↀ; Unicode has them as Latin letters or numbers.
        if name.contains("ROMAN NUMERAL") { return .romanNumerals }
        // Latin letters in other blocks too, like ə in IPA Extensions or a fullwidth Ａ.
        let latin = ownScript == "Latin" || block.contains("Latin") || name.hasPrefix("LATIN ")
        switch category {
        // A to Z on their own; Æ, Ł, Þ and the like with the accented letters.
        case .uppercaseLetter, .titlecaseLetter:
            return latin ? (0x41...0x5A ~= value ? .uppercase : .uppercaseAccents) : .graphical
        case .lowercaseLetter:
            return latin ? (0x61...0x7A ~= value ? .lowercase : .lowercaseAccents) : .graphical
        // Latin's letters without case, like the click ǀ and the glottal stop ʔ; signs that are letters to Unicode but no
        // script's, like 〆, with the symbols.
        case .otherLetter:
            return latin ? .lowercaseAccents : .punctuationAndSymbols
        // 0 to 9, and figures no script has, like the fullwidth ０; a script's own go with it.
        case .decimalNumber:
            return .proportionalFigures
        case .mathSymbol:
            // The vertical line is typed as punctuation, with the broken bar.
            return value == 0x7C ? .punctuationAndSymbols : .mathematicalOperators
        // The accents letters take, like U+0301, and the marks scripts share; a script's own go with its letters.
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return .combiningMarks
        case .modifierSymbol:
            // Accents set on their own, like ´ and ˘; ^ and ` are typed as punctuation, and the skin tones of emoji
            // go with them.
            return value < 0x80 || name.hasPrefix("EMOJI MODIFIER") ? .punctuationAndSymbols : .diacriticalMarks
        // Accents and tone letters that are letters to Unicode, like ʹ and ꜗ; others no script has, like the kana
        // repeat mark 〱, with the symbols.
        case .modifierLetter:
            return latin || block == "Spacing Modifier Letters" || block == "Modifier Tone Letters" ? .diacriticalMarks : .punctuationAndSymbols
        case .privateUse, .unassigned:
            return .graphical
        default:
            return .punctuationAndSymbols
        }
    }

    /// Whether Unicode names it a superscript or subscript, like ᵝ MODIFIER LETTER SMALL BETA or ₐ.
    private static func isRaisedOrLowered(_ name: String) -> Bool {
        name.contains("SUBSCRIPT") || name.contains("SUPERSCRIPT") || name.hasPrefix("MODIFIER LETTER SMALL")
            || name.hasPrefix("MODIFIER LETTER CAPITAL")
    }

    /// How many letters of each script a font has, like 90 of Bengali and 300 of Latin for a Bengali font with Latin too.
    public static func scripts(of coverage: ScalarRanges) -> [String: Int] {
        var found: [String: Int] = [:]
        for range in coverage.ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isAlphabetic, let script = UnicodeScripts.script(of: value) else { continue }
                found[script, default: 0] += 1
            }
        }
        return found
    }

    private static func isLetterMarkOrFigure(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }
}

/// A cell of the font page's glyph grid: a character, a glyph a feature draws for one in a group of its own, like a
/// tabular figure, or an alternate after it.
public enum GlyphCell: Hashable, Sendable {
    case character(UInt32)
    case feature(FeatureGlyph)
    case alternate(FeatureAlternate)

    /// Whether it's an alternate of the cell before it, a character's or a feature glyph's, like a small capital's.
    public var isAlternate: Bool {
        switch self {
        case .character: false
        case .feature(let glyph): glyph.isAlternate
        case .alternate: true
        }
    }
}

/// A face's glyphs in one group for the glyph grid: its characters, then the glyphs features draw in place of theirs.
public struct GlyphSection: Identifiable, Sendable {
    public let group: GlyphGroup
    public let scalars: [UInt32]
    public let glyphs: [FeatureGlyph]
    public var title: String { group.title }
    public var id: GlyphGroup { group }

    public init(group: GlyphGroup, scalars: [UInt32], glyphs: [FeatureGlyph] = []) {
        self.group = group
        self.scalars = scalars
        self.glyphs = glyphs
    }

    /// Keeps the grid usable for fonts with tens of thousands of CJK characters: as many from each Unicode block.
    public static let limit = 6000

    /// The face's visible characters and the glyphs its features draw, by group, in `GlyphGroup`'s order, and in code
    /// point order within a group, but for superscripts, subscripts and fractions (see `valueOrder`); private-use characters in the groups `privateUse` gives them (see `privateUseGroups`).
    /// Characters `isEmpty` says the font draws nothing for are left out, as spaces are (see `EmptyGlyphs`). Limits very
    /// large fonts to a sensible number of characters from each Unicode block.
    public static func sections(for coverage: ScalarRanges, features: [FeatureGlyph] = [], privateUse: [UInt32: GlyphGroup] = [:],
                                leavingOut isEmpty: (UInt32) -> Bool = { _ in false }) -> [GlyphSection] {
        var buckets: [GlyphGroup: [UInt32]] = [:]
        var perBlock: [String: Int] = [:]
        let scripts = GlyphGroup.scripts(of: coverage)
        for range in coverage.ranges {
            for value in range {
                guard let group = privateUse[value] ?? GlyphGroup.of(value, in: scripts) else { continue }
                let block = Self.block(of: value) ?? ""
                guard perBlock[block, default: 0] < limit, !isEmpty(value) else { continue }
                perBlock[block, default: 0] += 1
                buckets[group, default: []].append(value)
            }
        }
        for group in [GlyphGroup.superscripts, .subscripts, .fractions] {
            buckets[group] = buckets[group]?.sorted { Self.valueOrder(of: $0, in: group) < Self.valueOrder(of: $1, in: group) }
        }
        let glyphs = Dictionary(grouping: features, by: \.group)
        var groups = Set(buckets.keys).union(glyphs.keys).sorted()
        // A font without Latin letters, like an Arabic or a Syriac one, starts with its scripts: the one it has the most
        // letters of, then the others, like the Arabic figures of a Syriac font, in Unicode's order; its small capitals, like
        // a Greek font's, after them.
        if !groups.contains(where: { $0 < .smallCaps }) {
            let main = groups.filter(\.isScript).max { a, b in
                let (x, y) = (buckets[a]?.count ?? 0, buckets[b]?.count ?? 0)
                return x != y ? x < y : b < a
            }
            let leading = groups.filter(\.isScript).sorted { a, b in a != b && (a == main || b != main && a < b) }
            groups = leading + groups.filter { !$0.isScript }
        }
        return groups.compactMap { group in
            let scalars = buckets[group] ?? [], featured = glyphs[group] ?? []
            return scalars.isEmpty && featured.isEmpty ? nil : GlyphSection(group: group, scalars: scalars, glyphs: featured)
        }
    }

    /// Where a superscript, subscript or fraction goes in its group. Superscripts and subscripts: the figures from 0 to
    /// 9, then the signs, like ⁺, then the letters, like ʰ. Fractions: the fraction slash, then the fractions by value,
    /// ⅒ to ⅞, then any without one. Each in code point order otherwise. Unicode keeps ¹ ² ³ and ¼ ½ ¾ in Latin-1 and
    /// the others in blocks of their own, after letters like ʰ or with the slash between, so code point order alone
    /// scattered them.
    static func valueOrder(of value: UInt32, in group: GlyphGroup) -> (Int, Double, UInt32) {
        let properties = Unicode.Scalar(value)?.properties
        if group == .fractions {
            if value == 0x2044 { return (0, 0, value) }
            return properties?.numericValue.map { (1, $0, value) } ?? (2, 0, value)
        }
        if let number = properties?.numericValue, properties?.numericType == .digit || properties?.numericType == .decimal {
            return (0, number, value)
        }
        return (properties?.isAlphabetic == true ? 2 : 1, 0, value)
    }

    /// The groups of a font's private-use characters whose glyphs are named after a character, like the uni0E34.alt1 a
    /// Thai font keeps at U+F701, a sara i shifted left: that character's group, so they're listed with the script
    /// they're for rather than as Graphical. A name like uni0E34 or u1F600 says the character; another, like the a in
    /// a.alt, is the name of the glyph the font maps the character to. Those named after nothing, like a foundry's
    /// logo, aren't given one.
    public static func privateUseGroups(in font: CTFont, coverage: ScalarRanges) -> [UInt32: GlyphGroup] {
        var named: [UInt32: String] = [:]
        for range in coverage.ranges where range.upperBound >= 0xE000 {
            for value in range where Unicode.Scalar(value)?.properties.generalCategory == .privateUse {
                guard let glyph = Self.glyph(of: value, in: font), let name = CTFontCopyNameForGlyph(font, glyph) as String?,
                      let base = name.split(separator: ".").first?.split(separator: "_").first.map(String.init)
                else { continue }
                named[value] = base
            }
        }
        guard !named.isEmpty else { return [:] }
        // The glyphs the base names are names of, and the characters the font maps to those.
        let glyphs = Dictionary(uniqueKeysWithValues: Set(named.values).map { ($0, CTFontGetGlyphWithName(font, $0 as CFString)) })
        let characters = LigatureGroup.characterGlyphs(of: font, needed: Set(glyphs.values.filter { $0 != 0 }))
        return named.compactMapValues { base in
            guard let character = Self.character(named: base) ?? glyphs[base].flatMap({ characters[$0] }),
                  let group = GlyphGroup.of(character), group != .graphical
            else { return nil }
            return group
        }
    }

    /// The private-use characters a font maps to `glyphs`, like the U+F761 an older font keeps for its small capital a,
    /// which is listed with the small capitals.
    public static func privateUse(in font: CTFont, coverage: ScalarRanges, drawing glyphs: Set<CGGlyph>) -> Set<UInt32> {
        guard !glyphs.isEmpty else { return [] }
        var found: Set<UInt32> = []
        for range in coverage.ranges where range.upperBound >= 0xE000 {
            for value in range where Unicode.Scalar(value)?.properties.generalCategory == .privateUse {
                if let glyph = Self.glyph(of: value, in: font), glyphs.contains(glyph) { found.insert(value) }
            }
        }
        return found
    }

    private static func glyph(of value: UInt32, in font: CTFont) -> CGGlyph? {
        guard let scalar = Unicode.Scalar(value) else { return nil }
        var units = Array(String(Character(scalar)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) && glyphs[0] != 0 ? glyphs[0] : nil
    }

    /// The character a glyph name like uni0E34 or u1F600 says, its first in a ligature's uni0066006C.
    static func character(named name: String) -> UInt32? {
        let hex: Substring
        if name.hasPrefix("uni"), name.count >= 7 { hex = name.dropFirst(3).prefix(4) }
        else if name.hasPrefix("u"), (5...7).contains(name.count) { hex = name.dropFirst() }
        else { return nil }
        guard let value = UInt32(hex, radix: 16), Unicode.Scalar(value)?.properties.generalCategory != .privateUse else { return nil }
        return value
    }

    /// How many of `shown`, some or all of a font's `sections` in their order, come before the ligatures it makes: the
    /// letters, Latin's or those of the scripts a font without Latin starts with, the small capitals and the Ligatures
    /// group's characters, like ﬀ.
    public static func beforeLigatures(_ shown: [GlyphSection], of sections: [GlyphSection]) -> Int {
        let leading = Set(sections.prefix { $0.group.isScript }.map(\.group))
        let start = shown.prefix { leading.contains($0.group) }.count
        return start + shown.dropFirst(start).prefix { $0.group <= .ligatures }.count
    }

    /// The section's cells in runs, each starting a row of its own, with `alternates` giving a character's: in most
    /// groups one run, each character followed by its alternates, then the glyphs features draw. Figures are lining
    /// ones, then old-style ones, whichever the font's own are, then their other alternates, like a slashed zero, then
    /// the signs a feature draws to go with them, by their own groups, then code point: a tabular percent, then a dollar.
    /// Roman numerals are capitals, then small ones; localized forms a run for each language.
    public func runs(alternates: (UInt32) -> [FeatureAlternate]) -> [[GlyphCell]] {
        func withAlternates(_ scalars: [UInt32]) -> [GlyphCell] {
            scalars.flatMap { [GlyphCell.character($0)] + alternates($0).map(GlyphCell.alternate) }
        }
        switch group {
        case .romanNumerals:
            // Capitals, then small ones, like ⅰ.
            let small = scalars.filter { Self.name(of: $0)?.hasPrefix("SMALL") == true }
            return [withAlternates(scalars.filter { !small.contains($0) }), withAlternates(small) + glyphs.map(GlyphCell.feature)]
                .filter { !$0.isEmpty }
        case .localizedForms:
            // A row for each language, or each that share their forms, as `FeatureGlyph.localizedForms` lists them.
            var runs: [[GlyphCell]] = []
            for (index, glyph) in glyphs.enumerated() {
                if index == 0 || glyph.languages != glyphs[index - 1].languages { runs.append([]) }
                runs[runs.count - 1].append(.feature(glyph))
            }
            return runs
        default:
            break
        }
        guard group == .proportionalFigures || group == .tabularFigures else {
            return [withAlternates(scalars) + glyphs.map(GlyphCell.feature)]
        }
        let found = scalars.map { ($0, alternates($0)) }
        // The font's own figures are old-style when a feature offers lining ones for them, and none old-style ones.
        let tags = found.flatMap { $0.1.flatMap(\.features) } + glyphs.flatMap(\.alongWith)
        let ownAreOldStyle = tags.contains("lnum") && !tags.contains("onum")
        enum Run: Int, CaseIterable { case lining, oldStyle, alternates, signs }
        func run(of features: [String]) -> Run {
            if features.contains("onum") { return .oldStyle }
            if features.contains("lnum") { return .lining }
            if features.isEmpty { return ownAreOldStyle ? .oldStyle : .lining }
            return .alternates
        }
        var runs: [Run: [GlyphCell]] = [:]
        for (scalar, list) in found {
            runs[run(of: []), default: []].append(.character(scalar))
            for alternate in list { runs[run(of: alternate.features), default: []].append(.alternate(alternate)) }
        }
        for glyph in glyphs {
            let isFigure = GlyphGroup.of(glyph.character) == .proportionalFigures
            runs[isFigure ? run(of: glyph.alongWith) : .signs, default: []].append(.feature(glyph))
        }
        runs[.signs] = runs[.signs]?.sorted { left, right in
            func place(_ cell: GlyphCell) -> (GlyphGroup, UInt32)? {
                guard case .feature(let glyph) = cell, let group = GlyphGroup.of(glyph.character) else { return nil }
                return (group, glyph.character)
            }
            guard let a = place(left) else { return false }
            guard let b = place(right) else { return true }
            return a < b
        }
        return Run.allCases.compactMap { runs[$0] }
    }

    /// The Unicode name, e.g. "LATIN SMALL LETTER A WITH ACUTE".
    public static func name(of scalar: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(scalar) else { return nil }
        return scalar.properties.name ?? scalar.properties.nameAlias
    }

    /// The Unicode block a scalar is in, e.g. "Latin Extended-A".
    public static func block(of scalar: UInt32) -> String? {
        UnicodeBlock.containing(scalar)?.name
    }
}

extension UnicodeBlock {
    static func containing(_ scalar: UInt32) -> UnicodeBlock? {
        var low = 0
        var high = all.count
        while low < high {
            let mid = (low + high) / 2
            if all[mid].range.lowerBound <= scalar { low = mid + 1 } else { high = mid }
        }
        guard low > 0, all[low - 1].range.contains(scalar) else { return nil }
        return all[low - 1]
    }

    /// Where a script's first block starts, for listing scripts in Unicode's order.
    static func firstCodePoint(of script: String) -> UInt32 {
        firstCodePoints[script] ?? .max
    }

    private static let firstCodePoints: [String: UInt32] = all.reduce(into: [:]) { found, block in
        if let script = block.script, found[script] == nil { found[script] = block.range.lowerBound }
    }
}
