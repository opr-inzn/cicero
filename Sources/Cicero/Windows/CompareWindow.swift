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
        let samples = model.compareIDs.compactMap(model.family).enumerated().map {
            CompareSample($1, index: $0, model: model, preview: preview)
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
            ToolbarItem {
                Picker("Layout", selection: $layout) {
                    ForEach(CompareLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("One row per font, or every font over each other")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem { PreviewOptionsButton() }
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

    init(_ family: Family, index: Int, model: AppModel, preview: PreviewSettings) {
        self.family = family
        face = family.face(nearestWeight: preview.weight)
        let font = FontLoader.shared.font(face.face, size: preview.size, weight: preview.weight, features: model.features(for: family))
        line = TextLine(preview.sampleText.isEmpty ? "Hamburgefonstiv" : preview.sampleText, font: font, kerning: preview.kerning(at: preview.size))
        tint = Self.tints[index % Self.tints.count]
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
private struct OverlayLayout: View {
    let samples: [CompareSample]
    /// Room for the ticks.
    private let inset: CGFloat = 28

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
                    SampleCaption(sample: sample, showsTint: true)
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
            .frame(width: max(width, 480), alignment: .leading)
        }
    }

    /// Centres a one-point line on a pixel row.
    private func crisp(_ y: CGFloat) -> CGFloat { y.rounded() + 0.5 }
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
