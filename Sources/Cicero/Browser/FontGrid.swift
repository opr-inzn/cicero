import CiceroCore
import SwiftUI

/// Tiles with a short sample in each family, for scanning many fonts at once.
struct FontGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.infoPanelShown) private var infoShown
    @Environment(\.displayScale) private var scale
    let families: [Family]
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool
    /// The rows' width, with how far the Info panel was in when it was measured, which the rows' width is narrower by: the
    /// two together, rather than the width measured with how far in the panel is by now, a frame further on its way.
    @State private var gridRoom = GridRoom(width: 0, infoShown: 0)
    @State private var visibleHeight: CGFloat = 0
    /// The text the tiles show, with how wide the library's samples of it are (`SampleWidths.listRatio`). A new preview
    /// text is shown once that's measured, a moment later, so the tiles take its layout and fit the widest fonts to it at
    /// once: shown before, the tiles took its width in the system font, the widest fonts were drawn that wide, and grew
    /// once it was measured. Nil until the grid has measured; a text that takes over 0.3 s is shown before.
    @State private var shown: Shown?

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

        init(_ sample: String, size: Double) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: NSFont.systemFont(ofSize: size)]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // Text with no letters, spaces say: a capital's height.
            above = ink.isEmpty ? size * 0.7 : max(ink.maxY, 0)
            below = ink.isEmpty ? 0 : max(-ink.minY, 0)
            width = CTLineGetTypographicBounds(line, nil, nil, nil)
        }

        /// The sample's height: its letters and room above and below them, which small type gets more of.
        func height(size: Double) -> CGFloat { above + below + size * 0.25 + 44 }

        /// The widest a font's sample is drawn with the sidebar shown and the Info panel shut: as wide as a tile as narrow as
        /// it can be has room for, in tiles `restingTile` wide, which goes up with the size, not with the tiles, as they stay
        /// as wide as they are until a row has room for one fewer or one more. With the sidebar hidden or the panel open,
        /// every sample at `drawn` alike.
        func fit(size: Double, ratio: CGFloat?, restingTile: CGFloat, drawn: Double) -> SampleFit {
            let room = minimumWidth(size: size, ratio: ratio) - padding * 2 - 8
            return SampleFit(width: min(room, restingTile - padding * 2 - 8), factor: drawn / size)
        }

        /// How far below the middle of the sample the baseline is, so that its letters are centred in it.
        var baselineBelowCentre: CGFloat { (above - below) / 2 }

        /// How narrow a tile can be: the size and 186 pt more, as wide as the sample text in the system font with a little
        /// to spare, and as wide as the families listed need for all but the widest twentieth of them to be drawn at the
        /// size (`SampleWidths.listRatio`, per point of the size) with 28 pt to spare.
        func minimumWidth(size: Double, ratio: CGFloat?) -> CGFloat {
            max(size + 186, width * 1.1 + padding * 2 + 8, (ratio ?? 0) * size + padding * 2 + 8)
        }
    }

    /// How much narrower the rows are with the Info panel `shown` of the way in: the room `InfoPanelInset` makes for it,
    /// and `cardsPadding`'s gap beside it in place of the margin at the window's edge, on whole pixels as they're laid out.
    static func infoPanelNarrowing(shown: CGFloat, scale: CGFloat) -> CGFloat {
        InfoPanelOverlay.room(shown: shown, scale: scale) + cardsTrailing(infoShown: shown, scale: scale) - InfoPanelOverlay.top
    }

    /// Beside the last tile or card: the margin at the window's edge, or one gap between cards from the Info panel, whose own
    /// margin makes up the rest, in between while it slides; on whole pixels.
    static func cardsTrailing(infoShown: CGFloat, scale: CGFloat) -> CGFloat {
        let beside = spacing - InfoPanelOverlay.gap
        return ((InfoPanelOverlay.top + (beside - InfoPanelOverlay.top) * infoShown) * scale).rounded() / scale
    }

    var body: some View {
        let shown = shown ?? Shown(text: sampleText, ratio: SampleWidths.shared.listRatio)
        let measure = Measure(shown.text, size: preview.size)
        let ratio = shown.ratio
        let (count, tile, restingTile) = layout(minimum: measure.minimumWidth(size: preview.size, ratio: ratio))
        let sampleHeight = max(measure.height(size: preview.size), restingTile * Self.sampleHeightPerWidth)
        // Bigger or smaller by as much as the sidebar hidden or the Info panel open makes the tiles wider or narrower.
        let factor = tile != restingTile ? tile / restingTile : nil
        let fit = measure.fit(size: preview.size, ratio: ratio, restingTile: restingTile,
                              drawn: factor.map { GridScale.drawn(preview.size, factor: $0) } ?? preview.size)
        let inputs = sampleInputs
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: Self.spacing), count: count), spacing: Self.spacing) {
                    ForEach(families) { family in
                        Tile(family: family, sampleText: shown.text, sampleHeight: sampleHeight, baselineBelowCentre: measure.baselineBelowCentre, fit: fit, isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                    }
                }
                .scrollTargetLayout()
                .frame(width: CGFloat(count) * (tile + Self.spacing) - Self.spacing)
                // As wide as the scroll view leaves, never the tiles': measured from the tiles, a grid as wide as
                // before the Info panel opened kept its columns and pushed the window's panes aside.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: GridRoom.self) { [infoShown] in GridRoom(width: $0.size.width, infoShown: infoShown) } action: { gridRoom = $0 }
                .cardsPadding(infoShown: infoShown, scale: scale)
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .visibleHeight($visibleHeight)
            .task(id: inputs) { await measureSamples(inputs) }
            .onChange(of: factor, initial: true) { GridScale.shared.factor = factor }
            .onDisappear { GridScale.shared.factor = nil }
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy, layout: .grid(columns: count)))
        }
    }

    /// What the tiles' width is measured from: the families All Fonts lists, the text and the weight. Not the sidebar
    /// selection or the search, so the tiles keep their width and the rows their number from one list to the next.
    private var sampleInputs: Int {
        var hasher = Hasher()
        hasher.combine(model.library.fingerprint)
        hasher.combine(model.data.showSystemFonts)
        hasher.combine(model.data.showCreativeCloudFonts)
        hasher.combine(preview.sampleText)
        hasher.combine(preview.weight)
        return hasher.finalize()
    }

    /// The preview text, or the tiles' own when it's empty.
    private var sampleText: String {
        preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText
    }

    /// Has the samples of the families All Fonts lists measured, so the tiles are wide enough for them (see
    /// `SampleWidths`): in the styles the tiles show without a search, before the text in a font's own script. Then shows
    /// the text with them.
    private func measureSamples(_ inputs: Int) async {
        let text = sampleText
        let samples = model.library.families.filter(model.data.lists).map { family in
            let (style, weight) = family.previewStyle(for: SearchQuery(""), weight: preview.weight)
            return SampleWidths.Sample(face: style.face, text: text, weight: weight, variations: model.variations(for: family, face: style.id), features: [])
        }
        // Should that take a while, as when the files are first read, the text in the meantime with the width as it is.
        let meanwhile = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { shown = Shown(text: text, ratio: SampleWidths.shared.listRatio) }
        }
        defer { meanwhile.cancel() }
        let ratio = await SampleWidths.shared.measure(inputs, samples: samples, scriptSamples: model.scriptSamples)
        guard !Task.isCancelled else { return }
        shown = Shown(text: text, ratio: ratio)
    }

    /// The tiles in a row, also for ↑/↓, and their width: as many as fit at `minimum` in the rows the grid has with the
    /// sidebar shown and the Info panel shut, from one to five, as wide as fills them, however many families there are.
    /// Hiding the sidebar makes the tiles wider and opening the panel narrower, never more or fewer, and not higher or
    /// lower: `restingWidth`, the width they have with the sidebar shown and the panel shut, sets their height.
    private func layout(minimum: CGFloat) -> (columns: Int, width: CGFloat, restingWidth: CGFloat) {
        let gridWidth = gridRoom.width
        let resting = gridWidth + Self.infoPanelNarrowing(shown: gridRoom.infoShown, scale: scale) - SidebarRoom.shared.hiddenWidth
        guard gridWidth > 0, resting > 0 else { return (1, minimum, minimum) }
        let count = min(Self.mostColumns, max(1, Int((resting + Self.spacing) / (minimum + Self.spacing))))
        let width = { (row: CGFloat) in (row - Self.spacing * CGFloat(count - 1)) / CGFloat(count) }
        return (count, width(gridWidth), width(resting))
    }

    nonisolated struct GridRoom: Equatable {
        var width: CGFloat
        var infoShown: CGFloat
    }

    struct Shown {
        var text: String
        var ratio: CGFloat?
    }
}

/// The size the grid draws at while the sidebar hidden or the Info panel open makes its tiles wider or narrower, which
/// Preview Options' Size shows then: the size chosen, bigger or smaller by as much as the tiles are, rounded down to a
/// whole point so it's never too big for them. The size chosen is kept for the list, specimens and the grid with the
/// sidebar shown and the panel shut; a size picked meanwhile sets the smallest whole size chosen that the grid draws at
/// that size.
@Observable
final class GridScale {
    static let shared = GridScale()
    /// How much wider or narrower the tiles are; nil while the sidebar is shown and the panel shut, or the grid isn't showing.
    var factor: CGFloat?

    static func drawn(_ size: Double, factor: CGFloat) -> Double {
        (size * factor + 1e-6).rounded(.down)
    }

    static func chosen(drawing drawn: Double, factor: CGFloat) -> Double {
        (drawn / factor - 1e-6).rounded(.up)
    }
}

/// How much of the sidebar's room the browser has: none while the sidebar is shown, all of it while it's hidden, and more
/// and more as it slides out. The grid keeps the rows it has with the sidebar shown and draws them wider and bigger by as
/// much (see `FontGrid.layout`), as the Info panel draws them narrower and smaller, so the sidebar sliding in and out
/// zooms the grid rather than rearranging it. Dragging the sidebar wider or narrower rearranges it, as resizing the
/// window does.
@Observable
final class SidebarRoom {
    static let shared = SidebarRoom()
    /// Where the browser starts in the window: beside the sidebar while it's shown or slides, at 0 while it's hidden.
    var detailStart: CGFloat? {
        didSet { moved() }
    }
    /// Where the sidebar is in the window. As wide as it is shown, also while it slides and while it's hidden.
    var sidebar: CGRect? {
        didSet {
            if let sidebar, sidebar.minX > inset { inset = sidebar.minX }
            moved()
        }
    }
    /// Set by AppKit the moment the sidebar starts to slide out or in; SwiftUI's own column visibility changes only
    /// once it has. While it slides, the browser's edge is the only sign of how far: on macOS 15, SwiftUI's sidebar
    /// stays put while AppKit's view around it narrows.
    private var isCollapsed = false
    /// From the moment the sidebar starts to slide in until the browser is beside it.
    private var isShowing = false
    /// How much further from the window's edge the browser starts than the sidebar is wide while it's shown: 8 pt on
    /// macOS 26, where the sidebar floats 8 pt in, 1 pt on macOS 15, for its divider. Taken while it's shown and still.
    private var beside: CGFloat?
    /// The furthest in the sidebar has been from the window's edge: `beside`, but for macOS 15's divider, until there's one.
    private var inset: CGFloat = 0
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// How much wider the browser is than with the sidebar shown; less than a point is none.
    var hiddenWidth: CGFloat {
        // Shown: none, also while it's dragged wider or narrower and the browser's edge moves a step before it.
        guard isCollapsed || isShowing, let room, let detailStart else { return 0 }
        let hidden = room - detailStart
        return hidden >= 1 ? hidden : 0
    }

    /// Where the browser starts with the sidebar shown at the width it has.
    private var room: CGFloat? {
        sidebar.map { $0.width + (beside ?? inset) }
    }

    /// Watches the split view item the sidebar is in, which says when it starts to slide.
    func watch(_ item: NSSplitViewItem) {
        isCollapsed = item.isCollapsed
        observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
            guard let collapsed = change.newValue else { return }
            // At once, before the browser has moved, so it's still beside the sidebar when that starts to slide out.
            MainActor.assumeIsolated { self?.collapsedChanged(collapsed) }
        }
    }

    private func collapsedChanged(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        if collapsed, !isShowing { measureBeside() }
        isCollapsed = collapsed
        isShowing = !collapsed
        if isShowing { settleSoon() }
    }

    private func moved() {
        if isShowing {
            if let room, let detailStart, detailStart >= room - 0.5 { isShowing = false } else { settleSoon() }
        }
        if !isCollapsed, !isShowing { measureBeside() }
    }

    private func measureBeside() {
        guard let sidebar, let detailStart, detailStart >= 1 else { return }
        beside = detailStart - sidebar.width
    }

    /// Ends sliding in once the browser's edge has been still for a moment, should it stop short of `room`.
    private func settleSoon() {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, isShowing else { return }
            isShowing = false
            moved()
        }
    }
}

/// Finds the split view item the sidebar is in, from a view inside it, for `SidebarRoom` to watch.
struct SidebarItemReader: NSViewRepresentable {
    func makeNSView(context: Context) -> ReaderView { ReaderView() }
    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSSplitView) { view = current.superview }
            guard let controller = (view as? NSSplitView)?.delegate as? NSSplitViewController,
                  let item = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) else { return }
            SidebarRoom.shared.watch(item)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// How big a font's sample is drawn in the grid: at the preview size, or, for one of the few fonts too wide for the tiles
/// (see `Measure.minimumWidth`), smaller, until it's `width` wide. `width` goes up with the size, so such a font grows and
/// shrinks with it like the rest; shrunk to fit its tile instead, it stopped growing while the rest went on, until the tiles
/// got fewer. While the sidebar hidden or the Info panel open makes the tiles wider or narrower, every sample is bigger or
/// smaller by as much (see `GridScale`), so all of them keep their sizes to one another, rather than the wider ones being
/// held at their tiles' edges.
struct SampleFit {
    var width: CGFloat
    var factor: CGFloat

    /// What to multiply the size by, for `sample`, drawn as `text` in `font` at that size.
    func scale(_ sample: SampleWidths.Sample, text: String, in font: CTFont) -> CGFloat {
        let wide = SampleWidths.ratio(of: sample, text: text, in: font) * CTFontGetSize(font)
        return (wide > width ? width / wide : 1) * factor
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    /// The preview text the grid shows (see `FontGrid.shown`).
    let sampleText: String
    let sampleHeight: CGFloat
    let baselineBelowCentre: CGFloat
    let fit: SampleFit
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
            // (see `Measure`), at the preview size unless it's wider than the tiles have room for (see `SampleFit`). Not
            // clipped: what reaches past it runs into the padding.
            let sample = SampleWidths.Sample(face: style.face, text: sampleText, weight: weight,
                                             variations: model.variations(for: family, face: style.id), features: model.searchFeatures)
            let text = model.scriptSamples.text(sample.text, for: style.face)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: sampleHeight)
                .alignmentGuide(.firstTextBaseline) { $0.height / 2 + baselineBelowCentre }
                .overlay(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
                    FontText(
                        text: text, face: style.face,
                        size: preview.size, weight: weight, variations: sample.variations, features: sample.features,
                        scale: { fit.scale(sample, text: text, in: $0) }
                    )
                    .foregroundStyle(Color.ink)
                    // Only where its letters fit but its line doesn't: a font whose first or last letter leaves a lot of room
                    // beside it.
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
    /// Around the grid's tiles and the specimens' cards: 16 pt, and beside the Info panel one gap between cards, whose
    /// margin makes up the rest (see `FontGrid.cardsTrailing`; `infoShown`, see `infoPanelShown`).
    func cardsPadding(infoShown: CGFloat, scale: CGFloat) -> some View {
        padding([.leading, .vertical], InfoPanelOverlay.top)
            .padding(.trailing, FontGrid.cardsTrailing(infoShown: infoShown, scale: scale))
    }
}
