import AppKit
import CiceroCore
import UniformTypeIdentifiers

enum GlyphVectors {
    static func outline(_ glyph: CGGlyph?, face: FontFace, weight: Double, variations: [String: Double]) -> GlyphOutline? {
        glyph.flatMap { GlyphOutline(glyph: $0, font: font(face, weight: weight, variations: variations)) }
    }

    static func font(_ face: FontFace, weight: Double, variations: [String: Double]) -> CTFont {
        FontLoader.shared.font(face, size: GlyphOutline.emSize, weight: weight, variations: variations)
    }

    static func glyph(of scalar: UInt32, in font: CTFont) -> CGGlyph? {
        guard let character = Unicode.Scalar(scalar) else { return nil }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

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

    static func dragItem(_ outline: GlyphOutline?, style: String, fallback: String) -> NSItemProvider {
        dragFile(outline, style: style, fallback: fallback).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
    }

    static func dragFile(_ outline: GlyphOutline?, style: String, fallback: String) -> URL? {
        outline.flatMap { temporaryFile($0.fileName(style: style, fallback: fallback), Data($0.svg.utf8)) }
    }

    static func isDragFile(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.resolvingSymlinksInPath().path
            .hasPrefix(filesFolder.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }

    private static var filesFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Glyphs", isDirectory: true) }

    private static func temporaryFile(_ name: String, _ data: Data) -> URL? {
        let folder = filesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    static let illustratorClipboard = NSPasteboard.PasteboardType("com.adobe.illustrator.aicb")
}
