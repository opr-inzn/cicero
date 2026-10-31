import CoreGraphics
import CoreText
import Foundation

/// A face's letters drawn small, white on black, each in a square of its own, and how wide each one's advance is, for
/// `LetterEmbedding` to look at; and a few words set in a line each, in strips (see `words`), and a few letters large
/// (see `detailLetters`).
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
    /// Words set in a line each, at the letters' size and on their baseline: the widest letters against the narrowest,
    /// and straight stems in a row, between zeros. They show how a face spaces its letters and how wide they run
    /// against each other, which the squares, one letter each, don't.
    static let words = ["0WWMMmm0", "0IIllii0"]
    /// A strip's width, in pixels; it's `size` tall. A line wider than that, as an expanded face's line of Ws, is cut
    /// off at the right.
    static let stripWidth = 384
    /// Where a line starts, in pixels from its strip's left edge.
    static let stripMargin: CGFloat = 4
    /// Letters drawn again `detailScale` times as large, each in a square `detailSize` wide, centred across by its ink on
    /// a baseline `detailBaseline` up: how their serifs, terminals and joins are drawn, which the small squares can't
    /// show. A letter taller than its square is cut off at the top.
    static let detailLetters: [Character] = ["h", "o"]
    static let detailSize = 128
    static let detailScale: CGFloat = 3
    static let detailBaseline: CGFloat = 8

    struct Drawn: Equatable {
        /// One square after the other, each `size` rows of `size` pixels from the top left, 255 where it's all ink;
        /// a letter the face hasn't is an empty square.
        var pixels: [UInt8]
        /// Each letter's advance at the size it's drawn, in squares, so 0.5 for one half as wide as its square, and
        /// 0 for a letter the face hasn't: what the squares, each letter centred by its ink, don't show, as how a
        /// monospaced face's i and m are as wide.
        var advances: [Float]
        /// One strip after the other, each `size` rows of `stripWidth` pixels from the top left, a word of `words` set in
        /// each; a letter the face hasn't is left out. Empty unless asked for.
        var strips: [UInt8]
        /// The `detailLetters` one square after the other, each `detailSize` rows of `detailSize` pixels; a letter the
        /// face hasn't is an empty square. Empty unless asked for.
        var details: [UInt8] = []
    }

    /// nil for a face with fewer than `fewest` of the letters drawn as outlines. The strips only with `strips`, and the
    /// large letters only with `details`, for a model that looks at them.
    static func draw(_ font: CTFont, strips withStrips: Bool = false, details withDetails: Bool = false) -> Drawn? {
        let font = inThousandths(font)
        let glyphs = letters.map { font.glyph(for: $0) }
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
        let x = font.glyph(for: Character("x")).flatMap { CTFontCreatePathForGlyph(font, $0, nil) }.map(\.boundingBoxOfPath.maxY)
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
        guard let strips = withStrips ? strips(font, scale: scale) : [],
              let details = withDetails ? details(font, scale: scale * detailScale) : [] else { return nil }
        return Drawn(pixels: pixels, advances: advances, strips: strips, details: details)
    }

    /// `detailLetters` at `scale`, as `draw` draws the small ones.
    private static func details(_ font: CTFont, scale: CGFloat) -> [UInt8]? {
        let area = detailSize * detailSize
        var pixels = [UInt8](repeating: 0, count: area * detailLetters.count)
        guard let context = CGContext(data: nil, width: detailSize, height: detailSize, bitsPerComponent: 8, bytesPerRow: detailSize,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data
        else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        for (position, character) in detailLetters.enumerated() {
            guard let glyph = font.glyph(for: character), let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isEmpty
            else { continue }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: detailSize, height: detailSize))
            var placed = CGAffineTransform(translationX: CGFloat(detailSize) / 2 - path.boundingBoxOfPath.midX * scale, y: detailBaseline)
                .scaledBy(x: scale, y: scale)
            guard let shape = path.copy(using: &placed) else { continue }
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(shape)
            context.fillPath()
            context.flush()
            pixels.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: position * area).copyMemory(from: data, byteCount: area) }
        }
        return pixels
    }

    /// `words` set at `scale`, each glyph where the one before it advances to: no kerning and no ligatures, nor
    /// another font's glyph for one the face hasn't.
    private static func strips(_ font: CTFont, scale: CGFloat) -> [UInt8]? {
        let area = size * stripWidth
        var pixels = [UInt8](repeating: 0, count: area * words.count)
        guard let context = CGContext(data: nil, width: stripWidth, height: size, bitsPerComponent: 8, bytesPerRow: stripWidth,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data
        else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        for (position, word) in words.enumerated() {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: stripWidth, height: size))
            let line = CGMutablePath()
            var pen = stripMargin
            for character in word {
                guard var glyph = font.glyph(for: character) else { continue }
                var placed = CGAffineTransform(translationX: pen, y: baseline).scaledBy(x: scale, y: scale)
                if let path = CTFontCreatePathForGlyph(font, glyph, &placed) { line.addPath(path) }
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
                pen += advance.width * scale
            }
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(line)
            context.fillPath()
            context.flush()
            pixels.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: position * area).copyMemory(from: data, byteCount: area) }
        }
        return pixels
    }

    /// The font at 1,000 units to the em, at its own optical size: the one its variation sets, else its axis's default.
    /// CoreText would size a font with an optical size axis to the point size, so at 1,000 every one would be its
    /// largest, display cut.
    static func inThousandths(_ font: CTFont) -> CTFont {
        let ownSize = CTFontDescriptorCreateWithAttributes([kCTFontOpticalSizeAttribute: "none"] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 1000, nil, ownSize)
    }
}
