import CoreText
import Foundation

/// The characters a font has: those its character map (the cmap table) gives a glyph. CoreText's character set adds
/// some the font doesn't have, which it draws with another glyph: U+A789 MODIFIER LETTER COLON with the colon, U+2010
/// and U+2011 with the hyphen, U+00A0, U+202F and the line and paragraph separators with the space, and so on.
public enum CharacterMap {
    /// CoreText's character set without the characters the font's character map leaves out. CoreText's own when the
    /// font has no Unicode or symbol subtable to read, like a font with only a Mac Roman one, which CoreText maps itself.
    public static func characters(of font: CTFont) -> ScalarRanges {
        let reported = ScalarRanges(characterSet: CTFontCopyCharacterSet(font))
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableCmap), []) as Data?,
              let mapped = mapped(in: table)
        else { return reported }
        return reported.intersection(mapped)
    }

    /// The characters the table's Unicode and symbol subtables (formats 0, 4, 6, 10, 12 and 13) give a glyph other than
    /// .notdef; nil when it has none it can read. Every offset and count is checked against the table, so a damaged one
    /// gives fewer characters, never a crash.
    static func mapped(in table: Data) -> ScalarRanges? {
        let reader = GSUBSubstitutions.Reader(bytes: [UInt8](table))
        var ranges: [ClosedRange<UInt32>] = []
        var read = false

        func add(_ low: Int, _ high: Int) {
            let high = min(high, 0x10FFFF)
            guard low <= high else { return }
            if let last = ranges.last, Int(last.upperBound) + 1 == low {
                ranges[ranges.count - 1] = last.lowerBound...UInt32(high)
            } else {
                ranges.append(UInt32(low)...UInt32(high))
            }
        }

        // Header: version, then the number of encoding records: platform, encoding and offset each.
        for record in 0..<(reader.u16(2) ?? 0) {
            let at = 4 + record * 8
            guard let platform = reader.u16(at), let encoding = reader.u16(at + 2), let start = reader.u32(at + 4),
                  // Unicode, Windows symbol, Windows Unicode BMP and full repertoire.
                  platform == 0 || (platform == 3 && [0, 1, 10].contains(encoding)),
                  let format = reader.u16(start)
            else { continue }
            switch format {
            case 0:
                // 256 one-byte glyph IDs after format, length and language.
                guard reader.u16(start + 6 + 254) != nil else { continue }
                read = true
                for code in 0..<256 where reader.bytes[start + 6 + code] != 0 { add(code, code) }
            case 4:
                // Segments: end codes, a reserved pad, start codes, deltas and range offsets, segCount of each.
                guard let doubled = reader.u16(start + 6) else { continue }
                let ends = start + 14, starts = ends + doubled + 2, deltas = starts + doubled, offsets = deltas + doubled
                guard reader.u16(offsets + doubled - 2) != nil else { continue }
                read = true
                for segment in 0..<doubled / 2 {
                    guard let last = reader.u16(ends + segment * 2), let first = reader.u16(starts + segment * 2),
                          let delta = reader.u16(deltas + segment * 2), let rangeOffset = reader.u16(offsets + segment * 2),
                          first <= last
                    else { continue }
                    for code in first...last {
                        let glyph: Int
                        if rangeOffset == 0 {
                            glyph = (code + delta) & 0xFFFF
                        } else {
                            // The offset counts from where it's stored, into the glyph ID array after the segments.
                            guard let id = reader.u16(offsets + segment * 2 + rangeOffset + (code - first) * 2), id != 0 else { continue }
                            glyph = (id + delta) & 0xFFFF
                        }
                        if glyph != 0 { add(code, code) }
                    }
                }
            case 6, 10:
                // A run of glyph IDs from a first code: 16-bit header fields for format 6, 32-bit for 10.
                let wide = format == 10
                guard let first = wide ? reader.u32(start + 12) : reader.u16(start + 6),
                      let count = wide ? reader.u32(start + 16) : reader.u16(start + 8)
                else { continue }
                let glyphs = start + (wide ? 20 : 10)
                guard count == 0 || reader.u16(glyphs + (count - 1) * 2) != nil else { continue }
                read = true
                for index in 0..<count where reader.u16(glyphs + index * 2) != 0 { add(first + index, first + index) }
            case 12, 13:
                // Groups of start code, end code and glyph ID, 32 bits each. Format 12 counts the glyph up from the
                // start code; 13 gives the whole group the one glyph.
                guard let count = reader.u32(start + 12), reader.u32(start + 16 + count * 12 - 4) != nil || count == 0 else { continue }
                read = true
                for group in 0..<count {
                    let at = start + 16 + group * 12
                    guard let first = reader.u32(at), let last = reader.u32(at + 4), let glyph = reader.u32(at + 8),
                          first <= last
                    else { continue }
                    if glyph != 0 {
                        add(first, last)
                    } else if format == 12 {
                        add(first + 1, last)
                    }
                }
            default:
                // Format 14 lists variation sequences, not characters; 2 and 8 hold no Unicode.
                continue
            }
        }
        return read ? ScalarRanges(ranges) : nil
    }
}
