import AppKit
import CiceroCore
import SwiftUI

extension Color {
    /// The background behind specimens: the text background, light or dark with the appearance.
    static let canvas = Color(nsColor: .textBackgroundColor)
}

/// Text set in a font face, straight from its file (so it works for fonts that aren't active).
struct FontText: View {
    let text: String
    let face: FontFace
    let size: Double
    var weight: Double = 400
    var features: [FeatureSetting] = []
    var kerning: Double = 0
    var lineLimit: Int? = 1

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(Font(FontLoader.shared.font(face, size: size, weight: weight, features: features)))
            .kerning(kerning)
            .lineLimit(lineLimit)
    }
}

/// A small switch drawn in SwiftUI. Lists show one per family, and a native switch per row made
/// building a list much slower.
struct MiniSwitch: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
            .onTapGesture { if isEnabled { action() } }
            .animation(.snappy(duration: 0.15), value: isOn)
    }
}

/// On/off for a whole family. Gets the model passed in rather than from the environment: AppKit
/// builds table cells outside SwiftUI's update, where the environment isn't there yet.
struct ActivationSwitch: View {
    let family: Family
    let model: AppModel

    var body: some View {
        let isEnabled = family.hasActivatable || family.hasDeactivatable
        MiniSwitch(isOn: family.hasActive, isEnabled: isEnabled) { model.toggle(family) }
            .help(help)
            .accessibilityElement()
            .accessibilityLabel("Activated")
            .accessibilityValue(family.hasActive ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { if isEnabled { model.toggle(family) } }
    }

    private var help: String {
        switch family.state {
        case .system: "Installed with macOS"
        case .appOnly(let app): "On in \(FaceState.appDescription(app)) only. Turn on to use it in every app."
        default: family.hasActive ? "Deactivate" : "Activate"
        }
    }
}

/// A small tinted capsule with a word or two.
struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: .capsule)
            .foregroundStyle(tint.opacity(0.9))
    }
}

/// A small capsule for families that aren't simply on or off.
struct StatusTag: View {
    let family: Family

    var body: some View {
        if let (text, tint) = content {
            Tag(text: text, tint: tint).help(help)
        }
    }

    private var content: (String, Color)? {
        if family.temporaryScope != nil { return ("Temporary", .blue) }
        switch family.state {
        case .system: return ("System", .secondary)
        case .partial: return ("Partly active", .orange)
        case .appOnly(let app): return (app, .red)
        case .active, .inactive: return nil
        }
    }

    private var help: String {
        switch family.temporaryScope {
        case .untilQuit: "Active until Cicero quits"
        case .untilLogout: "Active until you log out"
        case nil: ""
        }
    }
}

/// A slider drawn by Cicero: the system slider's glass knob disappears in toolbar popovers on macOS 26.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    @Environment(\.isEnabled) private var isEnabled

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
                value = rounded(range.lowerBound + position * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: knob + 4)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .number.precision(.fractionLength(0...1))))
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? value + step : value - step
            value = rounded(min(max(next, range.lowerBound), range.upperBound))
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value / step).rounded() * step
    }
}

/// A borderless + or − under a list, as in System Settings. The default button style gives each
/// a glass capsule on macOS 26, narrower when disabled.
struct ListEditButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

/// A pop-up menu that always shows its background. In grouped forms on macOS 26, a SwiftUI Picker
/// (and a plain NSPopUpButton) is only its text and a chevron until the pointer is over it.
struct PopUpPicker<Value: Hashable>: NSViewRepresentable {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .flexiblePush
        button.target = context.coordinator
        button.action = #selector(PopUpTarget.choose(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let titles = options.map(\.title)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: options.firstIndex { $0.value == selection } ?? -1)
        context.coordinator.onChoose = { index in selection = options[index].value }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> PopUpTarget { PopUpTarget() }
}

final class PopUpTarget: NSObject {
    var onChoose: (Int) -> Void = { _ in }

    @objc func choose(_ sender: NSPopUpButton) {
        onChoose(sender.indexOfSelectedItem)
    }
}

extension View {
    /// For a section footer in a grouped form: moves it closer to its card than the default gap.
    func formFooter() -> some View {
        padding(.top, -4)
    }

    /// For a grouped-form row with a button, pop-up or segmented picker: macOS 26 sets those 2 pt
    /// above the middle of the row (6 pt above, 10 below), and the label with them.
    func formRowCentered() -> some View {
        offset(y: 2)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The toolbar button with sample text, size, weight and spacing.
struct PreviewOptionsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Preview Options", systemImage: "textformat.size")
        }
        .help("Preview text, size, weight and spacing")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { PreviewOptions() }
    }
}

private struct PreviewOptions: View {
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        @Bindable var preview = preview
        Form {
            Section("Sample") {
                TextField("Sample", text: $preview.sampleText, prompt: Text("Font name"))
                Menu("Presets") {
                    Button("Font Name") { preview.sampleText = "" }
                    Divider()
                    ForEach(PreviewSettings.presets, id: \.self) { sample in
                        Button(sample) { preview.sampleText = sample }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            Section {
                row("Size", "\(Int(preview.size)) pt") { ValueSlider(value: $preview.size, range: 8...160) }
                row("Weight", "\(Int(preview.weight))") { ValueSlider(value: $preview.weight, range: 100...900) }
                row("Spacing", String(format: "%.1f%%", preview.tracking)) { ValueSlider(value: $preview.tracking, range: -10...40, step: 0.5) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, _ value: String, @ViewBuilder slider: () -> some View) -> some View {
        LabeledContent(title) {
            HStack {
                slider()
                Text(value).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// The Info panel toggle; toolbars give it a group of its own with a fixed spacer.
struct InfoButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.isInfoPresented.toggle()
        } label: {
            Label("Info", systemImage: "info.circle")
        }
        .help("Info")
    }
}
