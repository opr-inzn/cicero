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

    /// How much narrower the rows are while the Info panel is open: the room `InfoPanelInset` makes for it, and
    /// `cardsPadding`'s gap beside it in place of the margin at the window's edge.
    private static let infoPanelRoom = InfoPanelOverlay.width + InfoPanelOverlay.gap * 2
        + (spacing - InfoPanelOverlay.gap) - InfoPanelOverlay.top

    var body: some View {
        let tile = tileWidth(minimum: max(240, preview.size * 8))
        let count = columns(tile: tile)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: Self.spacing), count: count), spacing: Self.spacing) {
                    ForEach(families) { family in
                        Tile(family: family, isSelected: model.selectedIDs.contains(family.id), model: model)
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

    /// As wide as fills the rows, and up to 1.6 times the narrowest a tile goes. The Info panel keeps the columns
    /// the rows have without it, the tiles narrowing instead, as far as 0.6 times that (their sample shrinks to fit),
    /// and never below 240 points; past that it takes a column away.
    private func tileWidth(minimum: CGFloat) -> CGFloat {
        guard gridWidth > 0 else { return minimum }
        let closed = gridWidth + (model.isInfoPresented ? Self.infoPanelRoom : 0)
        var count = max(1, ((closed + Self.spacing) / (minimum + Self.spacing)).rounded(.down))
        func filling(_ count: CGFloat) -> CGFloat { (gridWidth - Self.spacing * (count - 1)) / count }
        while count > 1 && filling(count) < max(240, minimum * 0.6) { count -= 1 }
        return min(filling(count), minimum * 1.6, gridWidth)
    }

    /// Tiles in a row, also for ↑/↓: as many as fit, with half a point to spare for rounding where they fill it.
    private func columns(tile width: CGFloat) -> Int {
        max(1, Int((gridWidth + Self.spacing + 0.5) / (width + Self.spacing)))
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let isSelected: Bool
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusTag(family: family)
                Spacer()
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            FontText(
                text: preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText,
                face: family.face(nearestWeight: preview.weight).face,
                size: preview.size, weight: preview.weight, variations: model.variations(for: family),
                features: model.features(for: family), kerning: preview.kerning(at: preview.size)
            )
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: preview.size * 3.4)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(family.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    TagDots(colors: model.tagColors(of: family))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(family.rangeLabel)
                        .lineLimit(1)
                        .help(family.rangeLabel)
                    Spacer(minLength: 0)
                    Text(family.formatLabel)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
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
