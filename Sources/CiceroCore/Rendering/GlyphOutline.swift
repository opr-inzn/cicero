import CoreGraphics
import CoreText
import Foundation

public struct GlyphOutline {
    public static let emSize: CGFloat = 100

    public let path: CGPath
    public let frame: CGRect
    public let name: String?

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

    public var svg: String {
        var data = ""
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

    public var aicb: String {
        // InDesign and Illustrator run this as PostScript, where Illustrator's short operators exist only once its procedure sets define them: use PostScript's own.
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

    public func fileName(style: String, fallback: String, extension: String = "svg") -> String {
        let name = "\(style) \(name ?? fallback)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(name).\(`extension`)"
    }

    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 1000).rounded() / 1000
        guard rounded != 0 else { return "0" }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
