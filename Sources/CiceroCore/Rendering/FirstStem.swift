import CoreGraphics
import CoreText
import Foundation

/// Where a line's first letter has ink, low in the x-height, from the line's start: the left edge of its first stem,
/// clear of any serifs, their brackets and crossbars, or a round's outer edge. Compare's Overlay lines its fonts up
/// on it, so a serif font's stem stands on a sans one's, though its serif reaches further left.
public enum FirstStem {
    /// The heights that count, in fractions of the font's x-height above the baseline: the same in every letter, above
    /// the serifs at its foot and their brackets, below the crossbars of t and f at the x-height. A band in fractions
    /// of each letter's own height took some t's crossbar for its stem.
    static let band: ClosedRange<CGFloat> = 0.25...0.6

    /// nil for a line without ink.
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
                // A space has no outline: the letter after it counts.
                guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty else { continue }
                return position.x + edge(of: path, within: heights)
            }
        }
        return nil
    }

    /// The outline's ink furthest left between `heights` above the baseline, else anywhere, as in a period, with
    /// nothing there.
    static func edge(of path: CGPath, within heights: ClosedRange<CGFloat>) -> CGFloat {
        let bounds = path.boundingBoxOfPath
        let slice = CGRect(x: bounds.minX - 1, y: heights.lowerBound, width: bounds.width + 2, height: heights.upperBound - heights.lowerBound)
        let middle = path.intersection(CGPath(rect: slice, transform: nil)).boundingBoxOfPath
        return middle.isNull ? bounds.minX : middle.minX
    }
}
