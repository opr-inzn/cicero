import CoreText
import Foundation

/// A font's glyphs that draw nothing: the empty ones a trial font keeps for the characters it leaves out, say. A face
/// doesn't cover a character it has such a glyph for, unless the character is one of those with nothing to draw, like
/// a space (see `isInvisible`), and the glyph grid leaves those out too. Empty means without an outline or bounds of
/// its own; an emoji's bitmap has bounds but no outline. None are in a font that draws in colour from layers or SVG,
/// whose glyphs can have an empty outline of their own and still draw.
public struct EmptyGlyphs {
    private let font: CTFont
    private let inColour: Bool

    public init(font: CTFont) {
        self.font = font
        inColour = ["COLR", "SVG ", "CBDT"].contains { name in
            CTFontCopyTable(font, name.utf8.reduce(0) { $0 << 8 | CTFontTableTag($1) }, []) != nil
        }
    }

    public func contains(_ glyph: CGGlyph) -> Bool {
        guard !inColour else { return false }
        var glyph = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
        guard bounds.isEmpty else { return false }
        return CTFontCreatePathForGlyph(font, glyph, nil)?.isEmpty ?? true
    }

    /// Whether the glyph the font gives a character draws nothing; not when it has none for it.
    public func contains(character scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return false }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return false }
        return contains(glyphs[0])
    }

    /// The characters of these the font draws, and those with nothing to draw it has.
    public func drawn(_ scalars: ScalarRanges) -> ScalarRanges {
        inColour ? scalars : scalars.filter { Self.isInvisible($0) || !contains(character: $0) }
    }

    /// A character with nothing to draw, whose glyph is empty in any font: a space, a control, a joiner, a variation
    /// selector, a Hangul filler or the blank braille pattern. And a virama, which a font can leave empty as it only
    /// shows in the letters it joins, like Gondi's.
    public static func isInvisible(_ scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return true }
        let properties = character.properties
        if properties.isWhitespace || properties.isDefaultIgnorableCodePoint || scalar == 0x2800 { return true }
        if properties.canonicalCombiningClass == .virama { return true }
        switch properties.generalCategory {
        case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
