import CoreText
import Foundation

/// Reads faces straight from font files with CoreText, whether or not they're installed.
enum FontFiles {
    /// Every face in the file, in file order; empty when CoreText can't read it.
    static func descriptors(at path: String) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL) as? [CTFontDescriptor] ?? []
    }

    /// The face among a file's descriptors: the one at its index when the name agrees, else the
    /// one with its PostScript name, else whatever is at its index.
    static func descriptor(for face: FontFace, in descriptors: [CTFontDescriptor]) -> CTFontDescriptor? {
        guard !descriptors.isEmpty else { return nil }
        let index = face.id.index
        if index < descriptors.count, postScriptName(of: descriptors[index]) == face.postScriptName {
            return descriptors[index]
        }
        if let named = descriptors.first(where: { postScriptName(of: $0) == face.postScriptName }) {
            return named
        }
        return index < descriptors.count ? descriptors[index] : descriptors[0]
    }

    static func postScriptName(of descriptor: CTFontDescriptor) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    }

    /// An installed font with this name, for files Cicero can't read; CoreText substitutes a
    /// default font when none is installed.
    static func installedDescriptor(named postScriptName: String) -> CTFontDescriptor {
        CTFontCopyFontDescriptor(CTFontCreateWithName(postScriptName as CFString, 0, nil))
    }
}

extension CTFont {
    /// The glyph the font maps a character to; nil for one it has none for.
    func glyph(for character: Character) -> CGGlyph? {
        var units = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(self, &units, &glyphs, units.count) && glyphs[0] != 0 ? glyphs[0] : nil
    }

    /// The same for a Unicode scalar's value; nil for one that isn't a character.
    func glyph(for scalar: UInt32) -> CGGlyph? {
        Unicode.Scalar(scalar).flatMap { glyph(for: Character($0)) }
    }
}
