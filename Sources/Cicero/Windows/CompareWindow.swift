import CiceroCore
import SwiftUI

enum CompareLayout: String, CaseIterable {
    case stacked, overlay

    var title: String {
        switch self {
        case .stacked: "Stacked"
        case .overlay: "Overlay"
        }
    }
}

/// Families next to each other, each in a style of its choosing: one row each on a shared baseline, or drawn over
/// each other in tints.
struct CompareWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("compare.layout") private var layout: CompareLayout = .stacked
    /// Files on a server read off the main thread for the samples (see `FontLoader.wouldWait`).
    @State private var read: Set<String> = []

    var body: some View {
        let entries = model.compareEntries.compactMap { entry in
            model.family(entry.familyID).map { family in
                (entry: entry, family: family, path: CompareSample.face(for: entry, in: family, preview: preview).face.path)
            }
        }
        // A family whose file is on a server joins the others once it's been read in the background.
        let waiting = entries.map(\.path).filter { !read.contains($0) && FontLoader.shared.wouldWait(for: $0) }
        let samples = entries.filter { !waiting.contains($0.path) }.map { CompareSample($0.entry, family: $0.family, model: model, preview: preview) }
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing to Compare", systemImage: "square.on.square",
                                       description: Text("Select two or more families and choose Fonts → Compare, or drop families here."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        switch layout {
                        case .stacked: StackedLayout(samples: samples)
                        case .overlay: OverlayLayout(samples: samples)
                        }
                    }
                    .padding(24)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color.canvas)
        .dropDestination(for: String.self) { names, _ in _ = model.addToCompare(names) }
        .task(id: waiting) {
            guard !waiting.isEmpty else { return }
            await FontLoader.shared.read(waiting)
            read.formUnion(waiting)
        }
        .navigationSubtitle(subtitle(entries.map(\.family)))
        .toolbar {
            ToolbarCapsule {
                ToolbarPicker("Layout", values: CompareLayout.allCases, selection: $layout, title: \.title,
                              help: "One row per font, or every font over each other")
            }
            ToolbarCapsule { PreviewOptionsButton() }
        }
    }
}

private extension CompareWindow {
    /// "2 families", and how many styles when a family is there in more than one: "2 families · 3 styles". One family
    /// for each sample.
    func subtitle(_ samples: [Family]) -> String {
        let families = Set(samples.map(\.id)).count
        let text = families == 1 ? "1 family" : "\(families) families"
        return samples.count > families ? "\(text) · \(samples.count) styles" : text
    }
}

/// One family's sample, set in the style chosen for it, else the one nearest the preview weight.
private struct CompareSample: Identifiable {
    static let tints: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .teal, .indigo, .brown, .cyan, .mint, .yellow]

    let family: Family
    let face: LibraryFace
    /// The style chosen; nil when it follows the preview weight.
    let style: FaceID?
    let line: TextLine
    let tint: Color
    let id: UUID

    init(_ entry: CompareEntry, family: Family, model: AppModel, preview: PreviewSettings) {
        self.family = family
        id = entry.id
        let chosen = Self.chosenStyle(of: entry, in: family)
        style = chosen?.id
        face = Self.face(for: entry, in: family, preview: preview)
        let weight = chosen.map(\.face.styleWeight) ?? preview.weight
        let font = FontLoader.shared.font(face.face, size: preview.size, weight: weight, variations: model.variations(for: family, face: face.id))
        line = TextLine(preview.sampleText.isEmpty ? "Hamburgefonstiv" : preview.sampleText, font: font, kerning: preview.kerning(at: preview.size))
        tint = Self.tints[entry.tint % Self.tints.count]
    }

    /// The style chosen for the family, if one was.
    static func chosenStyle(of entry: CompareEntry, in family: Family) -> LibraryFace? {
        entry.style.flatMap { style in family.faces.first { $0.id == style } }
    }

    /// The style its sample is set in: the one chosen, else the one nearest the preview weight.
    static func face(for entry: CompareEntry, in family: Family, preview: PreviewSettings) -> LibraryFace {
        chosenStyle(of: entry, in: family) ?? family.face(nearestWeight: preview.weight)
    }
}

/// One row per font; every row's baseline sits at the same offset, so the samples line up. Dragging a row
/// changes the order.
private struct StackedLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let ascent = samples.map(\.line.ascent).max() ?? 0
        let descent = samples.map(\.line.descent).max() ?? 0
        let overhang = samples.map(\.line.overhang).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + 2
        Reorderable(samples: samples, layout: AnyLayout(VStackLayout(alignment: .leading, spacing: 20)), axis: .vertical) { sample in
            row(sample, ascent: ascent, descent: descent, overhang: overhang, width: width)
        } lifted: { sample in
            // Opaque, so the rows it passes don't show through.
            row(sample, ascent: ascent, descent: descent, overhang: overhang, width: width)
                .background { Color.canvas.padding(-8) }
        }
    }

    private func row(_ sample: CompareSample, ascent: CGFloat, descent: CGFloat, overhang: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Glyphs reaching left of the start go into the margin, so the lines start level with the names.
            Canvas { context, _ in
                let color = Color.primary.resolve(in: context.environment).cgColor
                context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: overhang, y: ascent), color: color) }
            }
            .frame(width: overhang + width, height: ascent + descent)
            .padding(.leading, -overhang)
            SampleCaption(sample: sample, showsTint: false)
                .help("Drag to change the order")
        }
        .contentShape(.rect)
    }
}

/// Every sample over the others, each in its tint, on a shared baseline. Dragging a chip in the legend below changes
/// the order, so the last one is drawn on top.
private struct OverlayLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let ascent = samples.map(\.line.ascent).max() ?? 0
        let descent = samples.map(\.line.descent).max() ?? 0
        // Glyphs reaching left of the start go into the margin, as in the stacked rows, so the lines start level
        // with the legend.
        let overhang = samples.map(\.line.overhang).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + 2
        VStack(alignment: .leading, spacing: 16) {
            Canvas { context, size in
                var baseline = Path()
                baseline.move(to: CGPoint(x: overhang, y: crisp(ascent)))
                baseline.addLine(to: CGPoint(x: size.width, y: crisp(ascent)))
                context.stroke(baseline, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                for sample in samples {
                    let color = sample.tint.opacity(0.7).resolve(in: context.environment).cgColor
                    context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: overhang, y: ascent), color: color) }
                }
            }
            .frame(width: overhang + width, height: ascent + descent)
            .padding(.leading, -overhang)
            Reorderable(samples: samples, layout: AnyLayout(FlowLayout(spacing: 8, lineSpacing: 8)), axis: .horizontal) { sample in
                chip(sample)
                    .help("Drag to change the order")
            } lifted: { sample in
                chip(sample)
                    .background(Color.canvas, in: .capsule)
            }
            .frame(width: max(width, 480), alignment: .leading)
        }
    }

    private func chip(_ sample: CompareSample) -> some View {
        SampleCaption(sample: sample, showsTint: true)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary, in: .capsule)
    }

    /// Centres a one-point line on a pixel row.
    private func crisp(_ y: CGFloat) -> CGFloat { y.rounded() + 0.5 }
}

/// Samples laid out by `layout` that can be dragged to new places among each other. The dragged one follows
/// the pointer, leaving a gap where it will land, and the others make way as it passes their middle.
private struct Reorderable<Item: View, Lifted: View>: View {
    @Environment(AppModel.self) private var model
    let samples: [CompareSample]
    let layout: AnyLayout
    /// The way samples pass each other: down a column of rows, or along lines of chips.
    let axis: Axis
    /// A sample in its place.
    @ViewBuilder let item: (CompareSample) -> Item
    /// The sample under the pointer while it's dragged.
    @ViewBuilder let lifted: (CompareSample) -> Lifted
    private static var space: String { "compare.reorderable" }
    @State private var drag: SampleDrag?
    /// Where each sample is laid out, in this view's coordinates.
    @State private var frames: [UUID: CGRect] = [:]

    var body: some View {
        layout {
            ForEach(samples) { sample in
                item(sample)
                    .opacity(drag?.id == sample.id ? 0 : 1)
                    // Keeps the gap hit-testable, so the drag that started on it carries on.
                    .background { Color.clear.contentShape(.rect) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[sample.id] = $0 }
                    .gesture(reorder(sample.id))
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) {
            if let drag, let sample = samples.first(where: { $0.id == drag.id }) {
                // Rows stay in their column, as in a list; chips go wherever the pointer does.
                lifted(sample)
                    .offset(x: axis == .vertical ? 0 : drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Picks the sample up and carries it under the pointer, moving it in Compare as it passes the others.
    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag?.id != id || drag?.isSettling == true, let frame = frames[id] {
                    drag = SampleDrag(id: id, grab: CGSize(width: value.startLocation.x - frame.minX, height: value.startLocation.y - frame.minY),
                                      location: value.location)
                }
                drag?.location = value.location
                if let target = target(at: value.location, dragging: id) {
                    withAnimation(.snappy) { model.moveInCompare(id, to: target) }
                }
            }
            .onEnded { _ in settle() }
    }

    /// The sample under `point` the dragged one should take the place of. Only once the pointer is past its
    /// middle, coming from the dragged one's side, so a wide chip and a narrow one don't keep trading places.
    /// A row counts all the way across.
    private func target(at point: CGPoint, dragging id: UUID) -> UUID? {
        let ids = model.compareEntries.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return nil }
        for (index, other) in ids.enumerated() where index != from {
            guard let frame = frames[other] else { continue }
            switch axis {
            case .vertical:
                guard (frame.minY..<frame.maxY).contains(point.y) else { continue }
                return (index < from ? point.y < frame.midY : point.y > frame.midY) ? other : nil
            case .horizontal:
                guard frame.contains(point) else { continue }
                return (index < from ? point.x < frame.midX : point.x > frame.midX) ? other : nil
            }
        }
        return nil
    }

    /// Glides the dropped sample into its place, then shows it there.
    private func settle() {
        guard let drag, let frame = frames[drag.id] else {
            self.drag = nil
            return
        }
        let settled = SampleDrag(id: drag.id, grab: drag.grab, location: CGPoint(x: frame.minX + drag.grab.width, y: frame.minY + drag.grab.height),
                                 isSettling: true)
        withAnimation(.snappy(duration: 0.25)) {
            self.drag = settled
        } completion: {
            if self.drag == settled { self.drag = nil }
        }
    }
}

/// A row or chip being dragged.
private struct SampleDrag: Equatable {
    let id: UUID
    /// Where the pointer took hold of the sample, from its top-left corner.
    let grab: CGSize
    /// The pointer, in the Reorderable's coordinates.
    var location: CGPoint
    /// Dropped, and on its way into its place.
    var isSettling = false
}

/// Name, a menu of styles and a remove button, as a row caption or a legend chip.
private struct SampleCaption: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let sample: CompareSample
    let showsTint: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsTint {
                Circle().fill(sample.tint).frame(width: 8, height: 8)
            }
            Text(sample.family.name).fontWeight(.semibold)
            styleMenu
            Button("Remove", systemImage: "xmark.circle.fill") { model.removeFromCompare(sample.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from Compare")
        }
    }

    /// The style shown, which opens the family's styles; Automatic follows the preview weight. Another of its styles
    /// can join Compare too, to set them against each other.
    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: Binding(get: { sample.style }, set: { model.setCompareStyle($0, of: sample.id) })) {
                Text("Automatic").tag(FaceID?.none)
                Divider()
                ForEach(sample.family.faces) { Text($0.face.styleName).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if sample.family.faces.count > 1 {
                Divider()
                Button("Compare Another Style", systemImage: "plus") {
                    let automatic = sample.family.face(nearestWeight: preview.weight).id
                    let shown = model.compareEntries.filter { $0.familyID == sample.family.id }.map { $0.style ?? automatic }
                    model.compareAnotherStyle(of: sample.id, besides: Set(shown))
                }
            }
        } label: {
            // One text, as a menu's label puts an image of its own first. Grey here only: on the menu, the grey
            // would reach its items' icons too.
            Text("\(sample.face.face.styleName) \(Image(systemName: "chevron.down"))")
                .foregroundStyle(.secondary)
                .tint(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the style to compare")
    }
}
