import CoreText
import Foundation

/// One line of text laid out by CoreText, measured for layouts that share a baseline and drawn
/// into a flipped (top-left origin) context in the context's fill colour.
struct TextLine {
    let line: CTLine
    /// From the start of the line to its end, or to the furthest a glyph reaches past it.
    let width: CGFloat
    /// How far glyphs reach to the left of the line's start, like an italic's j.
    let overhang: CGFloat
    /// Above and below the baseline: the font's ascent and descent, or as far as its glyphs go beyond them, so
    /// room for the line never cuts off a descender.
    let ascent: CGFloat
    let descent: CGFloat
    /// How far its glyphs reach above the baseline.
    let inkAscent: CGFloat
    let xHeight: CGFloat
    let capHeight: CGFloat

    init(_ text: String, font: CTFont, kerning: Double) {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        // Tracking is added to the font's kerning, but a kern of 0 turns that off (see `SampleEditor.Style`).
        if kerning != 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kerning }
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        width = max(CTLineGetTypographicBounds(line, nil, nil, nil), ink.maxX.rounded(.up))
        overhang = max(0, -ink.minX.rounded(.down))
        ascent = max(CTFontGetAscent(font), ink.maxY.rounded(.up))
        descent = max(CTFontGetDescent(font), -ink.minY.rounded(.down))
        inkAscent = ink.maxY.rounded(.up)
        xHeight = CTFontGetXHeight(font)
        capHeight = CTFontGetCapHeight(font)
    }

    func draw(in context: CGContext, baselineAt origin: CGPoint, color: CGColor) {
        context.saveGState()
        context.setFillColor(color)
        context.textMatrix = .identity
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
