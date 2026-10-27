import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// A font page's glyphs as vectors: Copy as Vector, and dragging a glyph's cell out of the page.
enum GlyphVectors {
    /// A glyph of a style, at its weight and with its axes as moved, at the size outlines are taken at.
    static func outline(_ glyph: CGGlyph?, face: FontFace, weight: Double, variations: [String: Double]) -> GlyphOutline? {
        glyph.flatMap { GlyphOutline(glyph: $0, font: font(face, weight: weight, variations: variations)) }
    }

    static func font(_ face: FontFace, weight: Double, variations: [String: Double]) -> CTFont {
        FontLoader.shared.font(face, size: GlyphOutline.emSize, weight: weight, variations: variations)
    }

    /// The glyph the font maps a character to, if it has one: the one its cell shows, without features.
    static func glyph(of scalar: UInt32, in font: CTFont) -> CGGlyph? {
        guard let character = Unicode.Scalar(scalar) else { return nil }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    /// Puts the outline on the clipboard, first as an SVG file named after the style and the glyph, as the Finder copies
    /// a file: Messages and WhatsApp take the first thing they can send, and named a PDF “FILE_3121.pdf”, and Figma,
    /// which takes a file before SVG code, imports SVG but not PDF. Then as paths for design apps: InDesign's from
    /// Illustrator's clipboard format, as it places a PDF as a graphic, and Illustrator's from the PDF, as it reads that
    /// format in its own operators only. And as SVG, as an image and as text, as Illustrator's own copies have it. And
    /// as `clip` for the font page's text, which pastes the glyph there rather than its SVG code.
    static func copy(_ outline: GlyphOutline, style: String, fallback: String, clip: SampleClip) {
        let item = NSPasteboardItem()
        let svg = outline.svg
        if let file = temporaryFile(outline.fileName(style: style, fallback: fallback), Data(svg.utf8)) {
            item.setString(file.absoluteString, forType: .fileURL)
        }
        item.setData(Data(outline.aicb.utf8), forType: .illustratorClipboard)
        item.setData(outline.pdf, forType: .pdf)
        item.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
        item.setString(svg, forType: .string)
        if let data = clip.data { item.setData(data, forType: .sampleClip) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// A glyph to drag: the SVG file Copy as Vector puts on the clipboard, as the Finder drags a file, so the Finder
    /// copies it and Messages sends it by its name, where its contents alone came as “SVG image.svg”. Nothing to drop
    /// for a glyph without an outline.
    static func dragItem(_ outline: GlyphOutline?, style: String, fallback: String) -> NSItemProvider {
        guard let outline, let file = temporaryFile(outline.fileName(style: style, fallback: fallback), Data(outline.svg.utf8)) else {
            return NSItemProvider()
        }
        return NSItemProvider(object: file as NSURL)
    }

    /// A file of its own in a new temporary folder, so it can have the name given: what's copied or dragged.
    private static func temporaryFile(_ name: String, _ data: Data) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Glyphs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}

extension NSPasteboard.PasteboardType {
    /// Adobe Illustrator's clipboard format (AICB), as Illustrator and InDesign declare it.
    static let illustratorClipboard = NSPasteboard.PasteboardType("com.adobe.illustrator.aicb")
}
