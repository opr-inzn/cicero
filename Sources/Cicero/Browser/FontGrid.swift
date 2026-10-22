import CiceroCore
import SwiftUI

/// Tiles with a short sample in each family, for scanning many fonts at once.
struct FontGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let families: [Family]
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool
    @State private var gridWidth: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    /// Between tiles, and between the last column and the Info panel.
    static let spacing: CGFloat = 12
    /// Around a tile's contents: little, so the sample can be big.
    static let padding: CGFloat = 10
    /// Above and below a tile's contents: a little more, so the tiles don't feel cramped.
    static let verticalPadding: CGFloat = 14
    /// The narrowest a tile goes, for its name and caption.
    static let narrowest: CGFloat = 160
    static let mostColumns = 5
    /// How narrow a tile can be for its sample: the sample's width at the preview size in the system font, with a little to
    /// spare, so the type fills the tile without being made smaller; never narrower than the sample is high, so a single
    /// letter gets a square of its own.
    static func minimumWidth(sample: String, size: Double, kerning: Double) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: font, .kern: kerning]))
        let text = CTLineGetTypographicBounds(line, nil, nil, nil) * 1.1 + padding * 2 + 8
        return max(narrowest, text, sampleHeight(size: size))
    }

    /// The sample's height at a preview size: its line and some room above and below, so the tiles follow the type at
    /// every size without crowding it.
    static func sampleHeight(size: Double) -> CGFloat { size * 1.6 + 16 }

    /// How much narrower the rows are while the Info panel is open: the room `InfoPanelInset` makes for it, and
    /// `cardsPadding`'s gap beside it in place of the margin at the window's edge.
    private static let infoPanelRoom = InfoPanelOverlay.width + InfoPanelOverlay.gap * 2
        + (spacing - InfoPanelOverlay.gap) - InfoPanelOverlay.top

    var body: some View {
        let sample = preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText
        let (count, tile) = layout(minimum: Self.minimumWidth(sample: sample, size: preview.size, kerning: preview.kerning(at: preview.size)))
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: Self.spacing), count: count), spacing: Self.spacing) {
                    ForEach(families) { family in
                        Tile(family: family, sampleHeight: Self.sampleHeight(size: preview.size), isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                    }
                }
                .scrollTargetLayout()
                .frame(width: CGFloat(count) * (tile + Self.spacing) - Self.spacing)
                // As wide as the scroll view leaves, never the tiles': measured from the tiles, a grid as wide as
                // before the Info panel opened kept its columns and pushed the window's panes aside.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                .cardsPadding(infoPresented: model.isInfoPresented)
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .visibleHeight($visibleHeight)
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy, layout: .grid(columns: count)))
        }
    }

    /// The tiles in a row, also for ↑/↓, and their width: as many as fit at `minimum`, from one to five, as wide as fills
    /// the rows, however many families there are. The Info panel keeps the columns the rows have without it, the tiles
    /// narrowing instead, as far as 0.6 times `minimum` (their sample shrinks to fit), and never below `narrowest`; past
    /// that it takes a column away.
    private func layout(minimum: CGFloat) -> (columns: Int, width: CGFloat) {
        guard gridWidth > 0 else { return (1, minimum) }
        let closed = gridWidth + (model.isInfoPresented ? Self.infoPanelRoom : 0)
        var count = min(Self.mostColumns, max(1, Int((closed + Self.spacing) / (minimum + Self.spacing))))
        func filling(_ count: Int) -> CGFloat { (gridWidth - Self.spacing * CGFloat(count - 1)) / CGFloat(count) }
        while count > 1 && filling(count) < max(Self.narrowest, minimum * 0.6) { count -= 1 }
        return (count, filling(count))
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let sampleHeight: CGFloat
    let isSelected: Bool
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                StatusTag(family: family)
                VariableTag(family: family)
                Spacer()
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            let face = family.face(nearestWeight: preview.weight).face
            FontText(
                text: model.scriptSamples.text(preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText, for: face),
                face: face,
                size: preview.size, weight: preview.weight, variations: model.variations(for: family),
                kerning: preview.kerning(at: preview.size)
            )
            // Only where the tiles can't be wide enough: a font far wider than the system font, a window too narrow for
            // one, text longer than a row, or the Info panel keeping the columns.
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity)
            // Not clipped: what reaches past the font's ascent and descent runs into the padding rather than being cut off.
            .frame(height: sampleHeight)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(family.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    TagDots(colors: model.tagColors(of: family))
                    let note = model.note(of: family), rating = model.rating(of: family)
                    if note != nil || rating != nil {
                        Spacer(minLength: 8)
                        NoteMark(note: note)
                        RatingStars(rating: rating)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(family.rangeLabel)
                        .lineLimit(1)
                        .help(family.rangeLabel)
                    Spacer(minLength: 0)
                    // The kinds of file: the tag above says it's variable.
                    Text(family.fileKinds)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, FontGrid.padding)
        .padding(.vertical, FontGrid.verticalPadding)
        .modifier(FamilyCard(isSelected: isSelected))
    }
}

/// A family's card in the grid and specimens: light grey, or tinted and outlined while it's selected. Opaque, on the
/// window's background, so a card dragged to the sidebar looks as it does here rather than all but see-through.
struct FamilyCard: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: .rect(cornerRadius: 14))
            .background(Color.canvas, in: .rect(cornerRadius: 14))
            .overlay {
                if isSelected { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2) }
            }
    }
}

extension View {
    /// Around the grid's tiles and the specimens' cards: 16 pt, and one gap between cards from the Info panel,
    /// whose margin makes up the rest.
    func cardsPadding(infoPresented: Bool) -> some View {
        padding([.leading, .vertical], InfoPanelOverlay.top)
            .padding(.trailing, infoPresented ? FontGrid.spacing - InfoPanelOverlay.gap : InfoPanelOverlay.top)
    }
}
