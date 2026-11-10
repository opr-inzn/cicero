import CoreText
import Foundation

public enum GlyphGroup: Hashable, Comparable, Sendable {
    case uppercase, lowercase, uppercaseAccents, lowercaseAccents, smallCaps, phoneticLetters, ligatures, localizedForms
    case initialForms, medialForms, finalForms, isolatedForms, proportionalFigures, tabularFigures
    case circledFigures, romanNumerals, punctuationAndSymbols, currency, mathematicalOperators, letterlikeSymbols
    case superscripts, subscripts, fractions, numerators, denominators, ordinals
    case caseSensitiveForms, arrows
    case script(String)
    case scriptPart(String, ScriptPart)
    case stylisticSet(tag: String, name: String)
    case graphical, diacriticalMarks, combiningMarks

    public static let greek = GlyphGroup.script("Greek")

    public enum ScriptPart: Int, Sendable {
        case uppercase, lowercase, uppercaseAccents, lowercaseAccents, smallCaps, signs, caseSensitiveForms

        var title: String {
            switch self {
            case .uppercase: "Uppercase"
            case .lowercase: "Lowercase"
            case .uppercaseAccents: "Uppercase Accents"
            case .lowercaseAccents: "Lowercase Accents"
            case .smallCaps: "Small Caps"
            case .signs: "Signs and Marks"
            case .caseSensitiveForms: "Case-Sensitive Forms"
            }
        }

        var order: Int { rawValue < ScriptPart.smallCaps.rawValue ? rawValue : rawValue + 1 }
    }

    public var isScript: Bool { scriptName != nil }

    public var scriptName: String? {
        switch self {
        case .script(let name), .scriptPart(let name, _): name
        default: nil
        }
    }

    private var scriptKey: (UInt32, String, Int)? {
        switch self {
        case .script(let name): (UnicodeBlock.firstCodePoint(of: name), name, ScriptPart.smallCaps.rawValue)
        case .scriptPart(let name, let part): (UnicodeBlock.firstCodePoint(of: name), name, part.order)
        default: nil
        }
    }

    public var title: String { category == name ? name : "\(category) › \(name)" }

    public var category: String {
        switch self {
        case .uppercase, .lowercase, .uppercaseAccents, .lowercaseAccents, .smallCaps, .phoneticLetters, .ligatures, .localizedForms: "Latin"
        case .proportionalFigures, .tabularFigures, .fractions, .superscripts, .subscripts, .numerators, .denominators, .ordinals,
             .circledFigures, .romanNumerals: "Figures"
        case .punctuationAndSymbols, .currency, .mathematicalOperators, .letterlikeSymbols, .arrows, .caseSensitiveForms: "Symbols"
        case .initialForms, .medialForms, .finalForms, .isolatedForms, .stylisticSet: "Forms"
        case .script(let name), .scriptPart(let name, _): name
        case .graphical: "Graphical"
        case .diacriticalMarks, .combiningMarks: "Marks"
        }
    }

    public var name: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .uppercaseAccents: "Uppercase Accents"
        case .lowercaseAccents: "Lowercase Accents"
        case .smallCaps: "Small Caps"
        case .phoneticLetters: "IPA"
        case .ligatures: "Ligatures"
        case .proportionalFigures: "Proportional Figures"
        case .tabularFigures: "Tabular Figures"
        case .circledFigures: "Circled Figures"
        case .romanNumerals: "Roman Numerals"
        case .punctuationAndSymbols: "Punctuation and Symbols"
        case .currency: "Currency"
        case .mathematicalOperators: "Mathematical Operators"
        case .letterlikeSymbols: "Letterlike Symbols"
        case .superscripts: "Superscript"
        case .subscripts: "Subscript"
        case .fractions: "Fractions"
        case .numerators: "Numerators"
        case .denominators: "Denominators"
        case .ordinals: "Ordinals"
        case .caseSensitiveForms: "Case-Sensitive Forms"
        case .arrows: "Arrows"
        case .script(let name): name
        case .scriptPart(_, let part): part.title
        case .stylisticSet(_, let name): name
        case .localizedForms: "Localized Forms"
        case .initialForms: "Initial Forms"
        case .medialForms: "Medial Forms"
        case .finalForms: "Final Forms"
        case .isolatedForms: "Isolated Forms"
        case .graphical: "Graphical"
        case .diacriticalMarks: "Diacritical Marks"
        case .combiningMarks: "Combining Marks"
        }
    }

    public var kind: String? {
        guard case .stylisticSet(let tag, let name) = self else { return nil }
        let standard = FeatureAlternates.name(of: tag, in: [:])
        return standard.caseInsensitiveCompare(name) == .orderedSame ? nil : standard
    }

    public static func < (left: GlyphGroup, right: GlyphGroup) -> Bool {
        if let a = left.scriptKey, let b = right.scriptKey { return a < b }
        if case .stylisticSet(let a, _) = left, case .stylisticSet(let b, _) = right { return a < b }
        return left.rank < right.rank
    }

    private var rank: Int {
        switch self {
        case .uppercase: 0
        case .lowercase: 1
        case .uppercaseAccents: 2
        case .lowercaseAccents: 3
        case .smallCaps: 4
        case .phoneticLetters: 5
        case .ligatures: 6
        case .localizedForms: 7
        case .proportionalFigures: 8
        case .tabularFigures: 9
        case .fractions: 10
        case .superscripts: 11
        case .subscripts: 12
        case .numerators: 13
        case .denominators: 14
        case .ordinals: 15
        case .circledFigures: 16
        case .romanNumerals: 17
        case .punctuationAndSymbols: 18
        case .currency: 19
        case .mathematicalOperators: 20
        case .letterlikeSymbols: 21
        case .arrows: 22
        case .caseSensitiveForms: 23
        case .initialForms: 24
        case .medialForms: 25
        case .finalForms: 26
        case .isolatedForms: 27
        case .stylisticSet: 28
        case .script, .scriptPart: 29
        case .graphical: 30
        case .diacriticalMarks: 31
        case .combiningMarks: 32
        }
    }

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
        // Letters to Unicode but signs to a type designer, like Ω OHM SIGN, K KELVIN SIGN, ℓ and the micro sign µ.
        if block == "Letterlike Symbols" && properties.isAlphabetic || value == 0xB5 {
            return properties.isMath && GlyphSection.isListedSign(value) == false ? .letterlikeSymbols : .punctuationAndSymbols
        }
        if block == "Mathematical Alphanumeric Symbols" { return .letterlikeSymbols }
        // Letters in circles, like Ⓐ, are named CIRCLED too, but have no numeric value.
        if properties.numericType != nil, Self.isEnclosedNumber(name) { return .circledFigures }
        let ownScript = UnicodeScripts.script(of: value)
        let blockScript = unicodeBlock?.script
        let script: String?, all: Bool
        if let shared = UnicodeScripts.sharing(value) {
            if let scripts {
                func letters(_ script: String) -> Int { scripts[script, default: 0] }
                let others = shared.filter { $0 != "Latin" && letters($0) > 0 }
                let most = others.max { letters($0) < letters($1) }
                if let blockScript, let most, others.contains(blockScript), letters(blockScript) * 2 >= letters(most) {
                    script = blockScript
                } else if blockScript != nil || shared.max(by: { letters($0) < letters($1) }) != "Latin" {
                    script = most ?? ownScript
                } else {
                    script = nil
                }
            } else {
                script = blockScript.flatMap { shared.contains($0) ? $0 : nil } ?? ownScript
            }
            all = blockScript != nil
        } else if let ownScript {
            script = ownScript
            all = blockScript == ownScript
        } else {
            let hasLetters = scripts.map { $0[blockScript ?? "", default: 0] > 0 } ?? true
            script = hasLetters ? blockScript : nil
            all = true
        }
        if let script, script != "Latin", all || Self.isLetterMarkOrFigure(category) && !Self.isRaisedOrLowered(name) {
            return .script(script)
        }
        if name.contains("SUBSCRIPT") { return .subscripts }
        if Self.isModifierLetter(name) { return .phoneticLetters }
        if Self.isRaisedOrLowered(name) { return .superscripts }
        if name.contains("ORDINAL INDICATOR") || value == 0x2116 { return .ordinals }
        if name.contains("FRACTION") { return .fractions }
        if (name.contains("ARROW") || name.contains("HARPOON") || block == "Arrows" || block.hasPrefix("Supplemental Arrows")) && !isMark {
            return .arrows
        }
        if name.contains("ROMAN NUMERAL") { return .romanNumerals }
        if Self.pictureBlocks.contains(block) || category == .otherSymbol && !block.hasPrefix("Geometric Shapes")
            && (properties.isEmojiPresentation || properties.isEmoji && block == "Miscellaneous Technical") {
            return .graphical
        }
        let latin = ownScript == "Latin" || block.contains("Latin") || name.hasPrefix("LATIN ")
        switch category {
        case .uppercaseLetter, .titlecaseLetter:
            return latin ? (0x41...0x5A ~= value ? .uppercase : .uppercaseAccents) : .graphical
        case .lowercaseLetter:
            guard latin else { return .graphical }
            return 0x61...0x7A ~= value ? .lowercase : Self.isPhonetic(value, named: name, in: block) ? .phoneticLetters : .lowercaseAccents
        case .otherLetter:
            guard latin else { return .punctuationAndSymbols }
            return Self.isPhonetic(value, named: name, in: block) ? .phoneticLetters : .lowercaseAccents
        case .decimalNumber:
            return .proportionalFigures
        case .mathSymbol:
            return value == 0x7C || block == "Geometric Shapes" ? .punctuationAndSymbols : .mathematicalOperators
        case .otherPunctuation where [0x25, 0x2030, 0x2031].contains(value):
            return .mathematicalOperators
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return .combiningMarks
        case .modifierSymbol:
            if value == 0x5E { return .mathematicalOperators }
            return .diacriticalMarks
        case .modifierLetter:
            return latin || block == "Spacing Modifier Letters" || block == "Modifier Tone Letters" ? .diacriticalMarks : .punctuationAndSymbols
        case .privateUse, .unassigned:
            return .graphical
        default:
            return .punctuationAndSymbols
        }
    }

    // Letters with a capital in Latin Extended-A or -B, like ɛ Ɛ, ə Ə and ɔ Ɔ, are written in African and Azerbaijani text, though Unicode keeps them with IPA.
    static func isPhonetic(_ value: UInt32, named name: String, in block: String) -> Bool {
        if name.contains("LETTER SMALL CAPITAL") { return true }
        let upper = Unicode.Scalar(value).map { Array($0.properties.uppercaseMapping.unicodeScalars).map(\.value) } ?? []
        if Self.phoneticBlocks.contains(block) { return upper.count != 1 || upper[0] == value || !(0x100...0x24F ~= upper[0]) }
        return 0x180...0x24F ~= value && upper == [value] && value != 0x237
    }

    private static let phoneticBlocks: Set<String> = [
        "IPA Extensions", "Phonetic Extensions", "Phonetic Extensions Supplement", "Latin Extended-E", "Latin Extended-F", "Latin Extended-G",
    ]

    static func isEnclosedNumber(_ name: String) -> Bool {
        name.contains("CIRCLED") || name.hasPrefix("PARENTHESIZED") || name.hasSuffix(" FULL STOP") || name.hasSuffix(" COMMA")
    }

    static func enclosureKind(of value: UInt32) -> String {
        let name = Unicode.Scalar(value)?.properties.name ?? ""
        return name.split(separator: " ").filter { !Self.numberWords.contains(String($0)) }.joined(separator: " ")
    }

    // DINGBAT too: Unicode keeps ❶ to ❿ among the dingbats and ⓫ to ⓴ elsewhere, but they're one set.
    private static let numberWords: Set<String> = [
        "DINGBAT", "DIGIT", "NUMBER", "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN",
        "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN", "TWENTY",
        "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY",
    ]

    static let enclosureKinds = [
        "CIRCLED", "NEGATIVE CIRCLED", "DOUBLE CIRCLED", "CIRCLED SANS-SERIF", "NEGATIVE CIRCLED SANS-SERIF", "PARENTHESIZED",
        "FULL STOP", "COMMA", "CIRCLED ON BLACK SQUARE", "CIRCLED IDEOGRAPH", "PARENTHESIZED IDEOGRAPH",
    ]

    static let pictureBlocks: Set<String> = [
        "Miscellaneous Symbols", "Dingbats", "Mahjong Tiles", "Domino Tiles", "Playing Cards",
        "Miscellaneous Symbols and Pictographs", "Emoticons", "Ornamental Dingbats", "Transport and Map Symbols",
        "Supplemental Symbols and Pictographs", "Chess Symbols", "Symbols and Pictographs Extended-A",
    ]

    static func isModifierLetter(_ name: String) -> Bool {
        name.hasPrefix("MODIFIER LETTER SMALL") || name.hasPrefix("MODIFIER LETTER CAPITAL")
    }

    private static func isRaisedOrLowered(_ name: String) -> Bool {
        name.contains("SUBSCRIPT") || name.contains("SUPERSCRIPT") || name.hasPrefix("MODIFIER LETTER SMALL")
            || name.hasPrefix("MODIFIER LETTER CAPITAL")
    }

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

public enum GlyphCell: Hashable, Sendable {
    case character(UInt32)
    case feature(FeatureGlyph)
    case alternate(FeatureAlternate)

    public var isAlternate: Bool {
        switch self {
        case .character: false
        case .feature(let glyph): glyph.isAlternate
        case .alternate(let alternate): !alternate.isFigureStyle
        }
    }
}

public struct PrivateUseNames: Sendable {
    let groups: [UInt32: GlyphGroup]
    let characters: [UInt32: UInt32]

    public static let none = PrivateUseNames(groups: [:], characters: [:])

    public subscript(value: UInt32) -> GlyphGroup? { groups[value] }
}

public struct GlyphSection: Identifiable, Sendable {
    public let group: GlyphGroup
    public let scalars: [UInt32]
    public let glyphs: [FeatureGlyph]
    public var title: String { group.title }
    public var category: String { group.category }
    public var name: String { group.name }
    public var kind: String? { group.kind }
    public var id: GlyphGroup { group }

    public init(group: GlyphGroup, scalars: [UInt32], glyphs: [FeatureGlyph] = []) {
        self.group = group
        self.scalars = scalars
        self.glyphs = glyphs
    }

    public static func sections(for coverage: ScalarRanges, features: [FeatureGlyph] = [], privateUse: PrivateUseNames = .none,
                                leavingOut isEmpty: (UInt32) -> Bool = { _ in false }) -> [GlyphSection] {
        var buckets: [GlyphGroup: [UInt32]] = [:]
        let scripts = GlyphGroup.scripts(of: coverage)
        for range in coverage.ranges {
            for value in range {
                guard let group = privateUse[value] ?? GlyphGroup.of(value, in: scripts), !isEmpty(value) else { continue }
                buckets[group, default: []].append(value)
            }
        }
        for (group, values) in buckets {
            let bases = values.map { privateUse.characters[$0] ?? $0 }
            guard case .script(let script) = group, Self.hasBothCases(bases) else { continue }
            buckets[group] = nil
            for (value, base) in zip(values, bases) { buckets[.scriptPart(script, Self.part(of: base, in: script)), default: []].append(value) }
        }
        func smallCaps(of character: UInt32) -> GlyphGroup { ofScript(.smallCaps, character, .smallCaps) }
        func ofScript(_ group: GlyphGroup, _ character: UInt32, _ part: GlyphGroup.ScriptPart) -> GlyphGroup {
            (GlyphGroup.of(character)?.scriptName).map { .scriptPart($0, part) } ?? group
        }
        if let values = buckets.removeValue(forKey: .smallCaps) {
            for value in values { buckets[smallCaps(of: privateUse.characters[value] ?? value), default: []].append(value) }
        }
        func ordered<Key>(_ values: [UInt32], by key: (UInt32) -> Key, _ precedes: (Key, Key) -> Bool) -> [UInt32] {
            values.map { value in
                let base = privateUse.characters[value] ?? value
                return (key: key(base), base: base, form: base == value ? 0 : 1, value: value)
            }
            .sorted { a, b in a.base != b.base ? precedes(a.key, b.key) : (a.form, a.value) < (b.form, b.value) }
            .map(\.value)
        }
        for (group, values) in buckets {
            switch group {
            case .superscripts, .subscripts, .numerators, .denominators, .fractions:
                buckets[group] = ordered(values, by: { Self.valueOrder(of: $0, in: group) }, <)
            case .phoneticLetters:
                buckets[group] = ordered(values, by: { (value: UInt32) -> (Int, Int, Double, UInt32, UInt32, UInt32) in
                    guard Self.isModifier(value) else {
                        let order = Self.letterOrder(of: value)
                        return (0, 0, 0, order.0, order.1, order.2)
                    }
                    let order = Self.valueOrder(of: value, in: .superscripts)
                    return (1, order.0, order.1, 0, 0, value)
                }, <)
            case .uppercaseAccents, .lowercaseAccents, .smallCaps, .scriptPart:
                buckets[group] = ordered(values, by: Self.letterOrder, <)
            case .punctuationAndSymbols, .mathematicalOperators:
                buckets[group] = ordered(values, by: Self.signOrder, <)
            case .letterlikeSymbols:
                buckets[group] = ordered(values, by: Self.letterlikeOrder, <)
            case .greek, .script("Cyrillic"):
                buckets[group] = ordered(values, by: { (Self.glyphsRanks[$0] ?? .max, $0) }, <)
            case .graphical:
                buckets[group] = ordered(values, by: { (Unicode.Scalar($0)?.properties.generalCategory == .privateUse ? 1 : 0, $0) }, <)
            default:
                if values.contains(where: { privateUse.characters[$0] != nil }) { buckets[group] = ordered(values, by: { $0 }, <) }
            }
        }
        let glyphs = Dictionary(grouping: features) { glyph in
            switch glyph.group {
            case .smallCaps: smallCaps(of: glyph.character)
            case .caseSensitiveForms: ofScript(.caseSensitiveForms, glyph.character, .caseSensitiveForms)
            case let group: group
            }
        }
        var groups = Set(buckets.keys).union(glyphs.keys).sorted()
        if !groups.contains(where: { $0 < .smallCaps }) {
            var sizes: [String: Int] = [:]
            for group in groups { if let script = group.scriptName { sizes[script, default: 0] += buckets[group]?.count ?? 0 } }
            let main = sizes.max { a, b in a.value != b.value ? a.value < b.value : GlyphGroup.script(b.key) < .script(a.key) }?.key
            let scripts = groups.filter(\.isScript)
            groups = scripts.filter { $0.scriptName == main } + scripts.filter { $0.scriptName != main } + groups.filter { !$0.isScript }
        }
        return groups.compactMap { group in
            let scalars = buckets[group] ?? [], featured = glyphs[group] ?? []
            return scalars.isEmpty && featured.isEmpty ? nil : GlyphSection(group: group, scalars: scalars, glyphs: featured)
        }
    }

    private static func hasBothCases(_ values: [UInt32]) -> Bool {
        let categories = Set(values).compactMap { Unicode.Scalar($0)?.properties.generalCategory }
        return categories.count { $0 == .lowercaseLetter } >= 10 && categories.count { $0 == .uppercaseLetter || $0 == .titlecaseLetter } >= 10
    }

    private static func part(of value: UInt32, in script: String) -> GlyphGroup.ScriptPart {
        guard let scalar = Unicode.Scalar(value) else { return .signs }
        let basic: Bool = switch script {
        case "Greek": (0x391...0x3A9 ~= value || 0x3B1...0x3C9 ~= value) && value != 0x3C2
        case "Cyrillic": 0x410...0x44F ~= value
        default: String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars.count == 1
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .titlecaseLetter: return basic ? .uppercase : .uppercaseAccents
        case .lowercaseLetter: return basic ? .lowercase : .lowercaseAccents
        default: return .signs
        }
    }

    static func letterOrder(of character: UInt32) -> (UInt32, UInt32, UInt32, Int, UInt32) {
        if let rank = glyphsRanks[character] { return (0, UInt32(rank), 0, 0, character) }
        guard let scalar = Unicode.Scalar(character), scalar.properties.isAlphabetic else { return (character, 0, character, 0, character) }
        let lowercase = String(Character(scalar)).lowercased()
        let scalars = Array(lowercase.unicodeScalars)
        let letter = scalars.count == 1 ? scalars[0].value : character
        let base = lowercase.decomposedStringWithCompatibilityMapping.unicodeScalars.first?.value ?? letter
        let built = lowercase.decomposedStringWithCanonicalMapping.unicodeScalars.first?.value ?? letter
        let kind: UInt32 = letter == base ? 0 : built == base ? 1 : max(built, 2)
        return (base, kind, letter, character == letter ? 0 : 1, character)
    }

    private static let glyphsRanks: [UInt32: Int] = Dictionary(
        (glyphsLatinOrder + glyphsGreekOrder + glyphsCyrillicOrder).unicodeScalars.filter { $0 != "\n" }.enumerated()
            .map { ($1.value, $0) }
    ) { first, _ in first }

    static func valueOrder(of value: UInt32, in group: GlyphGroup) -> (Int, Double, UInt32) {
        // Unicode keeps ¹ ² ³ and ¼ ½ ¾ in Latin-1 and the others in blocks of their own, so code point order alone scatters them.
        let properties = Unicode.Scalar(value)?.properties
        if group == .fractions {
            if value == 0x2044 { return (0, 0, value) }
            return properties?.numericValue.map { (1, $0, value) } ?? (2, 0, value)
        }
        if let number = properties?.numericValue, properties?.numericType == .digit || properties?.numericType == .decimal {
            return (0, number, value)
        }
        let base = Unicode.Scalar(value).flatMap { String(Character($0)).decomposedStringWithCompatibilityMapping.unicodeScalars.first?.value } ?? value
        if properties?.isAlphabetic != true {
            let (kind, index, _) = signOrder(of: base)
            return (1, Double(kind) * 1e8 + (index == .max ? 1e7 + Double(base) : Double(index)), value)
        }
        let order = letterOrder(of: base)
        let plain = 0x61...0x7A ~= (String(Character(Unicode.Scalar(base)!)).lowercased().unicodeScalars.first?.value ?? base)
        return (plain ? 2 : 3, order.0 == 0 ? Double(order.1) : 1e7 + Double(order.0) * 4 + Double(min(order.1, 3)), value)
    }

    private static let letterStyles = [
        "BOLD", "ITALIC", "BOLD ITALIC", "SCRIPT", "BOLD SCRIPT", "FRAKTUR", "DOUBLE-STRUCK", "BOLD FRAKTUR", "SANS-SERIF", "SANS-SERIF BOLD",
        "SANS-SERIF ITALIC", "SANS-SERIF BOLD ITALIC", "MONOSPACE", "DOUBLE-STRUCK ITALIC",
    ]

    private static let letterStyleWords = Set(letterStyles.flatMap { $0.split(separator: " ") })

    // Unicode names ℌ BLACK-LETTER CAPITAL H and 𝔄 MATHEMATICAL FRAKTUR CAPITAL A: one style, which Unicode splits between two blocks.
    static func letterStyle(of value: UInt32) -> Int {
        let name = (Self.name(of: value) ?? "").replacingOccurrences(of: "MATHEMATICAL ", with: "").replacingOccurrences(of: "BLACK-LETTER", with: "FRAKTUR")
        let style = name.split(separator: " ").prefix { letterStyleWords.contains($0) }.joined(separator: " ")
        return letterStyles.firstIndex(of: style) ?? letterStyles.count
    }

    static func letterlikeOrder(of value: UInt32) -> (Int, Int, Double) {
        let category = Unicode.Scalar(value)?.properties.generalCategory
        let kind = category == .uppercaseLetter ? 0 : category == .lowercaseLetter ? 1 : 2
        return (letterStyle(of: value), kind, valueOrder(of: value, in: .superscripts).1)
    }

    static func signOrder(of value: UInt32) -> (Int, Int, UInt32) {
        if let place = signPlaces[value] { return (place.kind, place.index, value) }
        return (signKind(of: value).rawValue, .max, value)
    }

    static func signPrecedes(_ a: UInt32, _ b: UInt32) -> Bool {
        let (x, y) = (GlyphGroup.of(a) ?? .graphical, GlyphGroup.of(b) ?? .graphical)
        return x != y ? x < y : signOrder(of: a) < signOrder(of: b)
    }

    private enum SignKind: Int { case punctuation, dash, bracket, quote, symbol, math, geometry }

    private static let signs: [(SignKind, String)] = [
        (.punctuation, ".,:;…!¡?¿·•#*/\\‖‼‾‿"),
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

    static func isListedSign(_ value: UInt32) -> Bool { signPlaces[value] != nil }

    private static func signKind(of value: UInt32) -> SignKind {
        let block = Self.block(of: value) ?? ""
        if block.hasPrefix("Geometric Shapes") { return .geometry }
        if block == "Mathematical Alphanumeric Symbols" || block == "Letterlike Symbols" && Unicode.Scalar(value)?.properties.isMath == true {
            return .math
        }
        switch Unicode.Scalar(value)?.properties.generalCategory {
        case .otherPunctuation, .connectorPunctuation: return .punctuation
        case .dashPunctuation: return .dash
        case .openPunctuation, .closePunctuation: return .bracket
        case .initialPunctuation, .finalPunctuation: return .quote
        case .mathSymbol: return .math
        default: return .symbol
        }
    }

    public static func privateUseNames(in font: CTFont, coverage: ScalarRanges) -> PrivateUseNames {
        var named: [UInt32: (base: String, suffixes: [Substring], isLigature: Bool)] = [:]
        for range in coverage.ranges where range.upperBound >= 0xE000 {
            for value in range where Unicode.Scalar(value)?.properties.generalCategory == .privateUse {
                guard let glyph = font.glyph(for: value), let name = CTFontCopyNameForGlyph(font, glyph) as String? else { continue }
                let parts = name.split(separator: ".")
                guard let components = parts.first?.split(separator: "_"), let base = components.first else { continue }
                named[value] = (String(base), Array(parts.dropFirst()), components.count > 1)
            }
        }
        guard !named.isEmpty else { return .none }
        let glyphs = Dictionary(uniqueKeysWithValues: Set(named.values.map(\.base)).map { ($0, CTFontGetGlyphWithName(font, $0 as CFString)) })
        let characters = LigatureGroup.characterGlyphs(of: font, needed: Set(glyphs.values.filter { $0 != 0 }))
        var groups: [UInt32: GlyphGroup] = [:]
        var bases: [UInt32: UInt32] = [:]
        for (value, name) in named {
            guard let character = Self.character(named: name.base) ?? glyphs[name.base].flatMap({ characters[$0] }) else { continue }
            let own = GlyphGroup.of(character)
            let group: GlyphGroup?
            if let featured = name.suffixes.lazy.compactMap({ Self.suffixGroups[$0.lowercased()] }).first,
               featured != .smallCaps || Self.isLetter(character) {
                group = featured
            } else if name.isLigature, let own, [.uppercase, .lowercase, .uppercaseAccents, .lowercaseAccents, .phoneticLetters].contains(own) {
                group = .ligatures
            } else {
                group = own == .graphical ? nil : own
            }
            guard let group else { continue }
            groups[value] = group
            bases[value] = character
        }
        return PrivateUseNames(groups: groups, characters: bases)
    }

    private static func isLetter(_ character: UInt32) -> Bool {
        switch Unicode.Scalar(character)?.properties.generalCategory {
        // Not modifier letters: Unicode counts accents like ˆ as ones.
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .otherLetter: true
        default: false
        }
    }

    private static let suffixGroups: [String: GlyphGroup] = [
        "sc": .smallCaps, "smcp": .smallCaps, "c2sc": .smallCaps,
        "sups": .superscripts, "superior": .superscripts, "subs": .subscripts, "sinf": .subscripts, "inferior": .subscripts,
        "numr": .numerators, "numerator": .numerators, "dnom": .denominators, "denominator": .denominators,
    ]

    public static func privateUse(in font: CTFont, coverage: ScalarRanges, drawing glyphs: Set<CGGlyph>) -> Set<UInt32> {
        guard !glyphs.isEmpty else { return [] }
        var found: Set<UInt32> = []
        for range in coverage.ranges where range.upperBound >= 0xE000 {
            for value in range where Unicode.Scalar(value)?.properties.generalCategory == .privateUse {
                if let glyph = font.glyph(for: value), glyphs.contains(glyph) { found.insert(value) }
            }
        }
        return found
    }

    static func character(named name: String) -> UInt32? {
        let hex: Substring
        if name.hasPrefix("uni") {
            let digits = name.dropFirst(3)
            // Groups of four digits only: SF Pro's uni10003A, a symbol, would otherwise read as the Myanmar letter U+1000.
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

    public static func beforeLigatures(_ shown: [GlyphSection], of sections: [GlyphSection]) -> Int {
        let leading = Set(sections.prefix { $0.group.isScript }.map(\.group))
        let start = shown.prefix { leading.contains($0.group) }.count
        return start + shown.dropFirst(start).prefix { $0.group <= .ligatures }.count
    }

    public func runs(alternates: (UInt32) -> [FeatureAlternate]) -> [[GlyphCell]] {
        func withAlternates(_ scalars: [UInt32]) -> [GlyphCell] {
            scalars.flatMap { [GlyphCell.character($0)] + alternates($0).map(GlyphCell.alternate) }
        }
        switch group {
        case .circledFigures:
            func rank(_ kind: String) -> (Int, String) { (GlyphGroup.enclosureKinds.firstIndex(of: kind) ?? .max, kind) }
            func value(_ scalar: UInt32) -> Double { Unicode.Scalar(scalar)?.properties.numericValue ?? 0 }
            let kinds = Dictionary(grouping: scalars, by: GlyphGroup.enclosureKind(of:)).sorted { rank($0.key) < rank($1.key) }
            return kinds.map { withAlternates($0.value.sorted { (value($0), $0) < (value($1), $1) }) }
                + (glyphs.isEmpty ? [] : [glyphs.map(GlyphCell.feature)])
        case .superscripts, .subscripts, .numerators, .denominators:
            return [withAlternates(scalars), glyphs.map(GlyphCell.feature)].filter { !$0.isEmpty }
        case .phoneticLetters:
            let modifiers = scalars.filter(Self.isModifier)
            return [withAlternates(scalars.filter { !Self.isModifier($0) }) + glyphs.map(GlyphCell.feature), withAlternates(modifiers)]
                .filter { !$0.isEmpty }
        case .letterlikeSymbols:
            var runs: [[GlyphCell]] = []
            for (index, scalar) in scalars.enumerated() {
                if index == 0 || Self.letterStyle(of: scalar) != Self.letterStyle(of: scalars[index - 1]) { runs.append([]) }
                runs[runs.count - 1] += withAlternates([scalar])
            }
            return runs + (glyphs.isEmpty ? [] : [glyphs.map(GlyphCell.feature)])
        case .romanNumerals:
            let small = scalars.filter { Self.name(of: $0)?.hasPrefix("SMALL") == true }
            return [withAlternates(scalars.filter { !small.contains($0) }), withAlternates(small) + glyphs.map(GlyphCell.feature)]
                .filter { !$0.isEmpty }
        case .localizedForms:
            var runs: [[GlyphCell]] = []
            for (index, glyph) in glyphs.enumerated() {
                if index == 0 || glyph.languages != glyphs[index - 1].languages { runs.append([]) }
                runs[runs.count - 1].append(.feature(glyph))
            }
            return runs
        default:
            break
        }
        guard group == .proportionalFigures || group == .tabularFigures || group == .currency else {
            return [withAlternates(scalars) + glyphs.map(GlyphCell.feature)]
        }
        let found = scalars.map { ($0, alternates($0)) }
        let tags = found.flatMap { $0.1.flatMap(\.allFeatures) } + glyphs.flatMap(\.alongWith)
        let ownAreOldStyle = tags.contains("lnum") && !tags.contains("onum")
        enum Run: Hashable { case style([String]), signs }
        func run(of features: [String]) -> Run { .style(["lnum", "onum", "pnum"].filter(features.contains)) }
        func rank(_ run: Run) -> (Int, Int, String) {
            guard case .style(let tags) = run else { return (2, 0, "") }
            return (tags.contains("onum") || !tags.contains("lnum") && ownAreOldStyle ? 1 : 0, tags.count, tags.joined(separator: " "))
        }
        var order: [Run: [UInt32]] = [:]
        var cells: [Run: [UInt32: [GlyphCell]]] = [:]
        var strays: [Run: [GlyphCell]] = [:]
        func add(_ cell: GlyphCell, for character: UInt32, in run: Run) {
            if cells[run]?[character] != nil {
                cells[run]![character]!.append(cell)
            } else if cell.isAlternate {
                strays[run, default: []].append(cell)
            } else {
                order[run, default: []].append(character)
                cells[run, default: [:]][character] = [cell]
            }
        }
        for (scalar, list) in found {
            add(.character(scalar), for: scalar, in: run(of: []))
            for alternate in list where alternate.isFigureStyle { add(.alternate(alternate), for: scalar, in: run(of: alternate.allFeatures)) }
        }
        for glyph in glyphs where !glyph.isAlternate {
            let isFigure = GlyphGroup.of(glyph.character) == .proportionalFigures
            add(.feature(glyph), for: glyph.character, in: isFigure ? run(of: glyph.alongWith) : .signs)
        }
        for (scalar, list) in found {
            for alternate in list where !alternate.isFigureStyle { add(.alternate(alternate), for: scalar, in: run(of: alternate.allFeatures)) }
        }
        for glyph in glyphs where glyph.isAlternate {
            let isFigure = GlyphGroup.of(glyph.character) == .proportionalFigures
            add(.feature(glyph), for: glyph.character, in: isFigure ? run(of: glyph.alongWith) : .signs)
        }
        order[.signs]?.sort { a, b in
            guard GlyphGroup.of(a) != nil else { return false }
            guard GlyphGroup.of(b) != nil else { return true }
            return Self.signPrecedes(a, b)
        }
        return Set(order.keys).union(strays.keys).sorted { rank($0) < rank($1) }.compactMap { kind in
            let list = (order[kind] ?? []).flatMap { cells[kind]![$0]! } + (strays[kind] ?? [])
            return list.isEmpty ? nil : list
        }
    }

    public func labeledRuns(alternates: (UInt32) -> [FeatureAlternate]) -> [(label: String?, cells: [GlyphCell])] {
        let runs = runs(alternates: alternates)
        guard group == .localizedForms else { return runs.map { (nil, $0) } }
        return runs.map { run in
            guard case .feature(let glyph) = run.first else { return (nil, run) }
            return (glyph.featureName, run)
        }
    }

    static func isModifier(_ value: UInt32) -> Bool { GlyphGroup.isModifierLetter(name(of: value) ?? "") }

    public static func name(of scalar: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(scalar) else { return nil }
        return scalar.properties.name ?? scalar.properties.nameAlias
    }

    public static func shownName(of scalar: UInt32) -> String? {
        name(of: scalar).map { name in
            name.capitalized.split(separator: " ", omittingEmptySubsequences: false).enumerated()
                .map { $0 > 0 && smallWords.contains($1.lowercased()) ? $1.lowercased() : String($1) }
                .joined(separator: " ")
        }
    }

    private static let smallWords: Set = ["with", "and", "or", "of", "for", "to", "in", "on"]

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

    static func firstCodePoint(of script: String) -> UInt32 {
        firstCodePoints[script] ?? .max
    }

    private static let firstCodePoints: [String: UInt32] = all.reduce(into: [:]) { found, block in
        if let script = block.script, found[script] == nil { found[script] = block.range.lowerBound }
    }
}
