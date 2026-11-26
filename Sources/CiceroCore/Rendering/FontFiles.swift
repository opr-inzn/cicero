import CoreText
import Foundation

enum FontFiles {
    static func descriptors(at path: String) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL) as? [CTFontDescriptor] ?? []
    }

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

    static func installedDescriptor(named postScriptName: String) -> CTFontDescriptor {
        CTFontCopyFontDescriptor(CTFontCreateWithName(postScriptName as CFString, 0, nil))
    }
}

extension CTFont {
    func glyph(for character: Character) -> CGGlyph? {
        var units = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(self, &units, &glyphs, units.count) && glyphs[0] != 0 ? glyphs[0] : nil
    }

    func glyph(for scalar: UInt32) -> CGGlyph? {
        Unicode.Scalar(scalar).flatMap { glyph(for: Character($0)) }
    }
}
