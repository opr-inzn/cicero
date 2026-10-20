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

    /// Puts the outline on the clipboard as paths for design apps: InDesign's from Illustrator's clipboard format, as
    /// it places a PDF as a graphic, and Illustrator's from the PDF, as it reads that format in its own operators only.
    /// As SVG too, as an image and as text, for apps like Figma that paste SVG code, as Illustrator's own copies have
    /// it. And as a PDF file named after the style and the glyph, as the Finder copies a file: Messages and WhatsApp
    /// send that, where they named the PDF alone “FILE_3121.pdf”, and the Finder pastes it.
    static func copy(_ outline: GlyphOutline, style: String, fallback: String) {
        let item = NSPasteboardItem()
        item.setData(Data(outline.aicb.utf8), forType: .illustratorClipboard)
        let pdf = outline.pdf
        item.setData(pdf, forType: .pdf)
        let svg = outline.svg
        item.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
        item.setString(svg, forType: .string)
        if let file = temporaryFile(outline.fileName(style: style, fallback: fallback, extension: "pdf"), pdf) {
            item.setString(file.absoluteString, forType: .fileURL)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// A glyph to drag: an SVG file, which the Finder copies and design apps place, and its PDF. Nothing to drop for a
    /// glyph without an outline.
    static func dragItem(_ outline: GlyphOutline?, style: String, fallback: String) -> NSItemProvider {
        guard let outline, let file = temporaryFile(outline.fileName(style: style, fallback: fallback), Data(outline.svg.utf8)) else {
            return NSItemProvider()
        }
        let provider = NSItemProvider(contentsOf: file) ?? NSItemProvider()
        provider.suggestedName = file.deletingPathExtension().lastPathComponent
        let pdf = outline.pdf
        provider.registerDataRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { @Sendable completion in
            completion(pdf, nil)
            return nil
        }
        return provider
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
