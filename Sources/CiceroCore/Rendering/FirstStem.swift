import CoreGraphics
import CoreText
import Foundation

public enum FirstStem {
    static let band: ClosedRange<CGFloat> = 0.25...0.6
    // Of the cap height, above the lowercase band, which the hook of J reaches into in many fonts.
    static let capitalBand: ClosedRange<CGFloat> = 0.55...0.75

    public static func x(in line: CTLine, text: String) -> CGFloat? {
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
            guard count > 0, let value = attributes[NSAttributedString.Key(kCTFontAttributeName as String)] else { continue }
            let font = value as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            for (index, (glyph, position)) in zip(glyphs, positions).enumerated() {
                guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty else { continue }
                return position.x + edge(of: path, within: heights(in: font, capital: isCapital(at: indices[index], in: text)))
            }
        }
        return nil
    }

    static func heights(in font: CTFont, capital: Bool) -> ClosedRange<CGFloat> {
        let capHeight = CTFontGetCapHeight(font)
        if capital, capHeight > 0 {
            return capHeight * capitalBand.lowerBound...capHeight * capitalBand.upperBound
        }
        let xHeight = CTFontGetXHeight(font) > 0 ? CTFontGetXHeight(font) : CTFontGetSize(font) / 2
        return xHeight * band.lowerBound...xHeight * band.upperBound
    }

    static func isCapital(at index: CFIndex, in text: String) -> Bool {
        let string = text as NSString
        guard index >= 0, index < string.length else { return false }
        return string.substring(with: string.rangeOfComposedCharacterSequence(at: index)).first?.isUppercase ?? false
    }

    static func edge(of path: CGPath, within heights: ClosedRange<CGFloat>) -> CGFloat {
        let bounds = path.boundingBoxOfPath
        let slice = CGRect(x: bounds.minX - 1, y: heights.lowerBound, width: bounds.width + 2, height: heights.upperBound - heights.lowerBound)
        let middle = path.intersection(CGPath(rect: slice, transform: nil)).boundingBoxOfPath
        return middle.isNull ? bounds.minX : middle.minX
    }
}
