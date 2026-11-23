import CoreGraphics
import CoreText
import Foundation

public enum FirstStem {
    static let band: ClosedRange<CGFloat> = 0.25...0.6

    public static func x(in line: CTLine) -> CGFloat? {
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
            guard count > 0, let value = attributes[NSAttributedString.Key(kCTFontAttributeName as String)] else { continue }
            let font = value as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let xHeight = CTFontGetXHeight(font) > 0 ? CTFontGetXHeight(font) : CTFontGetSize(font) / 2
            let heights = xHeight * band.lowerBound...xHeight * band.upperBound
            for (glyph, position) in zip(glyphs, positions) {
                guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty else { continue }
                return position.x + edge(of: path, within: heights)
            }
        }
        return nil
    }

    static func edge(of path: CGPath, within heights: ClosedRange<CGFloat>) -> CGFloat {
        let bounds = path.boundingBoxOfPath
        let slice = CGRect(x: bounds.minX - 1, y: heights.lowerBound, width: bounds.width + 2, height: heights.upperBound - heights.lowerBound)
        let middle = path.intersection(CGPath(rect: slice, transform: nil)).boundingBoxOfPath
        return middle.isNull ? bounds.minX : middle.minX
    }
}
