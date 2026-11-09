import CoreGraphics
import CoreText
import Foundation

enum LetterImages {
    static let letters: [Character] = ["H", "O", "R", "A", "a", "e", "g", "n", "o", "s", "t", "y", "f", "k", "2", "5"]
    static let size = 64
    static let baseline: CGFloat = 18
    static let xHeight: CGFloat = 20
    static let largestCapHeight: CGFloat = 40
    static let fewest = 8
    static let words = ["0WWMMmm0", "0IIllii0"]
    static let stripWidth = 384
    static let stripMargin: CGFloat = 4
    static let detailLetters: [Character] = ["h", "o"]
    static let detailSize = 128
    static let detailScale: CGFloat = 3
    static let detailBaseline: CGFloat = 8

    struct Drawn: Equatable {
        var pixels: [UInt8]
        var advances: [Float]
        var strips: [UInt8]
        var details: [UInt8] = []
    }

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

    static func inThousandths(_ font: CTFont) -> CTFont {
        // CoreText sizes a font with an optical size axis to the point size, so at 1,000 every one would be its largest, display cut.
        let ownSize = CTFontDescriptorCreateWithAttributes([kCTFontOpticalSizeAttribute: "none"] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 1000, nil, ownSize)
    }
}
