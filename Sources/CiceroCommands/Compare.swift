import CiceroCore
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CompareCommand {
    public static let defaultText = "Sphinx of black quartz, judge my vow."
    static let maximumSamples = 50
    public static let sizes = 6...400
    public static let widths = 200...8000

    public struct Options: Sendable {
        public var names: [String] = []
        public var allStyles = false
        public var text: String?
        public var size = 48
        public var width = 1200
        public var png: String?

        public init() {}
    }

    public static func run(_ options: Options, in context: LibraryContext) throws -> JSON {
        guard sizes.contains(options.size) else { throw CommandError.invalid("--size goes from \(sizes.lowerBound) to \(sizes.upperBound).") }
        guard widths.contains(options.width) else { throw CommandError.invalid("--width goes from \(widths.lowerBound) to \(widths.upperBound).") }
        let text = options.text ?? defaultText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError.invalid("--text has nothing to draw.") }
        let chosen = try styles(options.names, allStyles: options.allStyles, in: context)
        guard chosen.count <= maximumSamples else {
            throw CommandError.invalid("That’s \(chosen.count) styles. Compare at most \(maximumSamples) at a time.")
        }

        let size = CGFloat(options.size)
        let samples = chosen.map { family, style in Sample(family: family, style: style, text: text, size: size) }
        let url = try destination(options.png, names: options.names)
        guard let (png, height) = try SampleSheet.png(samples, text: text, width: options.width) else {
            throw CommandError(.failed, "Cicero can’t draw the picture.")
        }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            throw CommandError(.failed, "Cicero can’t write \(url.path): \(error.localizedDescription)")
        }

        var answer = JSONObject.answer()
        answer.set("png", url.path)
        answer.set("width", options.width)
        answer.set("height", height)
        answer.set("text", text)
        answer.set("size", options.size)
        answer.set("samples", samples.map { sample -> JSON in
            var object = JSONObject()
            object.set("family", sample.family.id)
            object.set("style", sample.style.face.styleName)
            object.set("postScriptName", sample.style.face.postScriptName)
            object.set("path", sample.style.face.path)
            if sample.font == nil { object.set("unreadable", true) }
            object.set("missingCount", sample.missing.count)
            object.set("missing", sample.missing.map { value -> JSON in
                var character = JSONObject()
                character.set("character", Unicode.Scalar(value).map { String(Character($0)) } ?? "")
                character.set("unicode", String(format: "U+%04X", value))
                return character.json
            })
            return object.json
        })
        return answer.json
    }

    static func styles(_ names: [String], allStyles: Bool, in context: LibraryContext) throws -> [(Family, LibraryFace)] {
        guard !names.isEmpty else { throw CommandError.invalid("Give the families to compare, or styles by their PostScript names.") }
        var result: [(Family, LibraryFace)] = []
        var seen: Set<FaceID> = []
        for name in names {
            let found: [(Family, LibraryFace)]
            do {
                let family = try Names.family(name, in: context)
                found = allStyles ? family.faces.map { (family, $0) } : [(family, family.regular)]
            } catch let error as CommandError where error.code == .notFound {
                guard let style = try style(name, in: context) else { throw error }
                found = [style]
            }
            for (family, style) in found where seen.insert(style.id).inserted {
                result.append((family, style))
            }
        }
        return result
    }

    static func style(_ typed: String, in context: LibraryContext) throws -> (Family, LibraryFace)? {
        let key = Names.fold(typed)
        let found = context.listedFamilies.flatMap { family in
            family.faces.filter { style in
                [style.face.postScriptName, style.face.fullName, "\(family.id) \(style.face.styleName)"].contains { Names.fold($0) == key }
            }.map { (family, $0) }
        }
        guard found.count > 1 else { return found.first }
        throw CommandError(.ambiguous, "More than one family has a style called “\(typed)”. Compare those families with --all-styles.",
                           suggestions: found.map(\.0.id))
    }

    static func destination(_ path: String?, names: [String]) throws -> URL {
        if let path {
            guard !path.isEmpty else { throw CommandError.invalid("--png needs a file’s path.") }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        }
        // TMPDIR first: Foundation's temporary folder ignores it.
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let folder = temporary.appendingPathComponent("cicero", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw CommandError(.failed, "Cicero can’t make the folder \(folder.path): \(error.localizedDescription)")
        }
        var name = String(names.joined(separator: " vs ").map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 })
        while name.utf8.count > 200 { name.removeLast() }
        return folder.appendingPathComponent("compare " + name + ".png")
    }
}

struct Sample {
    let family: Family
    let style: LibraryFace
    let font: CTFont?
    let missing: [UInt32]

    init(family: Family, style: LibraryFace, text: String, size: CGFloat) {
        self.family = family
        self.style = style
        let font = FontLoader.shared.font(style.face, size: size, cached: false)
        // A file that can't be read gives a font CoreText puts in its place, which is never drawn.
        let isItself = CTFontCopyPostScriptName(font) as String == style.face.postScriptName
        self.font = isItself ? font : nil
        missing = isItself ? CoverageSearch.scalars(in: text).filter { !font.has($0) } : []
    }

    var label: String { "\(family.id), \(style.face.styleName)" }
}

private extension CTFont {
    func has(_ scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return false }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(self, &units, &glyphs, units.count)
    }
}

enum SampleSheet {
    static let margin: CGFloat = 32
    static let labelSize: CGFloat = 14
    static let labelGap: CGFloat = 8
    static let rowGap: CGFloat = 20
    static let listedMissing = 20
    static let maximumHeight = 30000
    static let maximumPixels = 36_000_000

    static let ink = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let grey = CGColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1)
    static let red = CGColor(srgbRed: 0.85, green: 0.15, blue: 0.1, alpha: 1)
    static let rule = CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)

    private struct Row {
        let label: CTLine
        let labelAscent: CGFloat
        let labelHeight: CGFloat
        let frame: CTFramesetter?
        let sampleHeight: CGFloat
        let font: CTFont?

        var height: CGFloat { labelHeight + labelGap + sampleHeight }
    }

    static func png(_ samples: [Sample], text: String, width: Int) throws -> (Data, Int)? {
        let contentWidth = CGFloat(width) - 2 * margin
        let labelFont = CTFontCreateUIFontForLanguage(.system, labelSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, labelSize, nil)
        let rows = samples.map { sample -> Row in
            let label = labelLine(sample, font: labelFont)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(label, &ascent, &descent, &leading)
            guard let font = sample.font else {
                return Row(label: label, labelAscent: ascent, labelHeight: ascent + descent, frame: nil, sampleHeight: 0, font: nil)
            }
            let attributed = sampleText(text.precomposedStringWithCanonicalMapping, font: font)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil, CGSize(width: contentWidth, height: .greatestFiniteMagnitude), nil)
            return Row(label: label, labelAscent: ascent, labelHeight: ascent + descent, frame: framesetter,
                       sampleHeight: ceil(fitted.height), font: font)
        }
        let height = Int(ceil(2 * margin + rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * (2 * rowGap + 1)))
        guard height <= maximumHeight else {
            throw CommandError.invalid("The picture would be \(height) pixels high, more than \(maximumHeight). Use fewer styles, a shorter text, a smaller --size or a wider --width.")
        }
        guard width * height <= maximumPixels else {
            throw CommandError.invalid("The picture would be \(width) × \(height) pixels, more than \(maximumPixels / 1_000_000) million. Use fewer styles, a shorter text, a smaller --size or a narrower --width.")
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textMatrix = .identity

        var top = margin
        for (index, row) in rows.enumerated() {
            if index > 0 {
                top += rowGap
                context.setFillColor(rule)
                context.fill(CGRect(x: margin, y: CGFloat(height) - top - 1, width: contentWidth, height: 1))
                top += 1 + rowGap
            }
            context.textPosition = CGPoint(x: margin, y: CGFloat(height) - top - row.labelAscent)
            CTLineDraw(row.label, context)
            top += row.labelHeight + labelGap
            if let framesetter = row.frame, let font = row.font {
                let box = CGRect(x: margin, y: CGFloat(height) - top - row.sampleHeight, width: contentWidth, height: row.sampleHeight)
                draw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil),
                     in: box, font: font, context: context)
            }
            top += row.sampleHeight
        }

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, height)
    }

    private static func labelLine(_ sample: Sample, font: CTFont) -> CTLine {
        let string = NSMutableAttributedString(string: sample.label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): grey,
        ])
        var note: String?
        if sample.font == nil {
            note = "can’t read its file: \(sample.style.face.path)"
        } else if !sample.missing.isEmpty {
            let listed = sample.missing.prefix(listedMissing).compactMap(Unicode.Scalar.init).map { String(Character($0)) }
            note = "missing " + listed.joined(separator: " ")
            if sample.missing.count > listedMissing { note! += " and \(sample.missing.count - listedMissing) more" }
        }
        if let note {
            string.append(NSAttributedString(string: "   " + note, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
            ]))
        }
        return CTLineCreateWithAttributedString(string)
    }

    private static func sampleText(_ text: String, font: CTFont) -> CFAttributedString {
        var alignment = CTTextAlignment.natural
        let style = withUnsafeBytes(of: &alignment) { bytes in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: bytes.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        // Each character the font lacks becomes U+FFFC with the delegate, as CoreText otherwise looks for another font anyway and macOS logs an error for each; a word joiner (U+2060, which draws nothing) on either side of it keeps lines breaking where the text's own would.
        var layout = ""
        var missing: [Int] = []
        let scalars = Array(text.unicodeScalars)
        let breaks = { (scalar: Unicode.Scalar) in scalar.properties.isWhitespace || scalar.properties.generalCategory == .control }
        let checked = Set(CoverageSearch.scalars(in: text))
        for (index, scalar) in scalars.enumerated() {
            if !checked.contains(scalar.value) || font.has(scalar.value) {
                layout.unicodeScalars.append(scalar)
                continue
            }
            if index > 0, !breaks(scalars[index - 1]) { layout.unicodeScalars.append("\u{2060}") }
            missing.append(layout.utf16.count)
            layout.unicodeScalars.append("\u{FFFC}")
            if index + 1 < scalars.count, !breaks(scalars[index + 1]) { layout.unicodeScalars.append("\u{2060}") }
        }
        let string = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), layout as CFString)
        let whole = CFRange(location: 0, length: CFAttributedStringGetLength(string))
        CFAttributedStringSetAttribute(string, whole, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(string, whole, kCTForegroundColorAttributeName, ink)
        CFAttributedStringSetAttribute(string, whole, kCTParagraphStyleAttributeName, style)
        let notdef = Notdef(font)
        for offset in missing {
            // A delegate of its own for each, so runs of missing characters don't merge into one wide glyph.
            CFAttributedStringSetAttribute(string, CFRange(location: offset, length: 1), kCTRunDelegateAttributeName, notdef.delegate())
        }
        return string
    }

    private static func draw(_ frame: CTFrame, in box: CGRect, font: CTFont, context: CGContext) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let name = CTFontCopyPostScriptName(font) as String
        let file = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
        for (line, origin) in zip(lines, origins) {
            let start = CGPoint(x: box.minX + origin.x, y: box.minY + origin.y)
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                if attributes[kCTRunDelegateAttributeName as String] != nil {
                    let count = CTRunGetGlyphCount(run)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var points = positions.map { CGPoint(x: start.x + $0.x, y: start.y + $0.y) }
                    // CoreGraphics adds the text position to the glyphs'.
                    context.textPosition = .zero
                    context.setFillColor(ink)
                    CTFontDrawGlyphs(font, &glyphs, &points, count, context)
                    continue
                }
                let runFont = attributes[kCTFontAttributeName as String] as! CTFont
                guard CTFontCopyPostScriptName(runFont) as String == name, CTFontCopyAttribute(runFont, kCTFontURLAttribute) as? URL == file
                else { continue }
                context.textPosition = start
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
            }
        }
    }
}

struct Notdef {
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat

    init(_ font: CTFont) {
        var glyph: CGGlyph = 0
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        width = advance.width
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
    }

    func delegate() -> CTRunDelegate {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { Unmanaged<Box>.fromOpaque($0).release() },
            getAscent: { Unmanaged<Box>.fromOpaque($0).takeUnretainedValue().metrics.ascent },
            getDescent: { Unmanaged<Box>.fromOpaque($0).takeUnretainedValue().metrics.descent },
            getWidth: { Unmanaged<Box>.fromOpaque($0).takeUnretainedValue().metrics.width })
        return CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(Box(self)).toOpaque())!
    }

    private final class Box {
        let metrics: Notdef
        init(_ metrics: Notdef) { self.metrics = metrics }
    }
}
