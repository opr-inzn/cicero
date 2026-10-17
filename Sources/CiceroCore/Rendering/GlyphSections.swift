import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, plain then accented, the figures,
/// then signs, symbols and accents, and last the letters, marks and signs of scripts other than Latin.
public enum GlyphGroup: Int, CaseIterable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, ligatures, proportionalFigures, tabularFigures
    case dingbatNumerals, currencyAndMath, superscriptAndSubscript, fractionsAndOrdinals, punctuationAndSymbols
    case diacriticalMarks, combiningMarks, caseSensitiveForms, arrows, global

    public var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .uppercaseAccents: "Uppercase Accents"
        case .lowercaseAccents: "Lowercase Accents"
        case .ligatures: "Ligatures"
        case .proportionalFigures: "Proportional Figures"
        case .tabularFigures: "Tabular Figures"
        case .dingbatNumerals: "Dingbat Numerals"
        case .currencyAndMath: "Currency and Mathematical Operators"
        case .superscriptAndSubscript: "Superscript and Subscript"
        case .fractionsAndOrdinals: "Fractions and Ordinals"
        case .punctuationAndSymbols: "Punctuation and Symbols"
        case .diacriticalMarks: "Diacritical Marks"
        case .combiningMarks: "Combining Marks"
        case .caseSensitiveForms: "Case Sensitive Forms"
        case .arrows: "Arrows"
        case .global: "Global"
        }
    }

    public static func < (left: GlyphGroup, right: GlyphGroup) -> Bool { left.rawValue < right.rawValue }

    /// The group a character goes in; nil for those with nothing to show, like spaces and controls.
    public static func of(_ value: UInt32) -> GlyphGroup? {
        guard let scalar = Unicode.Scalar(value) else { return nil }
        let properties = scalar.properties
        let category = properties.generalCategory
        switch category {
        case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: return nil
        default: break
        }
        let name = properties.name ?? ""
        let block = GlyphSection.block(of: value) ?? ""
        if name.contains("SUPERSCRIPT") || name.contains("SUBSCRIPT") || name.hasPrefix("MODIFIER LETTER SMALL")
            || name.hasPrefix("MODIFIER LETTER CAPITAL") {
            return .superscriptAndSubscript
        }
        if name.contains("FRACTION") || name.contains("ORDINAL INDICATOR") || value == 0x2116 { return .fractionsAndOrdinals }
        if block == "Alphabetic Presentation Forms" && name.contains("LIGATURE") { return .ligatures }
        if name.contains("ARROW") { return .arrows }
        if block.hasPrefix("Enclosed Alphanumeric") || (block == "Dingbats" && properties.numericType != nil) { return .dingbatNumerals }
        // Latin letters in other blocks too, like ə in IPA Extensions.
        let latin = block.contains("Latin") || name.hasPrefix("LATIN ")
        switch category {
        case .uppercaseLetter, .titlecaseLetter:
            return latin ? (isAccented(scalar) ? .uppercaseAccents : .uppercase) : .global
        case .lowercaseLetter:
            return latin ? (isAccented(scalar) ? .lowercaseAccents : .lowercase) : .global
        case .decimalNumber:
            return block == "Basic Latin" ? .proportionalFigures : .global
        case .currencySymbol, .mathSymbol:
            return .currencyAndMath
        case .nonspacingMark, .spacingMark, .enclosingMark:
            // The accents letters take, like U+0301; other scripts' own marks go with their letters.
            return block.hasPrefix("Combining") ? .combiningMarks : .global
        case .modifierSymbol:
            // Accents set on their own, like ´ and ˘; ^ and ` are typed as punctuation.
            return value < 0x80 ? .punctuationAndSymbols : .diacriticalMarks
        case .privateUse, .unassigned:
            return .global
        case .otherLetter, .modifierLetter:
            return block == "Spacing Modifier Letters" ? .diacriticalMarks : .global
        default:
            return .punctuationAndSymbols
        }
    }

    /// A letter with an accent, or a stroke, bar or the like through it: Á, Ł, Ø.
    static func isAccented(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.properties.name ?? "").contains(" WITH ")
            || String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars.count > 1
    }

    /// The letter an accented one is made from, for listing Á, Â and Ä together: its decomposition's first character,
    /// else the letter its name says it is ("O" in LATIN CAPITAL LETTER O WITH STROKE).
    static func base(of value: UInt32) -> UInt32 {
        guard let scalar = Unicode.Scalar(value) else { return value }
        let decomposed = String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars
        if decomposed.count > 1, let first = decomposed.first { return first.value }
        guard let name = scalar.properties.name, let letter = name.range(of: "LETTER "), let with = name.range(of: " WITH ") else { return value }
        let base = name[letter.upperBound..<with.lowerBound]
        guard base.count == 1, let character = base.unicodeScalars.first else { return value }
        return name.contains("SMALL") ? Character(character).lowercased().unicodeScalars.first!.value : character.value
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

    /// The face's visible characters and the glyphs its features draw, by group, in `GlyphGroup`'s order: in code point
    /// order within a group, but accented letters by the letter they're made from. Limits very large fonts to a
    /// sensible number of characters from each Unicode block.
    public static func sections(for coverage: ScalarRanges, features: [FeatureGlyph] = []) -> [GlyphSection] {
        var buckets: [GlyphGroup: [UInt32]] = [:]
        var perBlock: [String: Int] = [:]
        for range in coverage.ranges {
            for value in range {
                guard let group = GlyphGroup.of(value) else { continue }
                let block = Self.block(of: value) ?? ""
                guard perBlock[block, default: 0] < limit else { continue }
                perBlock[block, default: 0] += 1
                buckets[group, default: []].append(value)
            }
        }
        for group in [GlyphGroup.uppercaseAccents, .lowercaseAccents] {
            buckets[group] = buckets[group]?.map { (GlyphGroup.base(of: $0), $0) }.sorted { $0 < $1 }.map(\.1)
        }
        // By value rather than where Unicode put them (¹²³ in Latin-1, the rest in their own block): superscripts, then
        // subscripts; ordinals and the fraction slash, then the fractions.
        for group in [GlyphGroup.superscriptAndSubscript, .fractionsAndOrdinals] {
            buckets[group] = buckets[group]?.sorted { left, right in
                let a = Self.numericOrder(left), b = Self.numericOrder(right)
                return a.kind != b.kind ? a.kind < b.kind : a.value != b.value ? a.value < b.value : left < right
            }
        }
        let glyphs = Dictionary(grouping: features, by: \.group)
        return GlyphGroup.allCases.compactMap { group in
            let scalars = buckets[group] ?? [], featured = glyphs[group] ?? []
            return scalars.isEmpty && featured.isEmpty ? nil : GlyphSection(group: group, scalars: scalars, glyphs: featured)
        }
    }

    /// Where a superscript, subscript, fraction or ordinal goes among the others: its kind, then its value.
    private static func numericOrder(_ value: UInt32) -> (kind: Int, value: Double) {
        guard let scalar = Unicode.Scalar(value) else { return (9, 0) }
        let name = scalar.properties.name ?? ""
        let kind = name.contains("SUBSCRIPT") ? 1 : name.contains("FRACTION") && !name.contains("SLASH") ? 1 : 0
        return (kind, scalar.properties.numericValue ?? .infinity)
    }

    /// The Unicode name, e.g. "LATIN SMALL LETTER A WITH ACUTE".
    public static func name(of scalar: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(scalar) else { return nil }
        return scalar.properties.name ?? scalar.properties.nameAlias
    }

    /// The Unicode block a scalar is in, e.g. "Latin Extended-A".
    public static func block(of scalar: UInt32) -> String? {
        let blocks = UnicodeBlock.all
        var low = 0
        var high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].range.lowerBound <= scalar { low = mid + 1 } else { high = mid }
        }
        guard low > 0, blocks[low - 1].range.contains(scalar) else { return nil }
        return blocks[low - 1].name
    }
}
