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

/// Families next to each other: one row each on a shared baseline, or drawn over each other in tints.
struct CompareWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("compare.layout") private var layout: CompareLayout = .stacked

    var body: some View {
        let samples = model.compareIDs.compactMap(model.family).map {
            CompareSample($0, tint: model.compareTints[$0.id] ?? 0, model: model, preview: preview)
        }
        Group {
            if samples.isEmpty {
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
        .navigationSubtitle(samples.count == 1 ? "1 family" : "\(samples.count) families")
        .toolbar {
            ToolbarCapsule {
                ToolbarPicker(CompareLayout.allCases, selection: $layout, title: \.title)
                    .help("One row per font, or every font over each other")
            }
            ToolbarCapsule { PreviewOptionsButton() }
        }
    }
}

/// One family's sample, set in the face nearest the preview weight.
private struct CompareSample: Identifiable {
    static let tints: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .teal, .indigo, .brown, .cyan, .mint, .yellow]

    let family: Family
    let face: LibraryFace
    let line: TextLine
    let tint: Color

    var id: String { family.id }

    init(_ family: Family, tint: Int, model: AppModel, preview: PreviewSettings) {
        self.family = family
        face = family.face(nearestWeight: preview.weight)
        let font = FontLoader.shared.font(face.face, size: preview.size, weight: preview.weight, features: model.features(for: family))
        line = TextLine(preview.sampleText.isEmpty ? "Hamburgefonstiv" : preview.sampleText, font: font, kerning: preview.kerning(at: preview.size))
        self.tint = Self.tints[tint % Self.tints.count]
    }
}

/// One row per font; every row's baseline sits at the same offset, so the samples line up.
private struct StackedLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let ascent = samples.map(\.line.ascent).max() ?? 0
        let descent = samples.map(\.line.descent).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + 2
        VStack(alignment: .leading, spacing: 20) {
            ForEach(samples) { sample in
                VStack(alignment: .leading, spacing: 6) {
                    Canvas { context, _ in
                        let color = Color.primary.resolve(in: context.environment).cgColor
                        context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: 0, y: ascent), color: color) }
                    }
                    .frame(width: width, height: ascent + descent)
                    SampleCaption(sample: sample, showsTint: false)
                }
            }
        }
    }
}

/// Every sample over the others, each in its tint, with its x-height and cap height ticked at the left.
/// Dragging a chip in the legend below changes the order, so the last one is drawn on top.
private struct OverlayLayout: View {
    @Environment(AppModel.self) private var model
    let samples: [CompareSample]
    /// Room for the ticks.
    private let inset: CGFloat = 28
    private static let legend = "compare.legend"
    @State private var drag: ChipDrag?
    /// Where each chip is laid out, in the legend's coordinates.
    @State private var chipFrames: [String: CGRect] = [:]

    var body: some View {
        let ascent = samples.map(\.line.ascent).max() ?? 0
        let descent = samples.map(\.line.descent).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + inset + 2
        VStack(alignment: .leading, spacing: 16) {
            Canvas { context, size in
                var baseline = Path()
                baseline.move(to: CGPoint(x: inset, y: crisp(ascent)))
                baseline.addLine(to: CGPoint(x: size.width, y: crisp(ascent)))
                context.stroke(baseline, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                for sample in samples {
                    var ticks = Path()
                    let xHeight = crisp(ascent - sample.line.xHeight)
                    ticks.move(to: CGPoint(x: inset - 10, y: xHeight))
                    ticks.addLine(to: CGPoint(x: inset - 4, y: xHeight))
                    let capHeight = crisp(ascent - sample.line.capHeight)
                    ticks.move(to: CGPoint(x: inset - 18, y: capHeight))
                    ticks.addLine(to: CGPoint(x: inset - 4, y: capHeight))
                    context.stroke(ticks, with: .color(sample.tint), lineWidth: 1)
                    let color = sample.tint.opacity(0.7).resolve(in: context.environment).cgColor
                    context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: inset, y: ascent), color: color) }
                }
            }
            .frame(width: width, height: ascent + descent)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(samples) { sample in
                    // While it's dragged, the chip leaves an empty capsule where it will land.
                    chip(sample, isEmpty: drag?.id == sample.id)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.legend)) } action: { chipFrames[sample.id] = $0 }
                        .gesture(reorder(sample.id))
                        .help("Drag to change the order")
                }
            }
            .coordinateSpace(.named(Self.legend))
            .overlay(alignment: .topLeading) {
                if let drag, let sample = samples.first(where: { $0.id == drag.id }) {
                    chip(sample, isEmpty: false)
                        .background(Color.canvas, in: .capsule)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                        .offset(x: drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: max(width, 480), alignment: .leading)
        }
    }

    private func chip(_ sample: CompareSample, isEmpty: Bool) -> some View {
        SampleCaption(sample: sample, showsTint: true)
            .font(.callout)
            .opacity(isEmpty ? 0 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary, in: .capsule)
    }

    /// Picks the chip up and carries it under the pointer; the others make way as it passes them.
    private func reorder(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.legend))
            .onChanged { value in
                if drag?.id != id || drag?.isSettling == true, let frame = chipFrames[id] {
                    drag = ChipDrag(id: id, grab: CGSize(width: value.startLocation.x - frame.minX, height: value.startLocation.y - frame.minY),
                                    location: value.location)
                }
                drag?.location = value.location
                if let target = target(at: value.location, dragging: id) {
                    withAnimation(.snappy) { model.moveInCompare(id, to: target) }
                }
            }
            .onEnded { _ in settle() }
    }

    /// The chip under `point` the dragged one should take the place of. Only once the pointer is past its
    /// middle, coming from the dragged chip's side, so a wide chip and a narrow one don't keep trading places.
    private func target(at point: CGPoint, dragging id: String) -> String? {
        guard let from = model.compareIDs.firstIndex(of: id) else { return nil }
        for (index, other) in model.compareIDs.enumerated() where index != from {
            guard let frame = chipFrames[other], frame.contains(point) else { continue }
            return (index < from ? point.x < frame.midX : point.x > frame.midX) ? other : nil
        }
        return nil
    }

    /// Glides the dropped chip into its place, then shows it there.
    private func settle() {
        guard let drag, let frame = chipFrames[drag.id] else {
            self.drag = nil
            return
        }
        let settled = ChipDrag(id: drag.id, grab: drag.grab, location: CGPoint(x: frame.minX + drag.grab.width, y: frame.minY + drag.grab.height),
                               isSettling: true)
        withAnimation(.snappy(duration: 0.25)) {
            self.drag = settled
        } completion: {
            if self.drag == settled { self.drag = nil }
        }
    }

    /// Centres a one-point line on a pixel row.
    private func crisp(_ y: CGFloat) -> CGFloat { y.rounded() + 0.5 }
}

/// A legend chip being dragged.
private struct ChipDrag: Equatable {
    let id: String
    /// Where the pointer took hold of the chip, from its top-left corner.
    let grab: CGSize
    /// The pointer, in the legend's coordinates.
    var location: CGPoint
    /// Dropped, and on its way into its place.
    var isSettling = false
}

/// Name, style and a remove button, as a row caption or a legend chip.
private struct SampleCaption: View {
    @Environment(AppModel.self) private var model
    let sample: CompareSample
    let showsTint: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsTint {
                Circle().fill(sample.tint).frame(width: 8, height: 8)
            }
            Text(sample.family.name).fontWeight(.semibold)
            Text(sample.face.face.styleName).foregroundStyle(.secondary)
            Button("Remove", systemImage: "xmark.circle.fill") { model.removeFromCompare(sample.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from Compare")
        }
    }
}
