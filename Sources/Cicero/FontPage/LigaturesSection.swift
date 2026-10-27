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
    /// The family's ID, for the ligatures copied (see `SampleGlyph`).
    let family: String
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
                HStack(spacing: 4) {
                    Text(group.name).font(.headline)
                    Text("– \(group.ligatures.count.formatted())").font(.callout).foregroundStyle(.secondary)
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
        let shown = Array(ligatures)
        // The characters in its tooltip; a long one is scaled down to fit, 2 pt clear of the cell's sides.
        let actions = GridRowActions(open: { popover = (group.tag, shown[$0].characters) }, menu: { menu(shown[$0], in: group) },
                                     file: { dragFile(shown[$0]) }, help: { shown[$0].text })
        return GlyphGridRow(cells: shown.map { GridCell(content: .glyph($0.glyph), label: "Ligature of \($0.text)") }, columns: columns,
                            face: face, weight: weight, variations: variations, padding: 2, selected: column, actions: actions)
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .point(anchor)) {
            if let column {
                details(ligatures[ligatures.startIndex + column], in: group)
            }
        }
    }

    /// Its right-click menu, with Copy as Vector greyed out for one without an outline, as in the popover.
    private func menu(_ ligature: Ligature, in group: LigatureGroup) -> [GridMenuItem] {
        [
            GridMenuItem(title: "Copy Characters") { copyCharacters(ligature, in: group) },
            GridMenuItem(title: "Copy as Vector", isEnabled: outline(ligature) != nil) { copyVector(ligature, in: group) },
            GridMenuItem(title: "Copy Unicode") {
                copy(CharacterCodes.unicode(ligature.characters), shown: CharacterCodes.unicode(ligature.characters))
            },
        ]
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
            // where its feature is on, and the page's text where they're pasted (see `SampleGlyph`).
            VStack {
                Button("Copy Characters", systemImage: "doc.on.doc") { copyCharacters(ligature, in: group) }
                    .help("Copies “\(ligature.text)”, which shows as this ligature when pasted into the text above, and elsewhere with \(group.name) on")
                Button("Copy as Vector", systemImage: "doc.on.doc") { copyVector(ligature, in: group) }
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

    /// Its characters, which the page's text draws as the ligature where they're pasted there.
    private func copyCharacters(_ ligature: Ligature, in group: LigatureGroup) {
        sampleClip(ligature, in: group).copy()
        popover = nil
        model.showToast("“\(ligature.text)” copied to clipboard")
    }

    /// What it pastes as in the page's text: its characters, the ligature drawn in their place (see `SampleGlyph`).
    private func sampleClip(_ ligature: Ligature, in group: LigatureGroup) -> SampleClip {
        SampleClip(text: ligature.text, glyph: SampleGlyph(family: family, characters: ligature.text, face: face,
                                                           glyph: ligature.glyph, features: [group.tag]))
    }

    private func copyVector(_ ligature: Ligature, in group: LigatureGroup) {
        guard let outline = outline(ligature) else { return NSSound.beep() }
        GlyphVectors.copy(outline, style: face.fullName, fallback: Self.fileFallback(ligature), clip: sampleClip(ligature, in: group))
        popover = nil
        model.showToast("“\(ligature.text)” copied to clipboard as a vector")
    }

    private func outline(_ ligature: Ligature) -> GlyphOutline? {
        GlyphVectors.outline(ligature.glyph, face: face, weight: weight, variations: variations)
    }

    /// The ligature as an SVG file, named after the style and the glyph.
    private func dragItem(_ ligature: Ligature) -> NSItemProvider {
        GlyphVectors.dragItem(outline(ligature), style: face.fullName, fallback: Self.fileFallback(ligature))
    }

    /// The same file, for a ligature dragged out of the grid.
    private func dragFile(_ ligature: Ligature) -> URL? {
        GlyphVectors.dragFile(outline(ligature), style: face.fullName, fallback: Self.fileFallback(ligature))
    }

    /// What its file is called after when the font doesn't name the glyph: its characters, as in "Inter Regular f_i.svg".
    private static func fileFallback(_ ligature: Ligature) -> String {
        ligature.characters.compactMap(Unicode.Scalar.init).map { String(Character($0)) }.joined(separator: "_")
    }
}

/// One glyph of a face, by its ID: a ligature or an alternate has no character of its own to set. Drawn as text is,
/// centred on the font's ascender and descender and scaled down when it's wider than the room (see `GlyphDrawing`).
struct GlyphImage: View {
    let face: FontFace
    let glyph: CGGlyph
    let size: CGFloat
    var weight: Double = 400
    var variations: [String: Double] = [:]

    var body: some View {
        Canvas { context, area in
            let font = FontLoader.shared.font(face, size: size, weight: weight, variations: variations)
            let color = Color.primary.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                GlyphDrawing.draw(glyph, font: font, in: CGRect(origin: .zero, size: area), color: color, into: cg)
            }
        }
        .accessibilityHidden(true)
    }
}
