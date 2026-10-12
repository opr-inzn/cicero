import Foundation

/// A face's characters grouped for the glyph grid.
public struct GlyphSection: Identifiable, Sendable {
    public let title: String
    public let scalars: [UInt32]
    public var id: String { title }

    public init(title: String, scalars: [UInt32]) {
        self.title = title
        self.scalars = scalars
    }

    public static let latin = "Latin"
    public static let numbers = "Numbers"
    public static let symbols = "Symbols & punctuation"
    public static let marks = "Combining marks"
    public static let other = "Other"
    /// Keeps the grid usable for fonts with tens of thousands of CJK characters.
    public static let limit = 6000

    /// Latin, Numbers, Symbols & punctuation, then other scripts by name, then "Other". Limits very
    /// large fonts to a sensible number of characters per section.
    public static func sections(for coverage: ScalarRanges) -> [GlyphSection] {
        var buckets: [String: [UInt32]] = [:]
        for range in coverage.ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let category = scalar.properties.generalCategory
                switch category {
                case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: continue
                default: buckets[section(of: value, category: category), default: []].append(value)
                }
            }
        }
        var titles = [latin, numbers, symbols].filter { buckets[$0] != nil }
        titles += buckets.keys.filter { ![latin, numbers, symbols, other].contains($0) }.sorted()
        if buckets[other] != nil { titles.append(other) }
        return titles.map { GlyphSection(title: $0, scalars: Array(buckets[$0]!.prefix(limit))) }
    }

    /// The Unicode name, e.g. "LATIN SMALL LETTER A WITH ACUTE".
    public static func name(of scalar: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(scalar) else { return nil }
        return scalar.properties.name ?? scalar.properties.nameAlias
    }

    // MARK: - Blocks

    private enum Kind {
        /// Letters and marks are Latin; the rest of the block sorts by category.
        case latin
        case marks
        case script(String)
        case other
    }

    private static func section(of scalar: UInt32, category: Unicode.GeneralCategory) -> String {
        let kind = block(of: scalar)
        switch kind {
        case .script(let name): return name
        case .marks: return marks
        case .other: return other
        case .latin, nil: break
        }
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark:
            return kind == nil ? symbols : latin
        case .decimalNumber, .letterNumber, .otherNumber:
            return numbers
        case .privateUse, .unassigned:
            return other
        default:
            return symbols
        }
    }

    private static func block(of scalar: UInt32) -> Kind? {
        var low = 0
        var high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].range.lowerBound <= scalar { low = mid + 1 } else { high = mid }
        }
        guard low > 0, blocks[low - 1].range.contains(scalar) else { return nil }
        return blocks[low - 1].kind
    }

    /// Unicode blocks that belong to one script. Blocks shared by many scripts (punctuation,
    /// symbols, currency…) are left out and sorted by category instead.
    private static let blocks: [(range: ClosedRange<UInt32>, kind: Kind)] = [
        (0x0041...0x005A, .latin), (0x0061...0x007A, .latin), (0x00AA...0x00AA, .latin), (0x00BA...0x00BA, .latin),
        (0x00C0...0x024F, .latin), (0x0250...0x02FF, .latin), (0x0300...0x036F, .marks),
        (0x0370...0x03FF, .script("Greek")), (0x0400...0x052F, .script("Cyrillic")), (0x0530...0x058F, .script("Armenian")),
        (0x0590...0x05FF, .script("Hebrew")), (0x0600...0x06FF, .script("Arabic")), (0x0700...0x074F, .script("Syriac")),
        (0x0750...0x077F, .script("Arabic")), (0x0780...0x07BF, .script("Thaana")), (0x07C0...0x07FF, .script("N’Ko")),
        (0x0800...0x083F, .script("Samaritan")), (0x0840...0x085F, .script("Mandaic")), (0x0860...0x086F, .script("Syriac")),
        (0x0870...0x08FF, .script("Arabic")), (0x0900...0x097F, .script("Devanagari")), (0x0980...0x09FF, .script("Bengali")),
        (0x0A00...0x0A7F, .script("Gurmukhi")), (0x0A80...0x0AFF, .script("Gujarati")), (0x0B00...0x0B7F, .script("Oriya")),
        (0x0B80...0x0BFF, .script("Tamil")), (0x0C00...0x0C7F, .script("Telugu")), (0x0C80...0x0CFF, .script("Kannada")),
        (0x0D00...0x0D7F, .script("Malayalam")), (0x0D80...0x0DFF, .script("Sinhala")), (0x0E00...0x0E7F, .script("Thai")),
        (0x0E80...0x0EFF, .script("Lao")), (0x0F00...0x0FFF, .script("Tibetan")), (0x1000...0x109F, .script("Myanmar")),
        (0x10A0...0x10FF, .script("Georgian")), (0x1100...0x11FF, .script("Hangul")), (0x1200...0x139F, .script("Ethiopic")),
        (0x13A0...0x13FF, .script("Cherokee")), (0x1400...0x167F, .script("Canadian Aboriginal")), (0x1680...0x169F, .script("Ogham")),
        (0x16A0...0x16FF, .script("Runic")), (0x1700...0x171F, .script("Tagalog")), (0x1720...0x173F, .script("Hanunoo")),
        (0x1740...0x175F, .script("Buhid")), (0x1760...0x177F, .script("Tagbanwa")), (0x1780...0x17FF, .script("Khmer")),
        (0x1800...0x18AF, .script("Mongolian")), (0x18B0...0x18FF, .script("Canadian Aboriginal")), (0x1900...0x194F, .script("Limbu")),
        (0x1950...0x197F, .script("Tai Le")), (0x1980...0x19DF, .script("New Tai Lue")), (0x19E0...0x19FF, .script("Khmer")),
        (0x1A00...0x1A1F, .script("Buginese")), (0x1A20...0x1AAF, .script("Tai Tham")), (0x1AB0...0x1AFF, .marks),
        (0x1B00...0x1B7F, .script("Balinese")), (0x1B80...0x1BBF, .script("Sundanese")), (0x1BC0...0x1BFF, .script("Batak")),
        (0x1C00...0x1C4F, .script("Lepcha")), (0x1C50...0x1C7F, .script("Ol Chiki")), (0x1C80...0x1C8F, .script("Cyrillic")),
        (0x1C90...0x1CBF, .script("Georgian")), (0x1D00...0x1DBF, .latin), (0x1DC0...0x1DFF, .marks), (0x1E00...0x1EFF, .latin),
        (0x1F00...0x1FFF, .script("Greek")), (0x20D0...0x20FF, .marks), (0x2800...0x28FF, .script("Braille")),
        (0x2C00...0x2C5F, .script("Glagolitic")), (0x2C60...0x2C7F, .latin), (0x2C80...0x2CFF, .script("Coptic")),
        (0x2D00...0x2D2F, .script("Georgian")), (0x2D30...0x2D7F, .script("Tifinagh")), (0x2D80...0x2DDF, .script("Ethiopic")),
        (0x2DE0...0x2DFF, .script("Cyrillic")), (0x2E80...0x2FFF, .script("CJK")), (0x3000...0x303F, .script("CJK")),
        (0x3040...0x309F, .script("Hiragana")), (0x30A0...0x30FF, .script("Katakana")), (0x3100...0x312F, .script("Bopomofo")),
        (0x3130...0x318F, .script("Hangul")), (0x3190...0x319F, .script("CJK")), (0x31A0...0x31BF, .script("Bopomofo")),
        (0x31C0...0x31EF, .script("CJK")), (0x31F0...0x31FF, .script("Katakana")), (0x3200...0x4DBF, .script("CJK")),
        (0x4E00...0x9FFF, .script("CJK")), (0xA000...0xA4CF, .script("Yi")), (0xA4D0...0xA4FF, .script("Lisu")),
        (0xA500...0xA63F, .script("Vai")), (0xA640...0xA69F, .script("Cyrillic")), (0xA6A0...0xA6FF, .script("Bamum")),
        (0xA720...0xA7FF, .latin), (0xA800...0xA82F, .script("Syloti Nagri")), (0xA840...0xA87F, .script("Phags-pa")),
        (0xA880...0xA8DF, .script("Saurashtra")), (0xA8E0...0xA8FF, .script("Devanagari")), (0xA900...0xA92F, .script("Kayah Li")),
        (0xA930...0xA95F, .script("Rejang")), (0xA960...0xA97F, .script("Hangul")), (0xA980...0xA9DF, .script("Javanese")),
        (0xA9E0...0xA9FF, .script("Myanmar")), (0xAA00...0xAA5F, .script("Cham")), (0xAA60...0xAA7F, .script("Myanmar")),
        (0xAA80...0xAADF, .script("Tai Viet")), (0xAAE0...0xAAFF, .script("Meetei Mayek")), (0xAB00...0xAB2F, .script("Ethiopic")),
        (0xAB30...0xAB6F, .latin), (0xAB70...0xABBF, .script("Cherokee")), (0xABC0...0xABFF, .script("Meetei Mayek")),
        (0xAC00...0xD7FF, .script("Hangul")), (0xF900...0xFAFF, .script("CJK")), (0xFB00...0xFB06, .latin),
        (0xFB13...0xFB17, .script("Armenian")), (0xFB1D...0xFB4F, .script("Hebrew")), (0xFB50...0xFDFF, .script("Arabic")),
        (0xFE00...0xFE0F, .other), (0xFE20...0xFE2F, .marks), (0xFE30...0xFE6F, .script("CJK")), (0xFE70...0xFEFF, .script("Arabic")),
        (0xFF00...0xFFEF, .script("CJK")), (0x10000...0x100FF, .script("Linear B")), (0x10140...0x1018F, .script("Greek")),
        (0x10330...0x1034F, .script("Gothic")), (0x10400...0x1044F, .script("Deseret")), (0x10800...0x1083F, .script("Cypriot")),
        (0x10900...0x1091F, .script("Phoenician")), (0x10A00...0x10A5F, .script("Kharoshthi")), (0x11000...0x1107F, .script("Brahmi")),
        (0x12000...0x1254F, .script("Cuneiform")), (0x13000...0x1345F, .script("Egyptian Hieroglyphs")), (0x16800...0x16A3F, .script("Bamum")),
        (0x1B000...0x1B16F, .script("Hiragana")), (0x1E900...0x1E95F, .script("Adlam")), (0x1EE00...0x1EEFF, .script("Arabic")),
        (0x20000...0x323AF, .script("CJK")), (0xE0100...0xE01EF, .other),
    ]
}
