import CoreText
import Foundation

public struct EmptyGlyphs {
    private let font: CTFont
    private let inColour: Bool

    public init(font: CTFont) {
        self.font = font
        // A colour font's glyphs can have an empty outline of their own and still draw from layers or SVG.
        inColour = ["COLR", "SVG ", "CBDT"].contains { name in
            CTFontCopyTable(font, name.utf8.reduce(0) { $0 << 8 | CTFontTableTag($1) }, []) != nil
        }
    }

    public func contains(_ glyph: CGGlyph) -> Bool {
        guard !inColour else { return false }
        var glyph = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
        // An emoji's bitmap has bounds but no outline.
        guard bounds.isEmpty else { return false }
        return CTFontCreatePathForGlyph(font, glyph, nil)?.isEmpty ?? true
    }

    public func contains(character scalar: UInt32) -> Bool {
        font.glyph(for: scalar).map { contains($0) } ?? false
    }

    public func drawsNothing(for scalar: UInt32) -> Bool {
        // A font with variation sequences lists their selectors without a glyph for them.
        font.glyph(for: scalar).map { contains($0) } ?? true
    }

    public func drawn(_ scalars: ScalarRanges) -> ScalarRanges {
        inColour ? scalars : scalars.filter { Self.isInvisible($0) || !contains(character: $0) }
    }

    public static func isInvisible(_ scalar: UInt32) -> Bool {
        guard let character = Unicode.Scalar(scalar) else { return true }
        let properties = character.properties
        if properties.isWhitespace || properties.isDefaultIgnorableCodePoint || scalar == 0x2800 { return true }
        // A font can leave a virama empty, as it only shows in the letters it joins, like Gondi's.
        if properties.canonicalCombiningClass == .virama { return true }
        switch properties.generalCategory {
        case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
