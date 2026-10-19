import CoreGraphics
import CoreText
import Foundation

/// A face's letters drawn small, white on black, each in a square of its own, and how wide each one's advance is, for
/// `LetterEmbedding` to look at.
/// Every face has the same letters in the same squares, its baseline at the same height and its x-height as tall
/// (its capitals no taller than `largestCapHeight`), so that what differs is how they're drawn. Drawn from their
/// outlines, without hinting. Needs nothing but CoreText, so that scripts/embedding/render-letters.swift draws the
/// fonts the model learns from with this same code.
enum LetterImages {
    /// The letters, in the order of the squares.
    static let letters: [Character] = ["H", "O", "R", "A", "a", "e", "g", "n", "o", "s", "t", "y", "f", "k", "2", "5"]
    /// A square's side, in pixels.
    static let size = 64
    /// The baseline's height above a square's bottom edge, in pixels.
    static let baseline: CGFloat = 18
    /// How tall the x-height is drawn, in pixels, unless the capitals would be taller than `largestCapHeight`.
    static let xHeight: CGFloat = 20
    static let largestCapHeight: CGFloat = 40
    /// Fewer letters than this drawn, and the face hasn't enough of the Latin alphabet to say what it looks like.
    static let fewest = 8

    struct Drawn: Equatable {
        /// One square after the other, each `size` rows of `size` pixels from the top left, 255 where it's all ink;
        /// a letter the face hasn't is an empty square.
        var pixels: [UInt8]
        /// Each letter's advance at the size it's drawn, in squares, so 0.5 for one half as wide as its square, and
        /// 0 for a letter the face hasn't: what the squares, each letter centred by its ink, don't show, as how a
        /// monospaced face's i and m are as wide.
        var advances: [Float]
    }

    /// nil for a face with fewer than `fewest` of the letters drawn as outlines.
    static func draw(_ font: CTFont) -> Drawn? {
        let font = inThousandths(font)
        let glyphs = letters.map { glyph(font, $0) }
        let paths = glyphs.map { glyph -> CGPath? in
            guard let glyph, let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isEmpty else { return nil }
            return path
        }
        guard paths.count(where: { $0 != nil }) >= fewest else { return nil }
        func height(_ character: Character) -> CGFloat? {
            guard let path = paths[letters.firstIndex(of: character)!] else { return nil }
            let top = path.boundingBoxOfPath.maxY
            return top > 0 ? top : nil
        }
        let x = glyph(font, "x").flatMap { CTFontCreatePathForGlyph(font, $0, nil) }.map(\.boundingBoxOfPath.maxY)
        guard let xHeight = [x, CTFontGetXHeight(font), height("n"), height("o")].compactMap({ $0 }).first(where: { $0 > 0 }),
              let capHeight = [height("H"), CTFontGetCapHeight(font), xHeight / 0.7].compactMap({ $0 }).first(where: { $0 > 0 })
        else { return nil }
        let scale = min(Self.xHeight / xHeight, largestCapHeight / capHeight)

        let area = size * size
        var pixels = [UInt8](repeating: 0, count: area * letters.count)
        var advances = [Float](repeating: 0, count: letters.count)
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data
        else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        for (position, path) in paths.enumerated() {
            guard let path, var glyph = glyphs[position] else { continue }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            advances[position] = Float(advance.width * scale / CGFloat(size))
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // Centred across by its ink, on the baseline.
            var placed = CGAffineTransform(translationX: CGFloat(size) / 2 - path.boundingBoxOfPath.midX * scale, y: baseline)
                .scaledBy(x: scale, y: scale)
            guard let shape = path.copy(using: &placed) else { continue }
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(shape)
            context.fillPath()
            context.flush()
            pixels.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: position * area).copyMemory(from: data, byteCount: area) }
        }
        return Drawn(pixels: pixels, advances: advances)
    }

    /// The font at 1,000 units to the em, at its own optical size: the one its variation sets, else its axis's default.
    /// CoreText would size a font with an optical size axis to the point size, so at 1,000 every one would be its
    /// largest, display cut.
    static func inThousandths(_ font: CTFont) -> CTFont {
        let ownSize = CTFontDescriptorCreateWithAttributes([kCTFontOpticalSizeAttribute: "none"] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 1000, nil, ownSize)
    }

    private static func glyph(_ font: CTFont, _ character: Character) -> CGGlyph? {
        var characters = Array(String(character).utf16)
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1) && glyph != 0 ? glyph : nil
    }
}
