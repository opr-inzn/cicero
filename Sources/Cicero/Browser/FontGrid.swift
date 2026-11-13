import CiceroCore
import SwiftUI

struct FontGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.infoPanelShown) private var infoShown
    @Environment(\.displayScale) private var scale
    @Environment(\.isCovered) private var isCovered
    @State private var coveredHidden: CGFloat?
    let families: [Family]
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool
    @State private var gridRoom = GridRoom(width: 0, infoShown: 0)
    @State private var visibleHeight: CGFloat = 0
    @State private var position = ScrollPosition(idType: String.self)
    @State private var shown: Shown?

    static let spacing: CGFloat = 12
    static let padding: CGFloat = 10
    static let verticalPadding: CGFloat = 14
    static let mostColumns = 5
    static let sampleHeightPerWidth: CGFloat = 0.36

    struct Measure {
        var above: CGFloat
        var below: CGFloat
        var width: CGFloat

        init(_ sample: String, size: Double) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: NSFont.systemFont(ofSize: size)]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            above = ink.isEmpty ? size * 0.7 : max(ink.maxY, 0)
            below = ink.isEmpty ? 0 : max(-ink.minY, 0)
            width = CTLineGetTypographicBounds(line, nil, nil, nil)
        }

        func height(size: Double) -> CGFloat { above + below + size * 0.25 + 44 }

        func fit(size: Double, ratio: CGFloat?, restingTile: CGFloat, drawn: Double) -> SampleFit {
            let room = minimumWidth(size: size, ratio: ratio) - padding * 2 - 8
            return SampleFit(width: min(room, restingTile - padding * 2 - 8), factor: drawn / size)
        }

        var baselineBelowCentre: CGFloat { (above - below) / 2 }

        func minimumWidth(size: Double, ratio: CGFloat?) -> CGFloat {
            max(size + 186, width * 1.1 + padding * 2 + 8, (ratio ?? 0) * size + padding * 2 + 8)
        }
    }

    static func infoPanelNarrowing(shown: CGFloat, scale: CGFloat) -> CGFloat {
        InfoPanelOverlay.room(shown: shown, scale: scale) + cardsTrailing(infoShown: shown, scale: scale) - InfoPanelOverlay.top
    }

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
        let factor = tile != restingTile ? tile / restingTile : nil
        let fit = measure.fit(size: preview.size, ratio: ratio, restingTile: restingTile,
                              drawn: factor.map { GridScale.drawn(preview.size, factor: $0) } ?? preview.size)
        let inputs = sampleInputs
        let pinned = model.similarFamilyID.flatMap { id in families.first?.id == id ? families.first : nil }
        let rowWidth = CGFloat(count) * (tile + Self.spacing) - Self.spacing
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: Self.spacing), count: count), spacing: Self.spacing) {
                    ForEach(pinned == nil ? families[...] : families.dropFirst()) { family in
                        Tile(family: family, sampleText: shown.text, sampleHeight: sampleHeight, baselineBelowCentre: measure.baselineBelowCentre, fit: fit, isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                            .onAppear { ReadAhead.around(family, in: families) }
                    }
                }
                .scrollTargetLayout()
                .frame(width: rowWidth)
                // As wide as the scroll view leaves, never the tiles': measured from the tiles, a grid as wide as before the Info panel opened kept its columns and pushed the window's panes aside.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: GridRoom.self) { [infoShown] in GridRoom(width: $0.size.width, infoShown: infoShown) } action: { gridRoom = $0 }
                .cardsPadding(infoShown: infoShown, scale: scale, top: pinned == nil)
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .modifier(PinnedBar(isShown: pinned != nil, infoShown: infoShown, scale: scale) {
                if let pinned {
                    Tile(family: pinned, sampleText: shown.text, sampleHeight: measure.height(size: preview.size), baselineBelowCentre: measure.baselineBelowCentre, fit: fit, isSelected: model.selectedIDs.contains(pinned.id), model: model)
                        .modifier(FamilyItem(family: pinned, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                        .frame(width: rowWidth)
                }
            })
            .visibleHeight($visibleHeight)
            .task(id: inputs) { await measureSamples(inputs) }
            .onChange(of: factor, initial: true) { GridScale.shared.factor = factor }
            .onChange(of: isCovered, initial: true) { coveredHidden = isCovered ? SidebarRoom.shared.hiddenWidth : nil }
            .onDisappear { GridScale.shared.factor = nil }
            .modifier(KeepsTopOnResize(position: $position))
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy, position: $position, layout: .grid(columns: count), pinned: pinned?.id))
        }
    }

    private var sampleInputs: Int {
        var hasher = Hasher()
        hasher.combine(model.library.fingerprint)
        hasher.combine(model.data.showSystemFonts)
        hasher.combine(model.data.showCreativeCloudFonts)
        hasher.combine(preview.sampleText)
        return hasher.finalize()
    }

    private var sampleText: String {
        preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText
    }

    private func measureSamples(_ inputs: Int) async {
        let text = sampleText
        if SampleWidths.shared.hasMeasured(inputs) {
            shown = Shown(text: text, ratio: SampleWidths.shared.listRatio)
            return
        }
        let families = model.library.families, data = model.data
        let axes = model.familyAxes.mapValues { (face: $0.face, values: $0.values) }
        let samples = await Task.detached(priority: .userInitiated) {
            SampleWidths.measured(of: families.filter(data.lists)).map { family in
                let (style, weight) = family.previewStyle(for: SearchQuery(""))
                let variations = axes[family.id].flatMap { $0.face == style.id ? $0.values : nil } ?? [:]
                return SampleWidths.Sample(face: style.face, text: text, weight: weight, variations: variations, features: [])
            }
        }.value
        guard !Task.isCancelled else { return }
        let meanwhile = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { shown = Shown(text: text, ratio: SampleWidths.shared.listRatio) }
        }
        defer { meanwhile.cancel() }
        // A `Task` isn't cancelled with the one that made it: left to run, it would show this text after newer text.
        let scriptSamples = model.scriptSamples
        let ratio = await withTaskCancellationHandler {
            await SampleWidths.shared.measure(inputs, samples: samples, scriptSamples: scriptSamples)
        } onCancel: {
            meanwhile.cancel()
        }
        guard !Task.isCancelled else { return }
        shown = Shown(text: text, ratio: ratio)
    }

    private func layout(minimum: CGFloat) -> (columns: Int, width: CGFloat, restingWidth: CGFloat) {
        let gridWidth = gridRoom.width
        let hidden = isCovered ? coveredHidden ?? SidebarRoom.shared.hiddenWidth : SidebarRoom.shared.hiddenWidth
        let resting = gridWidth + Self.infoPanelNarrowing(shown: gridRoom.infoShown, scale: scale) - hidden
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

@Observable
final class GridScale {
    static let shared = GridScale()
    var factor: CGFloat?

    static func drawn(_ size: Double, factor: CGFloat) -> Double {
        (size * factor + 1e-6).rounded(.down)
    }

    static func chosen(drawing drawn: Double, factor: CGFloat) -> Double {
        (drawn / factor - 1e-6).rounded(.up)
    }
}

@Observable
final class SidebarRoom {
    static let shared = SidebarRoom()
    var detailStart: CGFloat? {
        didSet { moved() }
    }
    var sidebar: CGRect? {
        didSet {
            if let sidebar, sidebar.minX > inset { inset = sidebar.minX }
            moved()
        }
    }
    // Set from AppKit the moment the sidebar starts to slide: SwiftUI's column visibility changes only once it has, and on macOS 15 SwiftUI's sidebar stays put while AppKit's view around it narrows.
    private var isCollapsed = false
    private var isShowing = false
    private var beside: CGFloat?
    private var inset: CGFloat = 0
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var settling: Task<Void, Never>?

    var hiddenWidth: CGFloat {
        guard isCollapsed || isShowing, let room, let detailStart else { return 0 }
        let hidden = room - detailStart
        return hidden >= 1 ? hidden : 0
    }

    var isSliding: Bool {
        guard isCollapsed || isShowing, let room, let detailStart else { return false }
        return room - detailStart >= 1 && detailStart >= 0.5
    }

    private var room: CGFloat? {
        sidebar.map { $0.width + (beside ?? inset) }
    }

    func watch(_ item: NSSplitViewItem) {
        isCollapsed = item.isCollapsed
        observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
            guard let collapsed = change.newValue else { return }
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

struct SampleFit: Equatable {
    var width: CGFloat
    var factor: CGFloat

    func scale(_ sample: SampleWidths.Sample, text: String, in font: CTFont) -> CGFloat {
        let wide = SampleWidths.ratio(of: sample, text: text, in: font) * CTFontGetSize(font)
        return (wide > width ? width / wide : 1) * factor
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
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
            let (style, weight) = model.previewStyle(of: family)
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
                        scale: { fit.scale(sample, text: text, in: $0) }, showsPlaceholder: true
                    )
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.4)
                    // Its whole line, though that's higher than the sample: proposed less, it shrank to fit, drawn below the baseline it reported.
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

struct FamilyCard: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: .rect(cornerRadius: 14))
            // Opaque, so a card dragged to the sidebar looks as it does here rather than all but see-through.
            .background(Color.canvas, in: .rect(cornerRadius: 14))
            .overlay {
                if isSelected { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2) }
            }
    }
}

extension View {
    func cardsPadding(infoShown: CGFloat, scale: CGFloat, top: Bool = true) -> some View {
        padding(top ? [.leading, .vertical] : [.leading, .bottom], InfoPanelOverlay.top)
            .padding(.trailing, FontGrid.cardsTrailing(infoShown: infoShown, scale: scale))
    }
}
