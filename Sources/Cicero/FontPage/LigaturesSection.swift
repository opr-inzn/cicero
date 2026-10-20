import CiceroCore
import CoreText
import SwiftUI

/// The ligatures a style makes, by feature, among the glyphs (see `GlyphsSection`): each drawn from its glyph in a cell
/// like a character's, in the same columns, the characters it stands for in its tooltip and popover, which copies them
/// or its outline, as its right-click menu does, and dragged out as an SVG file. Like the glyphs' groups, rows of fixed
/// cells in the page's stack, under a header per feature like a group's.
struct LigaturesSection: View {
    @Environment(AppModel.self) private var model
    /// The style the page's text is set in, at its weight.
    let face: FontFace
    let weight: Double
    /// Axes moved in the Info panel, by tag.
    let variations: [String: Double]
    /// Cells per row: the glyphs'.
    let columns: Int
    let groups: [LigatureGroup]
    /// The character a ligature's glyph is too, like U+FB01 for ﬁ.
    let characters: [CGGlyph: UInt32]
    /// The clicked ligature: its feature and characters.
    @State private var popover: (tag: String, characters: [UInt32])?

    private static var cell: CGFloat { GlyphsSection.cell }
    private static var spacing: CGFloat { GlyphsSection.spacing }
    private static var inset: CGFloat { GlyphsSection.inset }

    var body: some View {
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
                Color.clear.frame(maxWidth: .infinity, maxHeight: Self.cell)
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
        // The glyphs' size; a long one is scaled down to fit.
        return GlyphImage(face: face, glyph: ligature.glyph, size: GlyphsSection.glyphSize, weight: weight, variations: variations)
            .padding(.horizontal, 2)
            .frame(minWidth: Self.cell, maxWidth: .infinity, minHeight: Self.cell, maxHeight: Self.cell)
            .background(.quaternary.opacity(isShown ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .help(ligature.text)
            .onTapGesture { popover = (group.tag, ligature.characters) }
            .onDrag { dragItem(ligature) }
            .contextMenu {
                Button("Copy Characters", systemImage: "doc.on.clipboard") { copy(ligature.text, shown: "“\(ligature.text)”") }
                Button("Copy as Vector", systemImage: "doc.on.clipboard") { copyVector(ligature) }
                Button("Copy Unicode", systemImage: "doc.on.clipboard") {
                    copy(CharacterCodes.unicode(ligature.characters), shown: CharacterCodes.unicode(ligature.characters))
                }
            }
        .accessibilityElement()
        .accessibilityLabel("Ligature of \(ligature.text)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { popover = (group.tag, ligature.characters) }
    }

    private func details(_ ligature: Ligature, in group: LigatureGroup) -> some View {
        VStack(spacing: 10) {
            GlyphImage(face: face, glyph: ligature.glyph, size: 96, weight: weight, variations: variations)
                .frame(width: 220, height: 130)
                .contentShape(.rect)
                .onDrag { dragItem(ligature) }
            Text(ligature.characters.compactMap(Unicode.Scalar.init).map { String(Character($0)) }.joined(separator: " + "))
                .font(.title3)
            Text(CharacterCodes.unicode(ligature.characters))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(group.name) (\(group.tag))").font(.callout).foregroundStyle(.secondary)
            if let character = characters[ligature.glyph] {
                Text("Also \(CharacterCodes.unicode(character))\(GlyphSection.name(of: character).map { ", \($0.capitalized)" } ?? "")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            // A ligature has no code of its own: what's copied is its characters, which the font draws as this glyph
            // where its feature is on.
            VStack {
                Button("Copy Characters", systemImage: "doc.on.doc") { copy(ligature.text, shown: "“\(ligature.text)”") }
                    .help("Copies “\(ligature.text)”, which this font draws as this ligature with \(group.name) on")
                Button("Copy as Vector", systemImage: "doc.on.doc") { copyVector(ligature) }
                    .disabled(outline(ligature) == nil)
                    .help("Copies the ligature’s outline, to paste into a design app as a shape you can edit, or as SVG code")
            }
            .buttonStyle(StillPushButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: 300)
    }

    /// As for a glyph: copies, closes the popover and says what was copied.
    private func copy(_ text: String, shown: String) {
        GlyphsSection.copy(text)
        popover = nil
        model.showToast("\(shown) copied to clipboard")
    }

    private func copyVector(_ ligature: Ligature) {
        guard let outline = outline(ligature) else { return NSSound.beep() }
        GlyphVectors.copy(outline)
        popover = nil
        model.showToast("“\(ligature.text)” copied to clipboard as a vector")
    }

    private func outline(_ ligature: Ligature) -> GlyphOutline? {
        GlyphVectors.outline(ligature.glyph, face: face, weight: weight, variations: variations)
    }

    /// The ligature as an SVG file, named after the style and the glyph, or its characters: "Inter Regular f_i.svg".
    private func dragItem(_ ligature: Ligature) -> NSItemProvider {
        let fallback = ligature.characters.compactMap(Unicode.Scalar.init).map { String(Character($0)) }.joined(separator: "_")
        return GlyphVectors.dragItem(outline(ligature), style: face.fullName, fallback: fallback)
    }
}

/// One glyph of a face, by its ID: a ligature or an alternate has no character of its own to set. Drawn as text is,
/// not filled from its outline, which came out a quarter lighter than the characters set next to it, as macOS
/// thickens text a little when it draws it. Centred on the font's ascender and descender, so glyphs side by side
/// share a baseline, and scaled down when it's wider than the room.
struct GlyphImage: View {
    let face: FontFace
    let glyph: CGGlyph
    let size: CGFloat
    var weight: Double = 400
    var variations: [String: Double] = [:]

    var body: some View {
        Canvas { context, area in
            let font = FontLoader.shared.font(face, size: size, weight: weight, variations: variations)
            var glyph = glyph
            var bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
            guard !bounds.isEmpty else { return }
            // The font's ascent and descent, or as far as the glyph reaches past them: all of it fits the cell.
            let ascent = max(CTFontGetAscent(font), bounds.maxY), descent = max(CTFontGetDescent(font), -bounds.minY)
            let scale = min(1, (area.width - 6) / max(bounds.width, 1), area.height / max(ascent + descent, 1))
            let x = (area.width - bounds.width * scale) / 2 - bounds.minX * scale
            let baseline = (area.height + (ascent - descent) * scale) / 2
            let color = Color.primary.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                cg.setFillColor(color)
                // From the canvas's top-left origin to the glyph's baseline, with y going up.
                cg.translateBy(x: x, y: baseline)
                cg.scaleBy(x: scale, y: -scale)
                var origin = CGPoint.zero
                CTFontDrawGlyphs(font, &glyph, &origin, 1, cg)
            }
        }
        .accessibilityHidden(true)
    }
}
