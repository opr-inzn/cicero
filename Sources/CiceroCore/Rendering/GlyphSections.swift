import Foundation

/// What a face's glyphs are grouped by on its font page, in its order: the letters, A to Z then the rest, the figures,
/// then punctuation, which any text has, before currency and the other signs, then each other script, Greek first, as
/// Unicode lists them, then what's in no script, like the private-use glyphs, and last the accents and marks, which
/// have no letter to sit on and are looked for least. A font with one script and no Latin letters starts with that
/// script (see `GlyphSection.sections`).
public enum GlyphGroup: Hashable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, ligatures, proportionalFigures, tabularFigures
    case circledFigures, punctuationAndSymbols, currency, mathematicalOperators, superscripts, subscripts, fractions, numerators, denominators, ordinals
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
        case .script(let name): name
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
        case .ligatures: 4
        case .proportionalFigures: 5
        case .tabularFigures: 6
        case .circledFigures: 7
        case .punctuationAndSymbols: 8
        case .currency: 9
        case .mathematicalOperators: 10
        case .superscripts: 11
        case .subscripts: 12
        case .fractions: 13
        case .numerators: 14
        case .denominators: 15
        case .ordinals: 16
        case .caseSensitiveForms: 17
        case .arrows: 18
        case .script: 19
        case .graphical: 20
        case .diacriticalMarks: 21
        case .combiningMarks: 22
        }
    }

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
        let unicodeBlock = UnicodeBlock.containing(value)
        let block = unicodeBlock?.name ?? ""
        if block == "Alphabetic Presentation Forms" && name.contains("LIGATURE") { return .ligatures }
        // A script's own characters, those in its blocks: Arabic's letters, figures, vowel marks and comma, Greek's tonos
        // and question mark; but its currency signs, like ฿, with the others. The Coptic letters Unicode keeps in Greek's
        // block, like ϣ, go with the rest of Coptic. Latin's are listed by kind.
        if let script = unicodeBlock?.script, script != "Latin", category != .currencySymbol {
            return .script(name.hasPrefix("COPTIC ") ? "Coptic" : script)
        }
        if name.contains("SUBSCRIPT") { return .subscripts }
        if name.contains("SUPERSCRIPT") || name.hasPrefix("MODIFIER LETTER SMALL") || name.hasPrefix("MODIFIER LETTER CAPITAL") {
            return .superscripts
        }
        if name.contains("ORDINAL INDICATOR") || value == 0x2116 { return .ordinals }
        if name.contains("FRACTION") { return .fractions }
        if name.contains("ARROW") { return .arrows }
        // Figures in circles, like ① and ❶, and the blocks' other numbered ones, like ⑴ and ⒈. The letters there, like Ⓐ
        // or the Ⓟ some fonts have for ℗, go with the symbols.
        if (block.hasPrefix("Enclosed Alphanumeric") || block == "Dingbats") && properties.numericType != nil { return .circledFigures }
        // Letters to Unicode but signs to a type designer, like Ω OHM SIGN, K KELVIN SIGN, ℓ for litres and ℝ: with ℮,
        // not with other scripts' letters.
        if block == "Letterlike Symbols" && properties.isAlphabetic { return .punctuationAndSymbols }
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
        var groups = Set(buckets.keys).union(glyphs.keys).sorted()
        // A font whose letters are all in one script other than Latin, like an Arabic or a Greek one, starts with them.
        let scripts = groups.filter(\.isScript)
        if scripts.count == 1, let script = scripts.first, !groups.contains(where: { $0 < .ligatures }) {
            groups.removeAll { $0 == script }
            groups.insert(script, at: 0)
        }
        return groups.compactMap { group in
            let scalars = buckets[group] ?? [], featured = glyphs[group] ?? []
            return scalars.isEmpty && featured.isEmpty ? nil : GlyphSection(group: group, scalars: scalars, glyphs: featured)
        }
    }

    /// How many of `shown`, some or all of a font's `sections` in their order, come before the ligatures it makes: the
    /// letters, Latin's or those of the one script the font starts with, and the Ligatures group's characters, like ﬀ.
    public static func beforeLigatures(_ shown: [GlyphSection], of sections: [GlyphSection]) -> Int {
        let leading = sections.first.flatMap { $0.group.isScript ? $0.group : nil }
        let start = shown.first.map { $0.group == leading ? 1 : 0 } ?? 0
        return start + shown.dropFirst(start).prefix { $0.group <= .ligatures }.count
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
