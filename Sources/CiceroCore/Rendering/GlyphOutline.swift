import CoreGraphics
import CoreText
import Foundation

/// A glyph's outline, to copy or drag out of a font page as a vector: as SVG, and as PDF, which design apps paste as
/// paths. Its frame runs from the font's descent to its ascent and across the glyph's advance, so glyphs taken from one
/// font share a baseline and keep their side bearings; it grows where the outline reaches past that, so nothing of
/// the glyph is cut off. Filled black, from the outline itself: a font's file never goes with it.
public struct GlyphOutline {
    /// The size outlines are taken at, in points: an em of 100 points, or pixels in SVG.
    public static let emSize: CGFloat = 100

    /// In the font's size, y going up from the baseline at 0.
    public let path: CGPath
    public let frame: CGRect
    /// The glyph's name in the font, like "a.ss01" or "f_i", if it has one.
    public let name: String?

    /// Nothing for a glyph without an outline: a space, or a bitmap like an emoji's.
    public init?(glyph: CGGlyph, font: CTFont) {
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty else { return nil }
        var glyph = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let metrics = CGRect(x: 0, y: -CTFontGetDescent(font), width: max(advance.width, 0), height: CTFontGetAscent(font) + CTFontGetDescent(font))
        self.path = path
        frame = metrics.union(path.boundingBox)
        name = (CTFontCopyNameForGlyph(font, glyph) as String?).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// An SVG document of the outline, as wide and high as its frame in pixels, the baseline where y is 0.
    public var svg: String {
        var data = ""
        // SVG's y goes down.
        func point(_ point: CGPoint) -> String { "\(Self.number(point.x)) \(Self.number(-point.y))" }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: data += "M\(point(points[0]))"
            case .addLineToPoint: data += "L\(point(points[0]))"
            case .addQuadCurveToPoint: data += "Q\(point(points[0])) \(point(points[1]))"
            case .addCurveToPoint: data += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
            case .closeSubpath: data += "Z"
            @unknown default: break
            }
        }
        let width = Self.number(frame.width), height = Self.number(frame.height)
        return """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="\(Self.number(frame.minX)) \(Self.number(-frame.maxY)) \(width) \(height)">
            <path d="\(data)"/>
            </svg>

            """
    }

    /// A one-page PDF of the outline, the page its frame, in points.
    public var pdf: Data {
        let data = NSMutableData()
        var page = CGRect(origin: .zero, size: frame.size)
        let info = name.map { [kCGPDFContextTitle: $0] as CFDictionary }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &page, info)
        else { return Data() }
        context.beginPDFPage(nil)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        context.addPath(path)
        // Grey black, which print documents take as black ink alone.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// "Inter Bold a.ss01.svg": the style's full name and the glyph's, or `fallback` for a glyph without a name, with
    /// what the Finder can't have in a file name replaced.
    public func fileName(style: String, fallback: String, extension: String = "svg") -> String {
        let name = "\(style) \(name ?? fallback)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(name).\(`extension`)"
    }

    /// At most three decimals, without trailing zeros: "12.5", "-3", "0".
    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 1000).rounded() / 1000
        guard rounded != 0 else { return "0" }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
