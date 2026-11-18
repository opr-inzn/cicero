import CiceroCore
import SwiftUI

struct GlyphMetrics: View {
    let face: FontFace
    let glyph: CGGlyph
    let characters: [UInt32]
    var weight: Double = 400
    var variations: [String: Double] = [:]

    private static let labelRoom: CGFloat = 58
    private static let topRoom: CGFloat = 14
    private static let bottomRoom: CGFloat = 18
    private static let labelHeight: CGFloat = 14
    private static let ascenderLetters = Set("bdfhklßþðħłŀƀƃƅƙƚɓɗɦɬɭβδζθλξбђћ".unicodeScalars.map(\.value))

    static func ascenderHeight(of font: CTFont) -> CGFloat? {
        var characters = Array("bdhkl".utf16), glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return glyphs.filter { $0 != 0 }.compactMap { glyph -> CGFloat? in
            guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isNull else { return nil }
            return path.boundingBoxOfPath.maxY
        }.max()
    }

    private static func hasAscender(_ characters: [UInt32]) -> Bool {
        let text = String(String.UnicodeScalarView(characters.compactMap(Unicode.Scalar.init)))
        return text.decomposedStringWithCompatibilityMapping.unicodeScalars.contains { ascenderLetters.contains($0.value) }
    }

    var body: some View {
        Canvas { context, area in
            let units = CGFloat(CTFontGetUnitsPerEm(FontLoader.shared.font(face, size: 12, weight: weight, variations: variations)))
            let font = FontLoader.shared.font(face, size: units, weight: weight, variations: variations)
            var glyph = glyph
            var bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            let width = advance.width.rounded()
            let capHeight = CTFontGetCapHeight(font).rounded()
            var lines: [(String, CGFloat)] = [("Cap Height", capHeight), ("x-Height", CTFontGetXHeight(font).rounded()),
                         ("Baseline", 0), ("Descender", -CTFontGetDescent(font).rounded())]
                .filter { $0.0 == "Baseline" || $0.1 != 0 }
            if let ascender = Self.ascenderHeight(of: font)?.rounded() {
                if abs(ascender - capHeight) > units / 100 {
                    lines.insert(("Ascender", ascender), at: 0)
                } else if Self.hasAscender(characters) {
                    lines[0] = ("Ascender", ascender)
                }
            }
            lines.sort { $0.1 > $1.1 }
            let top = max(bounds.isEmpty ? 0 : bounds.maxY, lines.map(\.1).max() ?? 0)
            let bottom = min(bounds.isEmpty ? 0 : bounds.minY, lines.map(\.1).min() ?? 0)
            let left = min(0, bounds.isEmpty ? 0 : bounds.minX), right = max(width, bounds.isEmpty ? 0 : bounds.maxX)
            let scale = min((area.height - Self.topRoom - Self.bottomRoom) / max(top - bottom, 1),
                            (area.width - 2 * Self.labelRoom) / max(right - left, 1))
            let baseline = (Self.topRoom + (area.height - Self.topRoom - Self.bottomRoom + (top - bottom) * scale) / 2 + bottom * scale).rounded()
            let origin = ((area.width - (right - left) * scale) / 2 - left * scale).rounded()
            let rule = Color.primary.opacity(0.15)
            let label = Font.caption2.weight(.medium)
            for (index, (name, value)) in lines.enumerated() {
                let y = baseline - value * scale + 0.5
                let below = index > 0 && value * scale > lines[index - 1].1 * scale - Self.labelHeight
                let labelY = below ? y + 2 : y - 2
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: area.width, y: y)) }, with: .color(rule), lineWidth: 1)
                context.draw(Text(name).font(label).foregroundStyle(.secondary), at: CGPoint(x: 0, y: labelY), anchor: below ? .topLeading : .bottomLeading)
                context.draw(Text(Int(value).formatted()).font(label.monospacedDigit()).foregroundStyle(.secondary),
                             at: CGPoint(x: area.width, y: labelY), anchor: below ? .topTrailing : .bottomTrailing)
            }
            let rulesTop = baseline - top * scale - 4, rulesBottom = area.height - Self.bottomRoom + 2
            for value in [0, width] {
                let x = (origin + value * scale).rounded() + 0.5
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: rulesTop)); $0.addLine(to: CGPoint(x: x, y: rulesBottom)) }, with: .color(rule), lineWidth: 1)
                context.draw(Text(Int(value).formatted()).font(label.monospacedDigit()).foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: area.height), anchor: .bottomLeading)
            }
            let color = Color.ink.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                cg.setFillColor(color)
                cg.translateBy(x: origin, y: baseline)
                cg.scaleBy(x: scale, y: -scale)
                var position = CGPoint.zero
                CTFontDrawGlyphs(font, &glyph, &position, 1, cg)
            }
        }
        .accessibilityHidden(true)
    }
}
