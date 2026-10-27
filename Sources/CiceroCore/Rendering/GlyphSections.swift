import CoreText
import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, A to Z then the rest, the small
/// capitals its features draw for them, the ligatures, then the forms its features draw for languages, after the
/// letters they're forms of, the figures, Roman numerals among them, then punctuation, which any text has, before
/// currency and the other signs, then each other script, Greek first, as Unicode lists them, then what's in no
/// script, like the private-use glyphs, and last the accents and marks, which have no letter to sit on and are looked
/// for least. A font without Latin letters starts with its scripts (see `GlyphSection.sections`).
public enum GlyphGroup: Hashable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, smallCaps, ligatures, localizedForms, proportionalFigures, tabularFigures
    case circledFigures, romanNumerals, punctuationAndSymbols, currency, mathematicalOperators, superscripts, subscripts, fractions, numerators, denominators, ordinals
    case caseSensitiveForms, arrows
    /// A script's own characters, by its Unicode name, like "Arabic": its letters, figures, marks and punctuation, those
    /// in the Unicode blocks for it.
    case script(String)
    case graphical, diacriticalMarks, combiningMarks

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
        case .localizedForms: 6
        case .proportionalFigures: 7
        case .tabularFigures: 8
        case .circledFigures: 9
        case .romanNumerals: 10
        case .punctuationAndSymbols: 11
        case .currency: 12
        case .mathematicalOperators: 13
        case .superscripts: 14
        case .subscripts: 15
        case .fractions: 16
        case .numerators: 17
        case .denominators: 18
        case .ordinals: 19
        case .caseSensitiveForms: 20
        case .arrows: 21
        case .script: 22
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
        // Every script's currency signs together, like ฿ and ؋, and the florin ƒ, a letter to Unicode.
        if category == .currencySymbol || value == 0x192 { return .currency }
        // Letters to Unicode but signs to a type designer, like Ω OHM SIGN, K KELVIN SIGN, ℓ for litres, ℝ and the micro
        // sign µ: with ℮, not with other scripts' letters; and mathematics' letters and figures, like 𝐀, with its operators.
        if block == "Letterlike Symbols" && properties.isAlphabetic || value == 0xB5 { return .punctuationAndSymbols }
        if block == "Mathematical Alphanumeric Symbols" { return .mathematicalOperators }
        // Numbers in circles, like ①, ❶ and ㉑, and the other numbers Unicode has for numbering, like ⑴, ⒈ and 🄁, the Chinese
        // ones too, like ㊀ and ㈠, by their names, whichever block or script they're in. The letters in circles, like Ⓐ or
        // the Ⓟ some fonts have for ℗, have no numeric value and go with the symbols.
        if properties.numericType != nil, Self.isEnclosedNumber(name) { return .circledFigures }
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
        // %, ‰ and ‱ with the operators, as Glyphs has them.
        case .otherPunctuation where [0x25, 0x2030, 0x2031].contains(value):
            return .mathematicalOperators
        // The accents letters take, like U+0301, and the marks scripts share; a script's own go with its letters.
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return .combiningMarks
        case .modifierSymbol:
            // Accents set on their own, like ´, ˘ and `; ^ with the operators, as Glyphs has it, and the skin tones of
            // emoji with the symbols.
            if value == 0x5E { return .mathematicalOperators }
            return name.hasPrefix("EMOJI MODIFIER") ? .punctuationAndSymbols : .diacriticalMarks
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
    /// Whether Unicode names a number as one in a circle, in parentheses, or with a full stop or a comma after it, like
    /// CIRCLED NUMBER TWENTY ONE, PARENTHESIZED DIGIT ONE, DIGIT ONE FULL STOP or DIGIT ZERO COMMA.
    static func isEnclosedNumber(_ name: String) -> Bool {
        name.contains("CIRCLED") || name.hasPrefix("PARENTHESIZED") || name.hasSuffix(" FULL STOP") || name.hasSuffix(" COMMA")
    }

    /// The kind of a numbering character, its Unicode name without its number: "CIRCLED" for ⓪, ① and ㉑, "NEGATIVE
    /// CIRCLED" for ⓿, ❶ and ⓫, "FULL STOP" for ⒈, "CIRCLED IDEOGRAPH" for ㊀. DINGBAT is left out too: Unicode keeps
    /// ❶ to ❿ among the dingbats and ⓫ to ⓴ elsewhere, but they're one set.
    static func enclosureKind(of value: UInt32) -> String {
        let name = Unicode.Scalar(value)?.properties.name ?? ""
        return name.split(separator: " ").filter { !Self.numberWords.contains(String($0)) }.joined(separator: " ")
    }

    private static let numberWords: Set<String> = [
        "DINGBAT", "DIGIT", "NUMBER", "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN",
        "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN", "TWENTY",
        "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY",
    ]

    /// The order of the kinds' rows: those in circles, then in parentheses, then with a full stop or comma, the Chinese
    /// ones last; a kind a later Unicode adds after them, by name.
    static let enclosureKinds = [
        "CIRCLED", "NEGATIVE CIRCLED", "DOUBLE CIRCLED", "CIRCLED SANS-SERIF", "NEGATIVE CIRCLED SANS-SERIF", "PARENTHESIZED",
        "FULL STOP", "COMMA", "CIRCLED ON BLACK SQUARE", "CIRCLED IDEOGRAPH", "PARENTHESIZED IDEOGRAPH",
    ]

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
    /// point order within a group, but for superscripts, subscripts and fractions (see `valueOrder`), and the accented
    /// letters (see `letterOrder`), punctuation, symbols and operators (see `signOrder`), and Greek and Cyrillic (see
    /// `glyphsGreekOrder`), as type designers list them;
    /// private-use characters in the groups `privateUse` gives them (see `privateUseGroups`).
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
        for group in [GlyphGroup.uppercaseAccents, .lowercaseAccents] {
            buckets[group] = buckets[group]?.map { (Self.letterOrder(of: $0), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
        }
        for group in [GlyphGroup.punctuationAndSymbols, .mathematicalOperators] {
            buckets[group] = buckets[group]?.map { (Self.signOrder(of: $0), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
        }
        for group in [GlyphGroup.greek, .script("Cyrillic")] {
            buckets[group] = buckets[group]?.map { (Self.glyphsRanks[$0] ?? .max, $0) }.sorted { $0 < $1 }.map(\.1)
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

    /// Where a letter goes among others of its case, like the accented capitals: Latin, Greek and Cyrillic letters as
    /// `glyphsLatinOrder`, `glyphsGreekOrder` and `glyphsCyrillicOrder` list them: Latin's by glyph name, as Glyphs
    /// sorts them, so Á Ă Â Ä À Ā Ą Å Ã, then Æ, ß after the s's and ɛ among the e's, Greek's and Cyrillic's by
    /// alphabet, α to ω, then ά; then those GlyphsInfo has nothing for and other scripts' letters, letter by letter,
    /// each followed by its accented forms in code point order, a capital where its lowercase letter goes, after it.
    /// Characters that aren't letters go by code point. Lists of both cases, like the small capitals, go by their
    /// lowercase letters (see `FeatureGlyph.letterOrder`).
    static func letterOrder(of character: UInt32) -> (UInt32, UInt32, UInt32, Int, UInt32) {
        if let rank = glyphsRanks[character] { return (0, UInt32(rank), 0, 0, character) }
        guard let scalar = Unicode.Scalar(character), scalar.properties.isAlphabetic else { return (character, 0, character, 0, character) }
        let lowercase = String(Character(scalar)).lowercased()
        let scalars = Array(lowercase.unicodeScalars)
        let letter = scalars.count == 1 ? scalars[0].value : character
        // The letter it's a form of, the first Unicode takes it apart into, like the α of ά, and what its accents sit on.
        let base = lowercase.decomposedStringWithCompatibilityMapping.unicodeScalars.first?.value ?? letter
        let built = lowercase.decomposedStringWithCanonicalMapping.unicodeScalars.first?.value ?? letter
        let kind: UInt32 = letter == base ? 0 : built == base ? 1 : max(built, 2)
        return (base, kind, letter, character == letter ? 0 : 1, character)
    }

    /// Each character's place in `glyphsLatinOrder`, `glyphsGreekOrder` or `glyphsCyrillicOrder`.
    private static let glyphsRanks: [UInt32: Int] = Dictionary(
        (glyphsLatinOrder + glyphsGreekOrder + glyphsCyrillicOrder).unicodeScalars.filter { $0 != "\n" }.enumerated()
            .map { ($1.value, $0) }
    ) { first, _ in first }

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

    /// Where a punctuation mark, symbol or operator goes in its group, as type designers list them: punctuation,
    /// dashes, brackets, quotes, symbols, operators, then geometric shapes, each kind those `signs` has in its order,
    /// then the others by code point. So . , : ; … ! ? come before # * / \, brackets in pairs, quotes from low to
    /// high, then @ & ¶ § © ®, and + − × ÷ = ≠ with % ‰ last; code point order scattered them over Unicode's blocks,
    /// ! " # % & first.
    static func signOrder(of value: UInt32) -> (Int, Int, UInt32) {
        if let place = signPlaces[value] { return (place.kind, place.index, value) }
        return (signKind(of: value).rawValue, .max, value)
    }

    /// Whether a sign goes before another where several groups' are listed together, like the case-sensitive forms:
    /// by group, then `signOrder`.
    static func signPrecedes(_ a: UInt32, _ b: UInt32) -> Bool {
        let (x, y) = (GlyphGroup.of(a) ?? .graphical, GlyphGroup.of(b) ?? .graphical)
        return x != y ? x < y : signOrder(of: a) < signOrder(of: b)
    }

    private enum SignKind: Int { case punctuation, dash, bracket, quote, symbol, math, geometry }

    /// The signs of the Latin character sets, each kind's common ones first, as type designers list them, then the
    /// others by code point: . , : ; … ! ¡ ? ¿ · •, an inverted mark after its own; the hyphen, en and em dash, then
    /// the low lines; parentheses, then the other brackets; quotes from low to high, double before single, then
    /// guillemets and straight quotes; @ & ¶ § © ® ℗ ™ ° ′ ″ | ¦ † ‡; the arithmetic signs and comparisons, % ‰ ‱
    /// last; and shapes by kind, circles, diamonds, squares, then triangles, filled before outlined and large before
    /// small, triangles pointing up, right, down, then left.
    private static let signs: [(SignKind, String)] = [
        (.punctuation, ".,:;…!¡?¿·•#*/\\‖‼‾‿"),
        // Hyphen-minus, en and em dash, hyphen, non-breaking hyphen, figure dash, horizontal bar, then the low lines.
        (.dash, "-–—‐‑‒―_‗"),
        (.bracket, "()[]{}⟨⟩"),
        (.quote, "‚„“”‘’‛‟«»‹›\"'"),
        (.symbol, "@&¶§©®℗™°′″|¦†‡℅ℓ№℞℠℮⌀⌂\u{FFFD}"),
        (.math, "+−×÷=≠><≥≤±≈~¬^∂∅∆∏∑∕∙√∞∟∧∨∩∪∫≡⋯%‰‱"),
        (.geometry, "●○◌◉◦◆◇◊■□▪▫▲▶▼◀△▷▽◁▴▸▾◂▵▹▿◃"),
    ]

    private static let signPlaces: [UInt32: (kind: Int, index: Int)] = signs.reduce(into: [:]) { places, run in
        for (index, scalar) in run.1.unicodeScalars.enumerated() { places[scalar.value] = (run.0.rawValue, index) }
    }

    /// The kind of a sign `signs` doesn't have, by its Unicode category: an interrobang with the punctuation, a fullwidth
    /// bracket with the brackets, ∀ with the operators.
    private static func signKind(of value: UInt32) -> SignKind {
        let block = Self.block(of: value) ?? ""
        if block.hasPrefix("Geometric Shapes") { return .geometry }
        if block == "Mathematical Alphanumeric Symbols" { return .math }
        switch Unicode.Scalar(value)?.properties.generalCategory {
        case .otherPunctuation, .connectorPunctuation: return .punctuation
        case .dashPunctuation: return .dash
        case .openPunctuation, .closePunctuation: return .bracket
        case .initialPunctuation, .finalPunctuation: return .quote
        case .mathSymbol: return .math
        default: return .symbol
        }
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

    /// The character a glyph name like uni0E34 or u1F600 says, its first in a ligature's uni0066006C: uni and groups of
    /// four hex digits, or u and four to six, as the Adobe Glyph List has them. Others say none, like SF Pro's uni10003A
    /// for a symbol, whose first four digits made it the Myanmar letter U+1000.
    static func character(named name: String) -> UInt32? {
        let hex: Substring
        if name.hasPrefix("uni") {
            let digits = name.dropFirst(3)
            guard !digits.isEmpty, digits.count % 4 == 0, digits.allSatisfy(\.isHexDigit) else { return nil }
            hex = digits.prefix(4)
        } else if name.hasPrefix("u") {
            hex = name.dropFirst()
            guard (4...6).contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        } else {
            return nil
        }
        guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value), scalar.properties.generalCategory != .privateUse
        else { return nil }
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
    /// the signs a feature draws to go with them, by their own groups, then in `signOrder`'s order (see
    /// `signPrecedes`): a tabular period, then a dollar, then a plus and a percent.
    /// Roman numerals are capitals, then small ones; circled figures a run for each kind; localized forms a run for each
    /// language.
    public func runs(alternates: (UInt32) -> [FeatureAlternate]) -> [[GlyphCell]] {
        func withAlternates(_ scalars: [UInt32]) -> [GlyphCell] {
            scalars.flatMap { [GlyphCell.character($0)] + alternates($0).map(GlyphCell.alternate) }
        }
        switch group {
        case .circledFigures:
            // A row for each kind (see `GlyphGroup.enclosureKind`), from its lowest number up: ⓪ ① … ⑳ ㉑ … ㊿, then ⓿ ❶ … ⓴.
            func rank(_ kind: String) -> (Int, String) { (GlyphGroup.enclosureKinds.firstIndex(of: kind) ?? .max, kind) }
            func value(_ scalar: UInt32) -> Double { Unicode.Scalar(scalar)?.properties.numericValue ?? 0 }
            let kinds = Dictionary(grouping: scalars, by: GlyphGroup.enclosureKind(of:)).sorted { rank($0.key) < rank($1.key) }
            return kinds.map { withAlternates($0.value.sorted { (value($0), $0) < (value($1), $1) }) }
                + (glyphs.isEmpty ? [] : [glyphs.map(GlyphCell.feature)])
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
            func character(_ cell: GlyphCell) -> UInt32? {
                guard case .feature(let glyph) = cell, GlyphGroup.of(glyph.character) != nil else { return nil }
                return glyph.character
            }
            guard let a = character(left) else { return false }
            guard let b = character(right) else { return true }
            return Self.signPrecedes(a, b)
        }
        return Run.allCases.compactMap { runs[$0] }
    }

    /// The runs, each with the words above it on the page, if any: a localized form's languages, like "Bulgarian".
    public func labeledRuns(alternates: (UInt32) -> [FeatureAlternate]) -> [(label: String?, cells: [GlyphCell])] {
        let runs = runs(alternates: alternates)
        guard group == .localizedForms else { return runs.map { (nil, $0) } }
        return runs.map { run in
            guard case .feature(let glyph) = run.first else { return (nil, run) }
            return (glyph.featureName, run)
        }
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
