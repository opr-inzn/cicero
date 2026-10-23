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
    static let mostColumns = 5
    /// How high a tile's sample is at least, for each point of the tile's width: so wide tiles, two or three in a row,
    /// aren't flat, while narrow ones keep the height their letters need.
    static let sampleHeightPerWidth: CGFloat = 0.36

    /// The sample text in the system font at the preview size: how far its letters reach above the baseline and below it,
    /// and how wide it is. Every tile sets its sample by these, whatever its own font, so they all share one baseline.
    struct Measure {
        var above: CGFloat
        var below: CGFloat
        var width: CGFloat

        init(_ sample: String, size: Double, kerning: Double) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: NSFont.systemFont(ofSize: size), .kern: kerning]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // Text with no letters, spaces say: a capital's height.
            above = ink.isEmpty ? size * 0.7 : max(ink.maxY, 0)
            below = ink.isEmpty ? 0 : max(-ink.minY, 0)
            width = CTLineGetTypographicBounds(line, nil, nil, nil)
        }

        /// The sample's height: its letters and room above and below them, which small type gets more of.
        func height(size: Double) -> CGFloat { above + below + size * 0.25 + 44 }

        /// How far below the middle of the sample the baseline is, so that its letters are centred in it.
        var baselineBelowCentre: CGFloat { (above - below) / 2 }

        /// How narrow a tile can be: the size and 186 pt more, and as wide as the sample text with a little to spare, so it
        /// isn't made smaller to fit.
        func minimumWidth(size: Double) -> CGFloat { max(size + 186, width * 1.1 + padding * 2 + 8) }
    }

    /// How much narrower the rows are while the Info panel is open: the room `InfoPanelInset` makes for it, and
    /// `cardsPadding`'s gap beside it in place of the margin at the window's edge.
    private static let infoPanelRoom = InfoPanelOverlay.width + InfoPanelOverlay.gap * 2
        + (spacing - InfoPanelOverlay.gap) - InfoPanelOverlay.top

    var body: some View {
        let sample = preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText
        let measure = Measure(sample, size: preview.size, kerning: preview.kerning(at: preview.size))
        let (count, tile, closedTile) = layout(minimum: measure.minimumWidth(size: preview.size))
        let sampleHeight = max(measure.height(size: preview.size), closedTile * Self.sampleHeightPerWidth)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: Self.spacing), count: count), spacing: Self.spacing) {
                    ForEach(families) { family in
                        Tile(family: family, sampleHeight: sampleHeight, baselineBelowCentre: measure.baselineBelowCentre, isSelected: model.selectedIDs.contains(family.id), model: model)
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

    /// The tiles in a row, also for ↑/↓, and their width: as many as fit at `minimum` in the rows without the Info panel,
    /// from one to five, as wide as fills them, however many families there are. The panel makes the tiles narrower, never
    /// fewer, and not lower: `closedWidth`, the width they have without it, sets their height.
    private func layout(minimum: CGFloat) -> (columns: Int, width: CGFloat, closedWidth: CGFloat) {
        guard gridWidth > 0 else { return (1, minimum, minimum) }
        let closed = gridWidth + (model.isInfoPresented ? Self.infoPanelRoom : 0)
        let count = min(Self.mostColumns, max(1, Int((closed + Self.spacing) / (minimum + Self.spacing))))
        let width = { (row: CGFloat) in (row - Self.spacing * CGFloat(count - 1)) / CGFloat(count) }
        return (count, width(gridWidth), width(closed))
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let sampleHeight: CGFloat
    let baselineBelowCentre: CGFloat
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
            let (style, weight) = model.previewStyle(of: family, weight: preview.weight)
            // On one baseline in every tile, whatever each font's ascent and descent, where the sample's letters are centred
            // (see `Measure`). Not clipped: what reaches past it runs into the padding.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: sampleHeight)
                .alignmentGuide(.firstTextBaseline) { $0.height / 2 + baselineBelowCentre }
                .overlay(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
                    FontText(
                        text: model.scriptSamples.text(preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText, for: style.face),
                        face: style.face,
                        size: preview.size, weight: weight, variations: model.variations(for: family, face: style.id), features: model.searchFeatures,
                        kerning: preview.kerning(at: preview.size)
                    )
                    // Only where a tile can't be wide enough: a font far wider than the system font, text longer than a row,
                    // or the Info panel narrowing the tiles.
                    .minimumScaleFactor(0.4)
                    // Its whole line, though that's higher than the sample: proposed less, it shrank to fit, drawn below the
                    // baseline it reported.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
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
