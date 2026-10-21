import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, A to Z then the rest, the figures,
/// then punctuation, which any text has, before currency and the other signs, then Greek, which a type designer lists
/// after Latin, the letters, marks and signs of other scripts, and last the accents and marks, which have no letter
/// to sit on and are looked for least.
public enum GlyphGroup: Int, CaseIterable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, ligatures, proportionalFigures, tabularFigures
    case circledFigures, punctuationAndSymbols, currency, mathematicalOperators, superscripts, subscripts, fractions, numerators, denominators, ordinals
    case caseSensitiveForms, arrows, greek, graphical, diacriticalMarks, combiningMarks

    public var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .uppercaseAccents: "Uppercase Accents"
        case .lowercaseAccents: "Lowercase Accents"
        case .ligatures: "Ligatures"
        case .proportionalFigures: "Proportional Figures"
        case .tabularFigures: "Tabular Figures"
        case .circledFigures: "Circled Figures"
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
        case .greek: "Greek"
        case .graphical: "Graphical"
        case .diacriticalMarks: "Diacritical Marks"
        case .combiningMarks: "Combining Marks"
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
        // Figures in circles, like ① and ❶, and the blocks' other numbered ones, like ⑴ and ⒈. The letters there, like Ⓐ
        // or the Ⓟ some fonts have for ℗, go with the symbols.
        if (block.hasPrefix("Enclosed Alphanumeric") || block == "Dingbats") && properties.numericType != nil { return .circledFigures }
        // Letters to Unicode but signs to a type designer, like Ω OHM SIGN, K KELVIN SIGN, ℓ for litres and ℝ: with ℮,
        // not with other scripts' letters.
        if block == "Letterlike Symbols" && properties.isAlphabetic { return .punctuationAndSymbols }
        // Greek's letters with its own accents and punctuation, like the tonos ΄ and the ano teleia ·; not the Coptic
        // letters Unicode keeps in its block, like ϣ, which go with the rest of Coptic.
        if block == "Greek and Coptic" || block == "Greek Extended" { return name.hasPrefix("COPTIC ") ? .graphical : .greek }
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

    /// The face's visible characters and the glyphs its features draw, by group, in `GlyphGroup`'s order, and in code
    /// point order within a group. Characters `isEmpty` says the font draws nothing for are left out, as spaces are (see
    /// `EmptyGlyphs`). Limits very large fonts to a sensible number of characters from each Unicode block.
    public static func sections(for coverage: ScalarRanges, features: [FeatureGlyph] = [],
                                leavingOut isEmpty: (UInt32) -> Bool = { _ in false }) -> [GlyphSection] {
        var buckets: [GlyphGroup: [UInt32]] = [:]
        var perBlock: [String: Int] = [:]
        for range in coverage.ranges {
            for value in range {
                guard let group = GlyphGroup.of(value) else { continue }
                let block = Self.block(of: value) ?? ""
                guard perBlock[block, default: 0] < limit, !isEmpty(value) else { continue }
                perBlock[block, default: 0] += 1
                buckets[group, default: []].append(value)
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
    /// the signs a feature draws to go with them, by their own groups, then code point: a tabular percent, then a dollar.
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
                return [group.rawValue, Int(glyph.character)]
            }
            return place(left).lexicographicallyPrecedes(place(right))
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
