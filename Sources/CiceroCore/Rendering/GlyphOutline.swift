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

    /// The outline in Adobe Illustrator's clipboard format (AICB), which InDesign and Illustrator paste as paths of
    /// their own, where they'd place a PDF as a graphic. They run it as PostScript: Illustrator's own copies define
    /// its short operators first, in Adobe's procedure sets, so this one sticks to PostScript's: one black path,
    /// filled, its frame's corner at 0, 0.
    public var aicb: String {
        var paths = ""
        func point(_ point: CGPoint) -> String {
            "\(Self.number(point.x - frame.minX)) \(Self.number(point.y - frame.minY))"
        }
        var current = CGPoint.zero, start = CGPoint.zero
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                start = points[0]
                current = points[0]
                paths += "\(point(points[0])) moveto\n"
            case .addLineToPoint:
                current = points[0]
                paths += "\(point(points[0])) lineto\n"
            case .addQuadCurveToPoint:
                // PostScript's curves are cubic: TrueType's quadratic ones, raised.
                let control = points[0], end = points[1]
                let first = CGPoint(x: current.x + 2 / 3 * (control.x - current.x), y: current.y + 2 / 3 * (control.y - current.y))
                let second = CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y))
                current = end
                paths += "\(point(first)) \(point(second)) \(point(end)) curveto\n"
            case .addCurveToPoint:
                current = points[2]
                paths += "\(point(points[0])) \(point(points[1])) \(point(points[2])) curveto\n"
            case .closeSubpath:
                current = start
                paths += "closepath\n"
            @unknown default: break
            }
        }
        let width = Self.number(frame.width), height = Self.number(frame.height)
        return """
            %!PS-Adobe-3.0 EPSF-3.0
            %%Creator: Cicero
            %%BoundingBox: 0 0 \(Int(frame.width.rounded(.up))) \(Int(frame.height.rounded(.up)))
            %%HiResBoundingBox: 0 0 \(width) \(height)
            %%EndComments
            %%BeginProlog
            %%EndProlog
            %%BeginSetup
            %%EndSetup
            0 0 0 1 setcmykcolor
            newpath
            \(paths)fill
            %%PageTrailer
            %%Trailer
            %%EOF

            """
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
