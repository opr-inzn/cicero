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
    /// For text that runs over several lines; nil for the font's own line spacing.
    var lineHeight: AttributedString.LineHeight?

    var body: some View {
        let font = FontLoader.shared.font(face, size: size, weight: weight, features: features)
        Text(text.isEmpty ? " " : text)
            .font(Font(font))
            .kerning(kerning)
            .lineLimit(lineLimit)
            .lineHeight(lineHeight)
            .textRenderer(UnclippedText(font: font))
    }
}

/// Draws text as usual, but with room above and below its lines for glyphs reaching past the font's ascent
/// and descent, like a descender lower than the font says or a swash, which SwiftUI otherwise cuts off: as far
/// as any of the font's glyphs reach, and at least half the size, for the fonts that stand in for missing
/// characters. None at the sides, where text isn't cut off, and room there puts a "…" out of place.
nonisolated struct UnclippedText: TextRenderer {
    let room: EdgeInsets

    init(font: CTFont) {
        let box = CTFontGetBoundingBox(font)
        let half = CTFontGetSize(font) / 2
        room = EdgeInsets(top: max(box.maxY - CTFontGetAscent(font), half), leading: 0,
                          bottom: max(-box.minY - CTFontGetDescent(font), half), trailing: 0)
    }

    var displayPadding: EdgeInsets { room }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout { context.draw(line) }
    }
}

/// A small switch drawn in SwiftUI. Lists show one per family, and a native switch per row made
/// building a list much slower. The middle position (on in one app only) puts the knob halfway.
struct MiniSwitch: View {
    let position: SwitchPosition
    let isEnabled: Bool
    let action: () -> Void

    init(position: SwitchPosition, isEnabled: Bool, action: @escaping () -> Void) {
        self.position = position
        self.isEnabled = isEnabled
        self.action = action
    }

    init(isOn: Bool, isEnabled: Bool, action: @escaping () -> Void) {
        self.init(position: isOn ? .on : .off, isEnabled: isEnabled, action: action)
    }

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(width: 26, height: 15)
            .overlay(alignment: alignment) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
            .onTapGesture { if isEnabled { action() } }
            .animation(.snappy(duration: 0.15), value: position)
    }

    private var fill: AnyShapeStyle {
        switch position {
        case .off: AnyShapeStyle(.quaternary)
        case .app: AnyShapeStyle(.tint.opacity(0.45))
        case .on: AnyShapeStyle(.tint)
        }
    }

    private var alignment: Alignment {
        switch position {
        case .off: .leading
        case .app: .center
        case .on: .trailing
        }
    }
}

/// On/off for a whole family. Gets the model passed in rather than from the environment: AppKit
/// builds table cells outside SwiftUI's update, where the environment isn't there yet.
struct ActivationSwitch: View {
    let family: Family
    let model: AppModel

    var body: some View {
        let isEnabled = family.hasActivatable || family.hasDeactivatable
        MiniSwitch(position: model.position(of: family), isEnabled: isEnabled) { model.toggle(family) }
            .help(help)
            .accessibilityElement()
            .accessibilityLabel("Active")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { if isEnabled { model.toggle(family) } }
    }

    private var help: String {
        if family.state == .system { return "Installed with macOS" }
        if family.isAdobeFonts { return "From Adobe Fonts, which Creative Cloud turns on and off" }
        guard let app = family.app.map(FaceState.appDescription) else { return family.hasActive ? "Deactivate" : "Activate" }
        return switch model.position(of: family) {
        case .app: "On in \(app) only. Click to turn on in every app."
        case .on: "On in every app. Click to turn off, \(app) included."
        case .off: "Off. Click to turn on in \(app) only."
        }
    }

    private var accessibilityValue: String {
        switch model.position(of: family) {
        case .on: "On"
        case .app: "On in \(family.app.map(FaceState.appDescription) ?? "one app") only"
        case .off: "Off"
        }
    }
}

/// A small tinted capsule with a word or two, never shortened: a name next to it gives way instead. (A list
/// cell lays its row out again at the row's own width, where a stack offers each text half of what's left,
/// so beside a name about as wide as itself, "Adobe" got less than it needs.)
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
            .fixedSize()
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
        if family.temporaryScope == .whileAppsRun { return ("App Set", .blue) }
        if family.temporaryScope != nil { return ("Temporary", .blue) }
        // Creative Cloud's, apart from the fonts type designers put in Adobe's folders to test them, tagged Testing.
        if family.isAdobeFonts { return ("Adobe Fonts", .purple) }
        switch family.state {
        case .system: return ("System", .secondary)
        case .partial: return ("Partly active", .orange)
        case .appOnly(let app): return (app == "Adobe" ? "Testing" : app, .red)
        case .active, .inactive: return nil
        }
    }

    private var help: String {
        switch (family.temporaryScope, family.state) {
        case (.untilQuit, _): "Active until Cicero quits"
        case (.whileAppsRun, _): "Active while an app it’s set up for is open"
        case (nil, .appOnly) where family.isAdobeFonts: "From Adobe Fonts, managed in Creative Cloud. Active in Adobe apps only."
        case (nil, _) where family.isAdobeFonts: "From Adobe Fonts, managed in Creative Cloud"
        case (nil, .appOnly("Adobe")): "Active in Adobe apps only, from a folder they load fonts from by themselves"
        case (nil, .appOnly(let app)): "Active in \(app) only, from a folder it loads fonts from by itself"
        case (nil, _): ""
        }
    }
}

/// The system slider on macOS 27, which draws it itself, and one drawn by Cicero on macOS 26, whose slider's
/// glass knob disappears in toolbar popovers. Continuous, rounded to the step: a stepped system slider can
/// show a tick for every step.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    @Environment(\.isEnabled) private var isEnabled

    private let knob: CGFloat = 18

    var body: some View {
        if #available(macOS 27, *) {
            Slider(value: Binding(get: { value }, set: { value = rounded($0) }), in: range)
        } else {
            drawn
        }
    }

    private var drawn: some View {
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

/// The number beside a slider, which takes one typed in as well: on Return, or when it loses focus, it's kept to
/// the slider's range and rounded to its step. ↑ and ↓ step it, ten steps with ⇧.
struct ValueField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// After the number: " pt", "%".
    var unit = ""
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, unit: String = "") {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField(title, text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(commit)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let steps = press.modifiers.contains(.shift) ? 10.0 : 1
                    set((typed ?? value) + (press.key == .upArrow ? step : -step) * steps)
                    return .handled
                }
            // In the number's colour: forms grey a row's value text.
            Text(unit).foregroundStyle(.primary)
        }
        .monospacedDigit()
        .frame(width: 52, alignment: .trailing)
        .onAppear { text = formatted(value) }
        // The slider moved; typing leaves the value alone until it's committed.
        .onChange(of: value) { text = formatted($1) }
        .onChange(of: isFocused) { if !$1 { commit() } }
    }

    /// What's typed, with a decimal comma or point.
    private var typed: Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacing(",", with: "."))
    }

    private func commit() {
        if let typed { set(typed) } else { text = formatted(value) }
    }

    private func set(_ new: Double) {
        value = min(max((new / step).rounded() * step, range.lowerBound), range.upperBound)
        text = formatted(value)
    }

    private func formatted(_ value: Double) -> String {
        String(format: step < 1 ? "%.1f" : "%.0f", value)
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

/// A + or − under a list in a card (see `inCard`).
struct CardListButton {
    let title: String
    let help: String
    let action: () -> Void
}

extension View {
    /// A list in a card with + and − along its bottom, like the lists in System Settings: Settings → Folders,
    /// and the apps of an application set. Its rows take `cardRow`.
    func inCard(add: CardListButton, remove: CardListButton, canRemove: Bool) -> some View {
        VStack(spacing: 0) {
            listStyle(.plain)
                .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 0) {
                ListEditButton(add.title, systemImage: "plus", action: add.action)
                    .help(add.help)
                Divider()
                    .frame(height: 14)
                ListEditButton(remove.title, systemImage: "minus", action: remove.action)
                    .disabled(!canRemove)
                    .help(remove.help)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
        }
        // The fill and corners of the grouped forms' cards.
        .background(.fill.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    /// Every other row tinted, without separators. A list's own stripes are opaque and would hide the card.
    func cardRow(_ index: Int) -> some View {
        listRowBackground(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
            .listRowSeparator(.hidden)
    }
}

/// What a folder's fonts are, in its row in Settings → Folders and its menu in the sidebar: Inactive, Active
/// (Cicero keeps them on), or active in an app that loads the folder by itself. `askForApp` asks for that app's name.
struct FolderActivationPicker: View {
    let folder: WatchedFolder
    let askForApp: () -> Void
    @Environment(AppModel.self) private var model

    /// Tags that aren't app names.
    private static let active = "\u{0}active", specificApp = "\u{0}app"

    var body: some View {
        Picker(selection: Binding(
            get: { folder.isActive ? Self.active : folder.appName ?? "" },
            set: { choice in
                switch choice {
                case Self.specificApp: askForApp()
                case Self.active: model.setActivation(ofFolder: folder.id, active: true, app: nil)
                default: model.setActivation(ofFolder: folder.id, active: false, app: choice)
                }
            }
        )) {
            Text("Inactive").tag("")
            Text("Active").tag(Self.active)
            Text("Active in Adobe apps").tag("Adobe")
            // One typed in, or InDesign from before there was Active in Specific App.
            if let app = folder.appName, app != "Adobe" {
                Text("Active in \(FaceState.appDescription(app))").tag(app)
            }
            Divider()
            Text("Active in Specific App").tag(Self.specificApp)
        } label: {
            Label("Fonts in This Folder", systemImage: "switch.2")
        }
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

/// Icons side by side, one of them chosen, always the same width. A SwiftUI segmented picker (and an NSSegmentedControl
/// sizing its own segments) measures 77 pt before it's in a window and 74 pt once it is, so a font page drew it wider
/// at first, then narrower the next time the page was laid out: it, and the size beside it, moved as the page filled
/// in. Segments of a set width measure the same either way.
struct IconSegments<Value: Hashable>: NSViewRepresentable {
    let title: String
    let options: [(title: String, systemImage: String, value: Value)]
    @Binding var selection: Value
    private let segmentWidth: CGFloat = 24

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = options.map { NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: $0.title) ?? NSImage() }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne, target: context.coordinator,
                                         action: #selector(SegmentTarget.choose(_:)))
        for index in options.indices {
            control.setWidth(segmentWidth, forSegment: index)
        }
        control.setAccessibilityLabel(title)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        context.coordinator.onChoose = { index in selection = options[index].value }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> SegmentTarget { SegmentTarget() }
}

final class SegmentTarget: NSObject {
    var onChoose: (Int) -> Void = { _ in }

    @objc func choose(_ sender: NSSegmentedControl) {
        onChoose(sender.selectedSegment)
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
        .buttonStyle(.toolbar)
        .help("Preview text, size, weight, spacing and alignment")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { PreviewOptions() }
    }
}

private struct PreviewOptions: View {
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        @Bindable var preview = preview
        Form {
            Section {
                TextField("Preview Text", text: $preview.sampleText, prompt: Text("Font name"))
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
                row("Size", $preview.size, range: 8...160, unit: " pt")
                row("Weight", $preview.weight, range: 100...900)
                row("Letter Spacing", $preview.tracking, range: -10...40, step: 0.5, unit: "%")
                row("Line Spacing", $preview.lineSpacing, range: 80...250, step: 5, unit: "%")
                    .help("The distance between lines, in percent of the size, where a sample runs over several lines")
                LabeledContent("Alignment") {
                    Picker("Alignment", selection: $preview.alignment) {
                        ForEach(SampleAlignment.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .labelsHidden()
                    .fixedSize()
                }
                .help("How samples line up in specimens and Quick Look; font pages have their own alignment")
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, unit: String = "") -> some View {
        LabeledContent(title) {
            HStack {
                ValueSlider(value: value, range: range, step: step)
                ValueField(title, value: value, range: range, step: step, unit: unit)
            }
        }
    }
}

/// The Info panel toggle, highlighted while the panel is open, like the view picker's choice; toolbars
/// give it a capsule of its own.
struct InfoButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle(isOn: Binding(get: { model.isInfoPresented }, set: { model.isInfoPresented = $0 })) {
            Label("Info", systemImage: "info.circle")
        }
        .toggleStyle(.toolbar)
        .help("Info")
    }
}
