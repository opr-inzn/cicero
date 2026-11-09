import CoreText
import Foundation

struct TextLine {
    let line: CTLine
    let width: CGFloat
    let overhang: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let inkAscent: CGFloat

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
