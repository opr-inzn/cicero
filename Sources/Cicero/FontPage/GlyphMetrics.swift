import CiceroCore
import SwiftUI

struct GlyphMetrics: View {
    let face: FontFace
    let glyph: CGGlyph
    var weight: Double = 400
    var variations: [String: Double] = [:]

    private static let labelRoom: CGFloat = 58
    private static let topRoom: CGFloat = 14
    private static let bottomRoom: CGFloat = 18
    private static let labelHeight: CGFloat = 14

    static func ascenderHeight(of font: CTFont) -> CGFloat? {
        var characters = Array("bdhkl".utf16), glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return glyphs.filter { $0 != 0 }.compactMap { glyph -> CGFloat? in
            guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isNull else { return nil }
            return path.boundingBoxOfPath.maxY
        }.max()
    }

    private struct Layout {
        let font: CTFont
        let units: CGFloat
        let bounds: CGRect
        let width: CGFloat
        let lines: [(value: CGFloat, names: [String])]
        let top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat

        init(face: FontFace, glyph: CGGlyph, weight: Double, variations: [String: Double]) {
            units = CGFloat(CTFontGetUnitsPerEm(FontLoader.shared.font(face, size: 12, weight: weight, variations: variations)))
            font = FontLoader.shared.font(face, size: units, weight: weight, variations: variations)
            var glyph = glyph
            var bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            width = advance.width.rounded()
            let capHeight = CTFontGetCapHeight(font).rounded()
            var lines: [(value: CGFloat, names: [String])] = [("Cap Height", capHeight), ("x-Height", CTFontGetXHeight(font).rounded()),
                                                              ("Baseline", 0), ("Descender", -CTFontGetDescent(font).rounded())]
                .filter { $0.0 == "Baseline" || $0.1 != 0 }
                .map { ($0.1, [$0.0]) }
            if let ascender = GlyphMetrics.ascenderHeight(of: font)?.rounded() {
                if capHeight != 0, abs(ascender - capHeight) <= units / 100 {
                    lines[0].names.insert("Ascender", at: 0)
                } else {
                    lines.append((ascender, ["Ascender"]))
                }
            }
            lines.sort { $0.value > $1.value }
            self.bounds = bounds
            self.lines = lines
            top = max(bounds.isEmpty ? 0 : bounds.maxY, lines.map(\.value).max() ?? 0)
            bottom = min(bounds.isEmpty ? 0 : bounds.minY, lines.map(\.value).min() ?? 0)
            left = min(0, bounds.isEmpty ? 0 : bounds.minX)
            right = max(width, bounds.isEmpty ? 0 : bounds.maxX)
        }
    }

    static func popoverWidth(face: FontFace, glyph: CGGlyph?, weight: Double, variations: [String: Double]) -> CGFloat {
        guard let glyph else { return GlyphsSection.popoverWidth }
        let layout = Layout(face: face, glyph: glyph, weight: weight, variations: variations)
        let scale = (GlyphsSection.metricsHeight - topRoom - bottomRoom) / max(layout.top - layout.bottom, 1)
        let wanted = (layout.right - layout.left) * scale + 2 * labelRoom + 2 * GlyphsSection.popoverPadding
        return min(max(GlyphsSection.popoverWidth, wanted.rounded(.up)), GlyphsSection.widestPopover)
    }

    var body: some View {
        Canvas { context, area in
            let layout = Layout(face: face, glyph: glyph, weight: weight, variations: variations)
            let (font, bounds, width, lines) = (layout.font, layout.bounds, layout.width, layout.lines)
            let (top, bottom, left, right) = (layout.top, layout.bottom, layout.left, layout.right)
            var glyph = glyph
            let scale = min((area.height - Self.topRoom - Self.bottomRoom) / max(top - bottom, 1),
                            (area.width - 2 * Self.labelRoom) / max(right - left, 1))
            let baseline = (Self.topRoom + (area.height - Self.topRoom - Self.bottomRoom + (top - bottom) * scale) / 2 + bottom * scale).rounded()
            let origin = ((area.width - (right - left) * scale) / 2 - left * scale).rounded()
            let label = Font.caption2.weight(.medium), light = Color.primary.opacity(0.15)
            var used = area.height
            for line in lines.reversed() {
                let y = baseline - line.value * scale + 0.5
                let ink = line.value == 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: area.width, y: y)) }, with: .color(line.value == 0 ? .accentColor : light), lineWidth: 1)
                for name in line.names.reversed() {
                    let below = !["Ascender", "Descender"].contains(name) && y + 2 + Self.labelHeight <= used
                    let labelY = below ? y + 2 : y - 2
                    used = below ? y : labelY - Self.labelHeight
                    context.draw(Text(name).font(label).foregroundStyle(ink), at: CGPoint(x: 0, y: labelY), anchor: below ? .topLeading : .bottomLeading)
                    guard name == line.names.last else { continue }
                    context.draw(Text(Int(line.value).plain).font(label).foregroundStyle(ink),
                                 at: CGPoint(x: area.width, y: labelY), anchor: below ? .topTrailing : .bottomTrailing)
                }
            }
            let leftX = origin.rounded() + 0.5, rightX = (origin + width * scale).rounded() + 0.5
            for x in [leftX, rightX] {
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: area.height)) }, with: .color(light), lineWidth: 1)
            }
            func number(_ value: CGFloat, at x: CGFloat, _ anchor: UnitPoint) {
                context.draw(Text(Int(value.rounded()).plain).font(label).foregroundStyle(.secondary), at: CGPoint(x: x, y: area.height), anchor: anchor)
            }
            number(width, at: (leftX + rightX) / 2, .bottom)
            if !bounds.isEmpty {
                number(bounds.minX, at: leftX - 3, .bottomTrailing)
                number(width - bounds.maxX, at: rightX + 3, .bottomLeading)
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
