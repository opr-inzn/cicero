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

    /// Puts the outline on the clipboard as PDF, which design apps paste as paths, and as SVG, as an image and as text,
    /// for apps like Figma that paste SVG code, as Illustrator's own copies have it. A beep for a glyph without one.
    static func copy(_ outline: GlyphOutline?) {
        guard let outline else { return NSSound.beep() }
        let item = NSPasteboardItem()
        item.setData(outline.pdf, forType: .pdf)
        let svg = outline.svg
        item.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
        item.setString(svg, forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// A glyph to drag: an SVG file, which the Finder copies and design apps place, and its PDF. Nothing to drop for a
    /// glyph without an outline.
    static func dragItem(_ outline: GlyphOutline?, style: String, fallback: String) -> NSItemProvider {
        guard let outline else { return NSItemProvider() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Glyphs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(outline.fileName(style: style, fallback: fallback))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(outline.svg.utf8).write(to: file)
        } catch {
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
}
