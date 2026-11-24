import CoreText
import Foundation

public struct EmptyGlyphs {
    private let font: CTFont
    private let inColour: Bool

    public init(font: CTFont) {
        self.font = font
        // A colour font's glyphs can have an empty outline of their own and still draw from layers or SVG.
        inColour = ["COLR", "SVG ", "CBDT"].contains { name in
            CTFontCopyTable(font, name.utf8.reduce(0) { $0 << 8 | CTFontTableTag($1) }, []) != nil
        }
    }

    public func contains(_ glyph: CGGlyph) -> Bool {
        guard !inColour else { return false }
        var glyph = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
        // An emoji's bitmap has bounds but no outline.
        guard bounds.isEmpty else { return false }
        return CTFontCreatePathForGlyph(font, glyph, nil)?.isEmpty ?? true
    }

    public func contains(character scalar: UInt32) -> Bool {
        font.glyph(for: scalar).map { contains($0) } ?? false
    }

    public func drawsNothing(for scalar: UInt32) -> Bool {
        // A font with variation sequences lists their selectors without a glyph for them.
        font.glyph(for: scalar).map { contains($0) } ?? true
    }

    public func drawn(_ scalars: ScalarRanges) -> ScalarRanges {
        guard !inColour, !scalars.isEmpty else { return scalars }
        let chunkSize = 1024
        var kept: [UInt32] = []
        var batchScalars: [UInt32] = []
        batchScalars.reserveCapacity(chunkSize)
        var units: [UniChar] = []
        units.reserveCapacity(chunkSize * 2)
        var offsets: [Int] = []
        offsets.reserveCapacity(chunkSize)

        func keep(_ scalar: UInt32) {
            if let last = kept.last, last + 1 == scalar {
                kept[kept.count - 1] = scalar
            } else {
                kept.append(scalar)
                kept.append(scalar)
            }
        }

        func flushBatch() {
            guard !batchScalars.isEmpty else { return }
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
            var toCheck: [CGGlyph] = []
            toCheck.reserveCapacity(batchScalars.count)
            var checkPositions: [Int] = []
            checkPositions.reserveCapacity(batchScalars.count)
            var keepFlags = [Bool](repeating: true, count: batchScalars.count)
            for i in batchScalars.indices {
                let glyph = glyphs[offsets[i]]
                if glyph != 0 {
                    toCheck.append(glyph)
                    checkPositions.append(i)
                }
            }
            if !toCheck.isEmpty {
                var rects = [CGRect](repeating: .zero, count: toCheck.count)
                _ = CTFontGetBoundingRectsForGlyphs(font, .horizontal, toCheck, &rects, toCheck.count)
                for j in toCheck.indices where rects[j].isEmpty {
                    if CTFontCreatePathForGlyph(font, toCheck[j], nil)?.isEmpty ?? true {
                        keepFlags[checkPositions[j]] = false
                    }
                }
            }
            for i in batchScalars.indices where keepFlags[i] {
                keep(batchScalars[i])
            }
            batchScalars.removeAll(keepingCapacity: true)
            units.removeAll(keepingCapacity: true)
            offsets.removeAll(keepingCapacity: true)
        }

        for range in scalars.ranges {
            for scalar in range {
                if Self.isInvisible(scalar) {
                    flushBatch()
                    keep(scalar)
                    continue
                }
                guard let unicode = Unicode.Scalar(scalar) else { continue }
                offsets.append(units.count)
                batchScalars.append(scalar)
                for codeUnit in unicode.utf16 { units.append(codeUnit) }
                if batchScalars.count >= chunkSize { flushBatch() }
            }
        }
        flushBatch()
        return ScalarRanges(bounds: kept)
    }

    public static func isInvisible(_ scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return true }
        let properties = character.properties
        if properties.isWhitespace || properties.isDefaultIgnorableCodePoint || scalar == 0x2800 { return true }
        // A font can leave a virama empty, as it only shows in the letters it joins, like Gondi's.
        if properties.canonicalCombiningClass == .virama { return true }
        switch properties.generalCategory {
        case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
