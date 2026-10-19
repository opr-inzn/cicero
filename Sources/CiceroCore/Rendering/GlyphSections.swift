import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, A to Z then the rest, the figures,
/// then signs, symbols and accents, and last the letters, marks and signs of scripts other than Latin.
public enum GlyphGroup: Int, CaseIterable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, ligatures, proportionalFigures, tabularFigures
    case dingbatNumerals, currency, mathematicalOperators, superscripts, subscripts, fractions, numerators, denominators, ordinals, punctuationAndSymbols
    case diacriticalMarks, combiningMarks, caseSensitiveForms, arrows, graphical

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
        case .currency: "Currency"
        case .mathematicalOperators: "Mathematical Operators"
        case .superscripts: "Superscript"
        case .subscripts: "Subscript"
        case .fractions: "Fractions"
        case .numerators: "Numerators"
        case .denominators: "Denominators"
        case .ordinals: "Ordinals"
        case .punctuationAndSymbols: "Punctuation and Symbols"
        case .diacriticalMarks: "Diacritical Marks"
        case .combiningMarks: "Combining Marks"
        case .caseSensitiveForms: "Case Sensitive Forms"
        case .arrows: "Arrows"
        case .graphical: "Graphical"
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
        if name.contains("SUBSCRIPT") { return .subscripts }
        if name.contains("SUPERSCRIPT") || name.hasPrefix("MODIFIER LETTER SMALL") || name.hasPrefix("MODIFIER LETTER CAPITAL") {
            return .superscripts
        }
        if name.contains("ORDINAL INDICATOR") || value == 0x2116 { return .ordinals }
        if name.contains("FRACTION") { return .fractions }
        if block == "Alphabetic Presentation Forms" && name.contains("LIGATURE") { return .ligatures }
        if name.contains("ARROW") { return .arrows }
        if block.hasPrefix("Enclosed Alphanumeric") || (block == "Dingbats" && properties.numericType != nil) { return .dingbatNumerals }
        // Latin letters in other blocks too, like ə in IPA Extensions.
        let latin = block.contains("Latin") || name.hasPrefix("LATIN ")
        switch category {
        // A to Z on their own; Æ, Ł, Þ and the like with the accented letters.
        case .uppercaseLetter, .titlecaseLetter:
            return latin ? (0x41...0x5A ~= value ? .uppercase : .uppercaseAccents) : .graphical
        case .lowercaseLetter:
            return latin ? (0x61...0x7A ~= value ? .lowercase : .lowercaseAccents) : .graphical
        case .decimalNumber:
            return block == "Basic Latin" ? .proportionalFigures : .graphical
        case .currencySymbol:
            return .currency
        case .mathSymbol:
            // The vertical line is typed as punctuation, with the broken bar.
            return value == 0x7C ? .punctuationAndSymbols : .mathematicalOperators
        case .nonspacingMark, .spacingMark, .enclosingMark:
            // The accents letters take, like U+0301; other scripts' own marks go with their letters.
            return block.hasPrefix("Combining") ? .combiningMarks : .graphical
        case .modifierSymbol:
            // Accents set on their own, like ´ and ˘; ^ and ` are typed as punctuation.
            return value < 0x80 ? .punctuationAndSymbols : .diacriticalMarks
        case .privateUse, .unassigned:
            return .graphical
        case .otherLetter, .modifierLetter:
            return block == "Spacing Modifier Letters" ? .diacriticalMarks : .graphical
        default:
            return .punctuationAndSymbols
        }
    }

    /// The order a type designer would list these groups' characters in, rather than where Unicode put them. For
    /// punctuation and symbols: the stops, then slashes and bars, brackets, dashes, quotes, then the signs.
    private static let orders: [GlyphGroup: [UInt32: Int]] = [
        .punctuationAndSymbols: ".,:;\u{2026}!\u{A1}?\u{BF}\u{203D}\u{B7}\u{2022}*#/\\|\u{A6}()[]{}\u{2329}\u{232A}\u{27E8}\u{27E9}-\u{AD}\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}_'\"\u{2018}\u{2019}\u{201A}\u{201B}\u{201C}\u{201D}\u{201E}\u{201F}\u{2039}\u{203A}\u{AB}\u{BB}\u{2032}\u{2033}@&\u{B6}\u{A7}\u{A9}\u{AE}\u{2117}\u{2122}\u{B0}\u{2020}\u{2021}%\u{2030}\u{2031}\u{212E}^`",
        .mathematicalOperators: "+\u{2212}\u{B1}\u{D7}\u{F7}=\u{2260}\u{2248}~\u{223C}<>\u{2264}\u{2265}\u{AC}\u{2215}\u{2219}\u{221E}\u{221A}\u{2202}\u{2206}\u{220F}\u{2211}\u{222B}\u{2205}\u{2227}\u{2228}\u{2229}\u{222A}\u{2208}\u{2209}\u{2200}\u{2203}\u{25CA}",
        .currency: "$\u{20AC}\u{A3}\u{A5}\u{A2}\u{20B9}\u{20BD}\u{20A9}\u{20BA}\u{20B4}\u{20AA}\u{20AB}\u{20A6}\u{20B1}\u{20BF}\u{E3F}\u{20A1}\u{20B5}\u{20B8}\u{20AE}\u{A4}",
    ].mapValues { list in
        Dictionary(list.unicodeScalars.enumerated().map { ($1.value, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Where a character goes in such a group: its place in the order, else after those, by kind, then code point.
    public static func order(of value: UInt32, in group: GlyphGroup) -> [Int] {
        if let index = orders[group]?[value] { return [0, index] }
        let kind: Int = switch Unicode.Scalar(value)?.properties.generalCategory {
        case .otherPunctuation: 1
        case .openPunctuation, .closePunctuation: 2
        case .dashPunctuation, .connectorPunctuation: 3
        case .initialPunctuation, .finalPunctuation: 4
        case .otherSymbol: 5
        default: 6
        }
        return [kind, Int(value)]
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

/// A cell of the font page's glyph grid: a character, a glyph a feature draws for one in a group of its own, like a
/// tabular figure, or an alternate after it.
public enum GlyphCell: Hashable, Sendable {
    case character(UInt32)
    case feature(FeatureGlyph)
    case alternate(FeatureAlternate)
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
        // By value rather than where Unicode put them (¹²³ in Latin-1, the rest in their own block), the fraction slash
        // first; letters, which have none, after.
        for group in [GlyphGroup.superscripts, .subscripts, .fractions] {
            buckets[group] = buckets[group]?.sorted { left, right in
                let a = Self.value(of: left), b = Self.value(of: right)
                return a != b ? a < b : left < right
            }
            if group == .fractions, var list = buckets[group], let slash = list.firstIndex(of: 0x2044) {
                list.insert(list.remove(at: slash), at: 0)
                buckets[group] = list
            }
        }
        for group in [GlyphGroup.punctuationAndSymbols, .mathematicalOperators, .currency] {
            buckets[group] = buckets[group]?.sorted {
                GlyphGroup.order(of: $0, in: group).lexicographicallyPrecedes(GlyphGroup.order(of: $1, in: group))
            }
        }
        let glyphs = Dictionary(grouping: features, by: \.group)
        return GlyphGroup.allCases.compactMap { group in
            let scalars = buckets[group] ?? [], featured = glyphs[group] ?? []
            return scalars.isEmpty && featured.isEmpty ? nil : GlyphSection(group: group, scalars: scalars, glyphs: featured)
        }
    }

    /// The section's cells in runs, each starting a row of its own, with `alternates` giving a character's: in most
    /// groups one run, each character followed by its alternates, then the glyphs features draw. Figures are lining
    /// ones, then old-style ones, whichever the font's own are, then their other alternates, like a slashed zero, then
    /// the signs a feature draws to go with them, like a tabular dollar, in the order of their own groups.
    public func runs(alternates: (UInt32) -> [FeatureAlternate]) -> [[GlyphCell]] {
        guard group == .proportionalFigures || group == .tabularFigures else {
            return [scalars.flatMap { [GlyphCell.character($0)] + alternates($0).map(GlyphCell.alternate) } + glyphs.map(GlyphCell.feature)]
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
            func place(_ cell: GlyphCell) -> [Int] {
                guard case .feature(let glyph) = cell, let group = GlyphGroup.of(glyph.character) else { return [Int.max] }
                return [group.rawValue] + GlyphGroup.order(of: glyph.character, in: group)
            }
            return place(left).lexicographicallyPrecedes(place(right))
        }
        return Run.allCases.compactMap { runs[$0] }
    }

    /// A character's numeric value, for sorting; letters, which have none, after.
    private static func value(of scalar: UInt32) -> Double {
        Unicode.Scalar(scalar)?.properties.numericValue ?? .infinity
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
