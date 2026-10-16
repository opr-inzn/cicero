import CiceroCore
import CoreText
import SwiftUI

/// The ligatures a style makes, by feature: each drawn from its glyph, with the characters it stands for
/// under it. Like the glyphs, rows of fixed cells in the page's stack, with a header per feature that pins.
struct LigaturesSection: View {
    @Environment(PreviewSettings.self) private var preview
    let face: FontFace
    /// Cells per row, from the page's width.
    let columns: Int
    let groups: [LigatureGroup]
    /// The clicked ligature: its feature and characters.
    @State private var popover: (tag: String, characters: [UInt32])?

    private nonisolated static let cell = CGSize(width: 76, height: 72)
    private nonisolated static let spacing: CGFloat = 4
    private nonisolated static let inset: CGFloat = 24

    /// How many cells fit across a page this wide.
    nonisolated static func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + spacing) / (cell.width + spacing)))
    }

    var body: some View {
        let total = groups.reduce(0) { $0 + $1.ligatures.count }
        HStack(spacing: 12) {
            Text("Ligatures").font(.title2.weight(.semibold))
            Text(total == 1 ? "1 ligature" : "\(total.formatted()) ligatures")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, Self.inset)
        // Well clear of the styles above, and close to the features it heads.
        .padding(.top, 56)
        .padding(.bottom, 4)
        ForEach(groups) { group in
            Section {
                let rows = (group.ligatures.count + columns - 1) / columns
                ForEach(0..<rows, id: \.self) { row in
                    ligatureRow(group.ligatures[row * columns ..< min((row + 1) * columns, group.ligatures.count)], in: group)
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, row == rows - 1 ? 18 : Self.spacing)
                }
            } header: {
                HStack(spacing: 6) {
                    Text(group.name).font(.headline)
                    Text("— \(group.ligatures.count.formatted())").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 4)
                .background(Color.canvas)
            }
        }
    }

    /// One popover per row, pointing at the clicked cell, and cells sharing out the row's width, as for the glyphs.
    private func ligatureRow(_ ligatures: ArraySlice<Ligature>, in group: LigatureGroup) -> some View {
        let column = popover.flatMap { shown in
            shown.tag == group.tag ? ligatures.firstIndex { $0.characters == shown.characters } : nil
        }.map { $0 - ligatures.startIndex }
        let anchor = UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1)
        return HStack(spacing: Self.spacing) {
            ForEach(ligatures) { ligature in
                cell(ligature, in: group)
            }
            ForEach(ligatures.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: Self.cell.height)
            }
        }
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .point(anchor)) {
            if let column {
                details(ligatures[ligatures.startIndex + column], in: group)
            }
        }
    }

    private func cell(_ ligature: Ligature, in group: LigatureGroup) -> some View {
        let isShown = popover?.tag == group.tag && popover?.characters == ligature.characters
        return VStack(spacing: 2) {
            GlyphImage(face: face, glyph: ligature.glyph, size: 28, weight: preview.weight)
                .frame(height: 46)
            Text(ligature.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 4)
        .frame(minWidth: Self.cell.width, maxWidth: .infinity, minHeight: Self.cell.height, maxHeight: Self.cell.height)
        .background(.quaternary.opacity(isShown ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onTapGesture { popover = (group.tag, ligature.characters) }
        .accessibilityElement()
        .accessibilityLabel("Ligature of \(ligature.text)")
        .accessibilityAddTraits(.isButton)
    }

    private func details(_ ligature: Ligature, in group: LigatureGroup) -> some View {
        VStack(spacing: 10) {
            GlyphImage(face: face, glyph: ligature.glyph, size: 96, weight: preview.weight)
                .frame(width: 220, height: 130)
            Text(ligature.characters.compactMap(Unicode.Scalar.init).map { String(Character($0)) }.joined(separator: " + "))
                .font(.title3)
            Text(ligature.characters.map { String(format: "U+%04X", $0) }.joined(separator: " "))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(group.name) (\(group.tag))").font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: 300)
    }
}

/// One glyph of a face, by its ID, drawn from its outline: a ligature has no character of its own to set.
/// Centred on the font's ascender and descender, so glyphs side by side share a baseline, and scaled down
/// when it's wider than the room.
struct GlyphImage: View {
    let face: FontFace
    let glyph: CGGlyph
    let size: CGFloat
    var weight: Double = 400

    var body: some View {
        Canvas { context, area in
            let font = FontLoader.shared.font(face, size: size, weight: weight)
            var glyph = glyph
            guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return }
            var bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
            // The font's ascent and descent, or as far as the glyph reaches past them: all of it fits the cell.
            let ascent = max(CTFontGetAscent(font), bounds.maxY), descent = max(CTFontGetDescent(font), -bounds.minY)
            let scale = min(1, (area.width - 6) / max(bounds.width, 1), area.height / max(ascent + descent, 1))
            let x = (area.width - bounds.width * scale) / 2 - bounds.minX * scale
            let baseline = (area.height + (ascent - descent) * scale) / 2
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: x, ty: baseline)
            context.fill(Path(outline).applying(transform), with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
