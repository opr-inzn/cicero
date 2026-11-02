import CiceroCore
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `cicero compare <names…>`: one PNG with the same text in each family's regular style (every style with
/// `--all-styles`), or in styles named by their PostScript names, full names or family and style names, each under a label, so an assistant can look
/// at the fonts and not only read their data. Fonts are drawn from their files, on or off. Characters a font lacks are
/// drawn as red boxes, never in another font, and listed in its label and in the answer.
public enum CompareCommand {
    /// Cicero's own sample text (the font page's).
    public static let defaultText = "Sphinx of black quartz, judge my vow."
    /// More would make a picture too tall for an assistant to see the letters in.
    public static let maximumSamples = 50
    public static let sizes = 6...400
    public static let widths = 200...8000

    public struct Options: Sendable {
        public var names: [String] = []
        public var allStyles = false
        public var text: String?
        public var size = 48
        public var width = 1200
        /// Where the PNG goes; nil for a file in the temporary folder.
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
        guard let (png, height) = try SampleSheet.png(samples, text: text, size: size, width: options.width) else {
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

    /// Each name a family (its regular style, or every style with `allStyles`), else a style by its PostScript name or
    /// full name, or family and style name ("Inter-Bold", "Inter Bold"). A style named twice is drawn once.
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

    /// The style of a shown family with this PostScript name, full name, or family and style name ("Inter Variable
    /// Bold", which a variable font's full name may not be), ignoring case; nil when none has it.
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

    /// The path given, from the current folder, or a file named after the names in the temporary folder.
    static func destination(_ path: String?, names: [String]) throws -> URL {
        if let path {
            guard !path.isEmpty else { throw CommandError.invalid("--png needs a file’s path.") }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        }
        // TMPDIR, as other command-line tools have it; Foundation's temporary folder ignores it.
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let folder = temporary.appendingPathComponent("cicero", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw CommandError(.failed, "Cicero can’t make the folder \(folder.path): \(error.localizedDescription)")
        }
        var name = String(names.joined(separator: " vs ").map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 })
        // A file name has up to 255 bytes.
        while name.utf8.count > 200 { name.removeLast() }
        return folder.appendingPathComponent("compare " + name + ".png")
    }
}

/// One row of the picture: the style's font from its file, or nil when the file can't be read (a font CoreText would
/// put in its place is never drawn), and the characters of the text it lacks.
struct Sample {
    let family: Family
    let style: LibraryFace
    let font: CTFont?
    let missing: [UInt32]

    init(family: Family, style: LibraryFace, text: String, size: CGFloat) {
        self.family = family
        self.style = style
        let font = FontLoader.shared.font(style.face, size: size, cached: false)
        let isItself = CTFontCopyPostScriptName(font) as String == style.face.postScriptName
        self.font = isItself ? font : nil
        missing = isItself ? CoverageSearch.scalars(in: text).filter { !font.has($0) } : []
    }

    var label: String { "\(family.id) — \(style.face.styleName)" }
}

private extension CTFont {
    func has(_ scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return false }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(self, &units, &glyphs, units.count)
    }
}

/// Draws the samples one under the other on white, each under a small grey label, with a hairline between them. The
/// text wraps at the picture's width and keeps its line breaks; right-to-left text starts at the right. One pixel is a
/// point, so `size` is the letters' size in pixels.
enum SampleSheet {
    static let margin: CGFloat = 32
    static let labelSize: CGFloat = 14
    static let labelGap: CGFloat = 8
    static let rowGap: CGFloat = 20
    /// Missing characters a label lists before it says how many more there are.
    static let listedMissing = 20
    /// Higher, the picture takes gigabytes to draw, and no one sees its letters.
    static let maximumHeight = 30000

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

    /// The PNG and its height in pixels; nil when CoreGraphics can't make it.
    static func png(_ samples: [Sample], text: String, size: CGFloat, width: Int) throws -> (Data, Int)? {
        let contentWidth = CGFloat(width) - 2 * margin
        let labelFont = CTFontCreateUIFontForLanguage(.system, labelSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, labelSize, nil)
        let rows = samples.map { sample -> Row in
            let label = labelLine(sample, font: labelFont)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(label, &ascent, &descent, &leading)
            guard let font = sample.font else {
                return Row(label: label, labelAscent: ascent, labelHeight: ascent + descent, frame: nil, sampleHeight: 0, font: nil)
            }
            let framesetter = CTFramesetterCreateWithAttributedString(sampleText(text, font: font))
            let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil, CGSize(width: contentWidth, height: .greatestFiniteMagnitude), nil)
            return Row(label: label, labelAscent: ascent, labelHeight: ascent + descent, frame: framesetter,
                       sampleHeight: ceil(fitted.height), font: font)
        }
        let height = Int(ceil(2 * margin + rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * (2 * rowGap + 1)))
        guard height <= maximumHeight else {
            throw CommandError.invalid("The picture would be \(height) pixels high, more than \(maximumHeight). Use fewer styles, a shorter text, a smaller --size or a wider --width.")
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textMatrix = .identity

        // From the top: CoreGraphics counts y from the bottom.
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
                     text: text, in: box, font: font, context: context)
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

    /// "Family — Style" in grey; what it lacks, or that its file can't be read, in red after it. One line: the missing
    /// characters after the first `listedMissing` are counted, not listed.
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
            note = "lacks " + listed.joined(separator: " ")
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
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ])
    }

    /// The frame's lines, the runs in the sample's font as they are, the others (characters CoreText took from another
    /// font) as red boxes as wide as those characters, from the baseline to the sample font's cap height. Spaces from
    /// another font stay empty.
    private static func draw(_ frame: CTFrame, text: String, in box: CGRect, font: CTFont, context: CGContext) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let name = CTFontCopyPostScriptName(font) as String
        let file = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
        let capHeight = CTFontGetCapHeight(font) > 0 ? CTFontGetCapHeight(font) : CTFontGetSize(font) * 0.7
        let stroke = max(1, CTFontGetSize(font) / 32)
        let units = Array(text.utf16)
        for (line, origin) in zip(lines, origins) {
            let start = CGPoint(x: box.minX + origin.x, y: box.minY + origin.y)
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName as String] as! CTFont
                if CTFontCopyPostScriptName(runFont) as String == name, CTFontCopyAttribute(runFont, kCTFontURLAttribute) as? URL == file {
                    context.textPosition = start
                    CTRunDraw(run, context, CFRange(location: 0, length: 0))
                    continue
                }
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                context.setStrokeColor(red)
                context.setLineWidth(stroke)
                for ((position, advance), index) in zip(zip(positions, advances), indices) where advance.width > 2 * stroke {
                    // A space another font gives is a space: nothing in it to see.
                    if index < units.count, let scalar = Unicode.Scalar(units[index]), scalar.properties.isWhitespace { continue }
                    context.stroke(CGRect(x: start.x + position.x + stroke, y: start.y + position.y + stroke / 2,
                                          width: advance.width - 2 * stroke, height: capHeight - stroke))
                }
            }
        }
    }
}
