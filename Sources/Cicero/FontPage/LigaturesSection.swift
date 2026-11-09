import CiceroCore
import CoreText
import SwiftUI

struct LigaturesSection: View {
    @Environment(AppModel.self) private var model
    let family: String
    let face: FontFace
    let weight: Double
    let variations: [String: Double]
    let columns: Int
    let groups: [LigatureGroup]
    let characters: [CGGlyph: UInt32]
    let generation: Int
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
                    Text("– \(group.ligatures.count.plain)").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 4)
            }
        }
    }

    private func ligatureRow(_ ligatures: ArraySlice<Ligature>, in group: LigatureGroup) -> some View {
        let column = popover.flatMap { shown in
            shown.tag == group.tag ? ligatures.firstIndex { $0.characters == shown.characters } : nil
        }.map { $0 - ligatures.startIndex }
        let shown = Array(ligatures)
        let actions = GridRowActions(open: { popover = (group.tag, shown[$0].characters) },
                                     details: { AnyView(details(shown[$0], in: group).environment(model)) },
                                     closed: { popover = nil }, menu: { menu(shown[$0], in: group) },
                                     file: { dragFile(shown[$0]) }, help: { shown[$0].text })
        return GlyphGridRow(cells: shown.map { GridCell(content: .glyph($0.glyph), label: "Ligature of \($0.text)") }, columns: columns,
                            face: face, generation: generation, weight: weight, variations: variations, padding: 2, selected: column,
                            actions: actions)
    }

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

    private func copy(_ text: String, shown: String) {
        GlyphsSection.copy(text)
        CellPopover.shared.close()
        model.showToast("\(shown) copied to clipboard")
    }

    private func copyCharacters(_ ligature: Ligature, in group: LigatureGroup) {
        sampleClip(ligature, in: group).copy()
        CellPopover.shared.close()
        model.showToast("“\(ligature.text)” copied to clipboard")
    }

    private func sampleClip(_ ligature: Ligature, in group: LigatureGroup) -> SampleClip {
        SampleClip(text: ligature.text, glyph: SampleGlyph(family: family, characters: ligature.text, face: face,
                                                           glyph: ligature.glyph, features: [group.tag]))
    }

    private func copyVector(_ ligature: Ligature, in group: LigatureGroup) {
        guard let outline = outline(ligature) else { return NSSound.beep() }
        GlyphVectors.copy(outline, style: face.fullName, fallback: Self.fileFallback(ligature), clip: sampleClip(ligature, in: group))
        CellPopover.shared.close()
        model.showToast("“\(ligature.text)” copied to clipboard as a vector")
    }

    private func outline(_ ligature: Ligature) -> GlyphOutline? {
        GlyphVectors.outline(ligature.glyph, face: face, weight: weight, variations: variations)
    }

    private func dragItem(_ ligature: Ligature) -> NSItemProvider {
        GlyphVectors.dragItem(outline(ligature), style: face.fullName, fallback: Self.fileFallback(ligature))
    }

    private func dragFile(_ ligature: Ligature) -> URL? {
        GlyphVectors.dragFile(outline(ligature), style: face.fullName, fallback: Self.fileFallback(ligature))
    }

    private static func fileFallback(_ ligature: Ligature) -> String {
        ligature.characters.compactMap(Unicode.Scalar.init).map { String(Character($0)) }.joined(separator: "_")
    }
}

struct GlyphImage: View {
    let face: FontFace
    let glyph: CGGlyph
    let size: CGFloat
    var weight: Double = 400
    var variations: [String: Double] = [:]

    var body: some View {
        Canvas { context, area in
            let font = FontLoader.shared.font(face, size: size, weight: weight, variations: variations)
            let color = Color.ink.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                GlyphDrawing.draw(glyph, font: font, in: CGRect(origin: .zero, size: area), color: color, into: cg)
            }
        }
        .accessibilityHidden(true)
    }
}
