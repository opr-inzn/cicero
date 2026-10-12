import SwiftUI

/// Preview options shared by the browser and the font page. An empty sample shows each family's own name.
@Observable @MainActor
final class PreviewSettings {
    static let waterfallSizes: [Double] = [9, 10, 11, 12, 14, 18, 24, 30, 36, 48, 60, 72, 96]
    static let samplePresets = ["Sphinx of black quartz, judge my vow.", "Hamburgefonstiv", "0123456789 €$£¥ %&@", "ÀÉÎÕÜ ñçß øæœ"]

    var sampleText: String { didSet { defaults.set(sampleText, forKey: Keys.sampleText) } }
    var size: Double { didSet { defaults.set(size, forKey: Keys.size) } }
    var weight: Double { didSet { defaults.set(weight, forKey: Keys.weight) } }
    /// Letter spacing in percent of the em.
    var tracking: Double { didSet { defaults.set(tracking, forKey: Keys.tracking) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let sampleText = "preview.sampleText"
        static let size = "preview.size"
        static let weight = "preview.weight"
        static let tracking = "preview.tracking"
    }

    init() {
        sampleText = defaults.string(forKey: Keys.sampleText) ?? ""
        size = defaults.object(forKey: Keys.size) as? Double ?? 32
        weight = defaults.object(forKey: Keys.weight) as? Double ?? 400
        tracking = defaults.object(forKey: Keys.tracking) as? Double ?? 0
    }

    func text(for family: FontFamily) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }

    /// Points of extra space between letters at a given size.
    func kerning(atSize size: Double) -> Double {
        size * tracking / 100
    }
}

/// Toolbar button opening the preview options; used by the browser and the font page.
struct PreviewOptionsButton: View {
    @Environment(PreviewSettings.self) private var preview
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("Preview Options", systemImage: "textformat.size")
        }
        .help("Preview text, size, weight and spacing")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            PreviewOptionsForm()
        }
    }
}

private struct PreviewOptionsForm: View {
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        @Bindable var preview = preview
        Form {
            Section("Sample") {
                TextField("Sample", text: $preview.sampleText, prompt: Text("Font name"))
                Menu("Presets") {
                    Button("Font Name") { preview.sampleText = "" }
                    Divider()
                    ForEach(PreviewSettings.samplePresets, id: \.self) { sample in
                        Button(sample) { preview.sampleText = sample }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            Section {
                LabeledContent("Size") {
                    HStack {
                        ValueSlider(value: $preview.size, in: 8...160, round: { $0.rounded() })
                        Text("\(Int(preview.size.rounded())) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Weight") {
                    HStack {
                        ValueSlider(value: $preview.weight, in: 100...900, round: { $0.rounded() })
                        Text("\(Int(preview.weight))").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Spacing") {
                    HStack {
                        ValueSlider(value: $preview.tracking, in: -10...40, round: { ($0 * 2).rounded() / 2 })
                        Text(String(format: "%.1f%%", preview.tracking)).monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A slider drawn by Point. The system slider's glass knob vanishes in some toolbar popovers on
/// macOS 26, leaving a gap in the track; this one always shows a solid knob.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var round: (Double) -> Double = { $0 }
    @Environment(\.isEnabled) private var isEnabled

    init(value: Binding<Double>, in range: ClosedRange<Double>, round: @escaping (Double) -> Double = { $0 }) {
        _value = value
        self.range = range
        self.round = round
    }

    private let knob: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knob, 1)
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: knob / 2 + travel * fraction, height: 4)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                value = round(range.lowerBound + position * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: knob + 4)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .number.precision(.fractionLength(0...1))))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 50
            let next = direction == .increment ? value + step : value - step
            value = round(min(max(next, range.lowerBound), range.upperBound))
        }
    }
}
