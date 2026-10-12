import CoreText
import Foundation

/// One line of text laid out by CoreText, measured for layouts that share a baseline and drawn
/// into a flipped (top-left origin) context in the context's fill colour.
struct TextLine {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let xHeight: CGFloat
    let capHeight: CGFloat

    init(_ text: String, font: CTFont, kerning: Double) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): kerning,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes))
        width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
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
