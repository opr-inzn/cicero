import CoreText
import Foundation

/// A glyph the features chosen for a family draw for a character in place of its own, like a single-storey a for a
/// stylistic set or a small capital: the font page lists it after the character's.
public struct FeatureAlternate: Hashable, Sendable {
    public let glyph: CGGlyph
    /// The chosen features that draw it, by the names the font gives them, like "Small Capitals".
    public let featureNames: [String]

    public init(glyph: CGGlyph, featureNames: [String]) {
        self.glyph = glyph
        self.featureNames = featureNames
    }
}

public enum FeatureAlternates {
    /// The characters whose glyph the features change, each set on its own, with the glyph they draw instead and
    /// the features that do it; where it takes them together, all of them. A character the features make into
    /// several glyphs, or none, is left out. Reads the font; call off the main thread.
    public static func read(_ face: FontFace, scalars: [UInt32], features: [FeatureSetting]) -> [UInt32: FeatureAlternate] {
        guard !features.isEmpty, !scalars.isEmpty else { return [:] }
        let plain = glyphs(of: scalars, in: FontLoader.shared.font(face, size: 12))
        let chosen = glyphs(of: scalars, in: FontLoader.shared.font(face, size: 12, features: features))
        var changed: [Int] = []
        for index in scalars.indices {
            if let glyph = chosen[index], let own = plain[index], glyph != own { changed.append(index) }
        }
        guard !changed.isEmpty else { return [:] }
        let groups = FontFeatureGroup.load(for: face)
        let named = features.map { feature in (name: name(of: feature, in: groups), feature: feature) }
        // Which of them draws each, from each on its own; with one, it's that one.
        let alone: [[CGGlyph?]] = named.count == 1 ? [] : named.map { glyphs(of: scalars, in: FontLoader.shared.font(face, size: 12, features: [$0.feature])) }
        var result: [UInt32: FeatureAlternate] = [:]
        for index in changed {
            var names = named.indices.filter { alone.isEmpty || alone[$0][index] != plain[index] }.map { named[$0].name }
            if names.isEmpty { names = named.map(\.name) }
            result[scalars[index]] = FeatureAlternate(glyph: chosen[index]!, featureNames: names)
        }
        return result
    }

    /// The glyph each character is drawn with, set on its own in the font, between spaces so none takes part in
    /// another's ligature or context; nil where it's drawn with more than one glyph, or by another font.
    static func glyphs(of scalars: [UInt32], in font: CTFont) -> [CGGlyph?] {
        var text = ""
        var offsets: [Int] = []
        var utf16 = 0
        for value in scalars {
            guard let scalar = Unicode.Scalar(value) else {
                offsets.append(-1)
                continue
            }
            offsets.append(utf16)
            text.unicodeScalars.append(scalar)
            text.unicodeScalars.append(" ")
            utf16 += scalar.utf16.count + 1
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        let name = CTFontCopyPostScriptName(font) as String
        var drawn: [Int: [CGGlyph]] = [:]
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            // A character the font hasn't got falls back to another font, whose glyphs aren't this one's.
            guard let runFont = attributes[kCTFontAttributeName as String], CFGetTypeID(runFont as CFTypeRef) == CTFontGetTypeID(),
                  CTFontCopyPostScriptName(runFont as! CTFont) as String == name
            else { continue }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetStringIndices(run, CFRange(), &indices)
            for (glyph, index) in zip(glyphs, indices) { drawn[index, default: []].append(glyph) }
        }
        return scalars.indices.map { index in
            guard let glyphs = drawn[offsets[index]], glyphs.count == 1, glyphs[0] != 0 else { return nil }
            return glyphs[0]
        }
    }

    /// A feature's name as the Features tab shows it: its option's, like "Small Capitals", else its group's.
    static func name(of feature: FeatureSetting, in groups: [FontFeatureGroup]) -> String {
        guard let group = groups.first(where: { $0.type == feature.type }) else { return "Feature \(feature.type):\(feature.selector)" }
        return group.options.first { $0.selector == feature.selector }?.name ?? group.name
    }
}
