import AppKit
import CiceroCore
import SwiftUI

extension Color {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let ink = Color(nsColor: .textColor)
    static let variable = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemGreen : NSColor(srgbRed: 0.16, green: 0.55, blue: 0.24, alpha: 1)
    })
    static let appSet = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.72, green: 0.77, blue: 0.85, alpha: 1)
            : NSColor(srgbRed: 0.27, green: 0.31, blue: 0.38, alpha: 1)
    })
    static let solar = Color(nsColor: NSColor(srgbRed: 1, green: 0.392, blue: 0.04, alpha: 1))
}

struct FontText: View {
    let text: String
    let face: FontFace
    let size: Double
    var weight: Double = 400
    var variations: [String: Double] = [:]
    var features: [FeatureSetting] = []
    var lineLimit: Int? = 1
    var lineHeight: Double?
    var scale: ((CTFont) -> CGFloat)?
    var cached = true
    var onCaps = false
    @State private var readPath: String?

    var body: some View {
        if readPath == face.path || !FontLoader.shared.wouldWait(for: face.path) {
            let atSize = FontLoader.shared.font(face, size: size, weight: weight, variations: variations, features: features, cached: cached)
            let scale = scale?(atSize) ?? 1
            let font = scale == 1 ? atSize : FontLoader.shared.font(face, size: size * scale, weight: weight, variations: variations,
                                                                    features: features, cached: cached)
            Text(text.isEmpty ? " " : text)
                .font(Font(font))
                .lineLimit(lineLimit)
                .lineHeight(lineHeight, natural: font.naturalLineHeight)
                .textRenderer(UnclippedText(font: font))
                .onCaps(onCaps ? font : nil)
        } else {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: size))
                .lineLimit(lineLimit)
                .lineHeight(lineHeight, natural: (NSFont.systemFont(ofSize: size) as CTFont).naturalLineHeight)
                .onCaps(onCaps ? NSFont.systemFont(ofSize: size) as CTFont : nil)
                .hidden()
                .task(id: face.path) {
                    await FontLoader.shared.read(face.path)
                    readPath = face.path
                }
        }
    }
}

private extension View {
    @ViewBuilder func onCaps(_ font: CTFont?) -> some View {
        if let font {
            let size = CTFontGetSize(font)
            let cap = CTFontGetCapHeight(font) > 0 ? CTFontGetCapHeight(font) : size * 0.7
            let baseline = (size * 0.1 + cap).rounded()
            alignmentGuide(.top) { $0[.firstTextBaseline] - baseline }
                .frame(height: baseline + (size * 0.15).rounded(), alignment: .topLeading)
        } else {
            self
        }
    }
}

struct FontLine: View {
    let text: String
    let face: FontFace
    let size: Double
    var weight: Double = 400
    var variations: [String: Double] = [:]
    var features: [FeatureSetting] = []
    let height: CGFloat
    @State private var readPath: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if readPath == face.path || !FontLoader.shared.wouldWait(for: face.path) {
            let font = FontLoader.shared.font(face, size: size, weight: weight, variations: variations, features: features)
            let text = text.isEmpty ? " " : text
            let scheme = colorScheme
            let scale = displayScale
            let line = Self.line(of: font, in: height, scale: scale)
            // A line can be much taller than the row (Zapfino's is 57.5 pt in a row of 22), and its swashes reach further.
            let room = UnclippedText(font: font).room
            let top = min(0, line.top - room.top), bottom = max(height, line.top + line.height + room.bottom)
            // At the sides too, where Text doesn't cut glyphs off either, as Zapfino's Z reaching left of the line's start.
            let box = CTFontGetBoundingBox(font)
            let left = max(0, -box.minX).rounded(.up), right = max(0, box.maxX).rounded(.up)
            Canvas { context, size in
                _ = scheme
                Self.draw(text, font: font, in: &context, x: left, width: size.width - left - right, baseline: line.baseline - top)
            }
            .frame(height: bottom - top)
            .padding(.top, top)
            .padding(.bottom, height - bottom)
            .padding(.leading, -left)
            .padding(.trailing, -right)
            .accessibilityElement()
            .accessibilityLabel(text)
        } else {
            Color.clear
                .frame(height: height)
                .task(id: face.path) {
                    await FontLoader.shared.read(face.path)
                    readPath = face.path
                }
        }
    }

    private static func line(of font: CTFont, in height: CGFloat, scale: CGFloat) -> (top: CGFloat, height: CGFloat, baseline: CGFloat) {
        let pixel = { (value: CGFloat) in (value * scale).rounded(.down) / scale }
        let ascent = CTFontGetAscent(font).rounded()
        let line = pixel(ascent + CTFontGetDescent(font))
        let top = pixel((height - line) / 2)
        return (top, line, top + ascent)
    }

    private static func draw(_ text: String, font: CTFont, in context: inout GraphicsContext, x: CGFloat, width: CGFloat, baseline: CGFloat) {
        let color = Color.ink.resolve(in: context.environment).cgColor
        let attributes: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let drawn = CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line
        context.withCGContext { cg in
            cg.textMatrix = .identity
            cg.translateBy(x: x, y: baseline)
            cg.scaleBy(x: 1, y: -1)
            cg.textPosition = .zero
            CTLineDraw(drawn, cg)
        }
    }
}

struct ReadingFonts<Content: View>: View {
    let paths: [String]
    @ViewBuilder let content: () -> Content
    @State private var read: Set<String> = []

    var body: some View {
        let waiting = paths.filter { !read.contains($0) && FontLoader.shared.wouldWait(for: $0) }
        if waiting.isEmpty {
            content()
        } else {
            Color.clear
                .task(id: waiting) {
                    await FontLoader.shared.read(waiting)
                    read.formUnion(waiting)
                }
        }
    }
}

nonisolated struct UnclippedText: TextRenderer {
    let room: EdgeInsets

    init(font: CTFont) {
        let box = CTFontGetBoundingBox(font)
        let half = CTFontGetSize(font) / 2
        // None at the sides, where text isn't cut off: room there puts a "…" out of place.
        room = EdgeInsets(top: max(box.maxY - CTFontGetAscent(font), half), leading: 0,
                          bottom: max(-box.minY - CTFontGetDescent(font), half), trailing: 0)
    }

    var displayPadding: EdgeInsets { room }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout { context.draw(line) }
    }
}

struct MiniSwitch: View {
    let position: SwitchPosition
    let isEnabled: Bool
    let action: () -> Void

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

struct Tag: View {
    let text: String
    let tint: Color
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2.5) {
            if let systemImage {
                Text(Image(systemName: systemImage))
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(Self.font)
        .padding(.horizontal, 5)
        // A whole number of points tall: centred in a row, a fractional height drew the capsule half a pixel off its text, which snaps to pixels.
        .frame(height: 14)
        .background(tint.opacity(0.14), in: .capsule)
        .foregroundStyle(tint.opacity(0.9))
        .fixedSize()
    }

    private static let font = Font.system(size: 10, weight: .semibold)
}

struct VariableTag: View {
    let family: Family

    var body: some View {
        if family.isVariable {
            Tag(text: "Variable", tint: .variable, systemImage: "slider.horizontal.3")
                .help(help)
        }
    }

    private var help: String {
        var axes: [VariationAxis] = []
        for face in family.faces {
            for axis in face.face.axes where !axes.contains(where: { $0.name == axis.name }) { axes.append(axis) }
        }
        return axes.isEmpty ? "Variable" : "Variable: " + axes.map(\.name).joined(separator: ", ")
    }
}

struct StatusTag: View {
    let family: Family

    var body: some View {
        if let (text, tint, symbol) = content {
            Tag(text: text, tint: tint, systemImage: symbol).help(help)
        }
    }

    private var content: (String, Color, String?)? {
        if family.temporaryScope == .whileAppsRun { return ("App Folder", .appSet, "app.badge.checkmark") }
        if family.temporaryScope != nil { return ("Temporary", .blue, "clock") }
        if family.isAdobeFonts { return ("Adobe Fonts", .purple, nil) }
        switch family.state {
        case .system: return ("System", .secondary, nil)
        case .partial: return ("Partly Active", .orange, nil)
        case .appOnly(let app): return (app == "Adobe" ? "Proofing" : app, .red, nil)
        case .active, .inactive: return nil
        }
    }

    private var help: String {
        switch (family.temporaryScope, family.state) {
        case (.untilQuit, _): "Active until Cicero quits"
        case (.whileAppsRun, _): "Active while its app is open"
        case (nil, .appOnly) where family.isAdobeFonts: "From Adobe Fonts, managed in Creative Cloud. Active in Adobe apps only."
        case (nil, _) where family.isAdobeFonts: "From Adobe Fonts, managed in Creative Cloud"
        case (nil, .appOnly("Adobe")): "Active in Adobe apps only, from a folder they load fonts from by themselves"
        case (nil, .appOnly(let app)): "Active in \(app) only, from a folder it loads fonts from by itself"
        case (nil, _): ""
        }
    }
}

struct EmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text?
    @ViewBuilder var actions: Actions

    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage).labelStyle(EmptyStateLabelStyle())
        } description: {
            description?.padding(.top, -4)
        } actions: {
            actions.padding(.top, 6)
        }
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(title, systemImage: systemImage, description: description) {}
    }

    static func search(text: String = "") -> Self {
        EmptyState(text.isEmpty ? "No Results" : "No Results for “\(text)”", systemImage: "magnifyingglass",
                   description: Text("Check the spelling or try a new search."))
    }
}

private struct EmptyStateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 8) {
            configuration.icon.font(.system(size: 36)).foregroundStyle(.tertiary)
            configuration.title.bold()
        }
    }
}

struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    @Environment(\.isEnabled) private var isEnabled

    private let knob: CGFloat = 18

    var body: some View {
        if #available(macOS 27, *) {
            // Rounded here rather than given the step: a stepped system slider can show a tick for every step.
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

struct ValueField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = ""
    var alignment = HorizontalAlignment.trailing
    @State private var text = ""
    @State private var owner: Binding<Double>?
    @FocusState private var isFocused: Bool

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, unit: String = "", alignment: HorizontalAlignment = .trailing) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.alignment = alignment
        // The number from the start, not once it appears: a field measured before it's on screen, as `TesterControls` does, would measure as wide as its title, which it shows while empty.
        _text = State(initialValue: Self.formatted(value.wrappedValue, step: step))
    }

    var body: some View {
        let content = HStack(spacing: 0) {
            number
            // In the number's colour: forms grey a row's value text.
            Text(unit).foregroundStyle(.primary)
        }
        Group {
            if alignment == .leading {
                ZStack(alignment: .leading) {
                    Text(formatted(range.lowerBound) + unit).hidden()
                    Text(formatted(range.upperBound) + unit).hidden()
                    content
                }
            } else {
                content.frame(width: 52, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .onAppear { text = formatted(value) }
        .onChange(of: value) { text = formatted($1) }
        .onChange(of: isFocused) {
            if $1 {
                owner = $value
            } else {
                commit()
                owner = nil
            }
        }
    }

    @ViewBuilder
    private var number: some View {
        let field = TextField(title, text: $text)
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit(commit)
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let steps = press.modifiers.contains(.shift) ? 10.0 : 1
                set((typed ?? value) + (press.key == .upArrow ? step : -step) * steps)
                return .handled
            }
        if alignment == .leading {
            field.fixedSize().padding(.trailing, -4)
        } else {
            field.multilineTextAlignment(.trailing)
        }
    }

    private var typed: Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        // A parse in the Mac's format stops at the other decimal mark, taking 12.5 for 12 in German.
        return Double(text.replacing(",", with: ".")) ?? (try? Double(text, format: .number.grouping(.never)))
    }

    private func commit() {
        let target = owner ?? $value
        guard text != formatted(target.wrappedValue) else { return }
        if let typed { set(typed, on: target) } else { text = formatted(value) }
    }

    private func set(_ new: Double, on target: Binding<Double>? = nil) {
        let target = target ?? owner ?? $value
        let new = min(max((new / step).rounded() * step, range.lowerBound), range.upperBound)
        // Within a thousandth of a step: rounding to the step can leave the same number a hair apart.
        if abs(new - target.wrappedValue) > step / 1000 { target.wrappedValue = new }
        text = formatted(value)
    }

    private func formatted(_ value: Double) -> String {
        Self.formatted(value, step: step)
    }

    private static func formatted(_ value: Double, step: Double) -> String {
        let decimals = step < 0.1 ? 2 : step < 1 ? 1 : 0
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...max(decimals, 1))))
    }
}

struct DetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}

struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(.rect)
    }
}

struct StillPushButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StillPushButton(label: configuration.label)
    }

    private struct StillPushButton: View {
        let label: Configuration.Label
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(isEnabled ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 6))
                .contentShape(.rect(cornerRadius: 6))
        }
    }
}

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

struct CardListButton {
    let title: String
    let help: String
    let action: () -> Void
}

extension View {
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
        .background(.fill.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    func cardRow(_ index: Int) -> some View {
        listRowBackground(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
            .listRowSeparator(.hidden)
    }
}

struct FolderActivationPicker: View {
    let folder: WatchedFolder
    let askForApp: () -> Void
    @Environment(AppModel.self) private var model

    private static let active = "\u{0}active", specificApp = "\u{0}app"

    var body: some View {
        Picker(selection: Binding(
            get: { folder.isActive ? Self.active : folder.appName ?? "" },
            set: { choice in
                switch choice {
                case Self.specificApp: askForApp()
                case Self.active: model.setActivation(ofFolder: folder.id, active: true, app: nil)
                default: model.setActivation(ofFolder: folder.id, active: false, app: choice.isEmpty ? nil : choice)
                }
            }
        )) {
            Text("Inactive").tag("")
            Text("Active").tag(Self.active)
            Text("Active in Adobe Apps").tag("Adobe")
            if let app = folder.appName, app != "Adobe" {
                Text("Active in \(FaceState.appDescription(app))").tag(app)
            }
            Divider()
            Text("Active in Specific App").tag(Self.specificApp)
        } label: {
            Label("Fonts in This Location", systemImage: "switch.2")
        }
    }
}

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

struct IconSegments<Value: Hashable>: NSViewRepresentable {
    let title: String
    let options: [(title: String, systemImage: String, value: Value)]
    @Binding var selection: Value
    private let segmentWidth: CGFloat = 24

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = options.map { NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: $0.title) ?? NSImage() }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne, target: context.coordinator,
                                         action: #selector(SegmentTarget.choose(_:)))
        // A set width: segments that size themselves measure 77 pt before the control is in a window and 74 pt once it is.
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

enum CaseConversion: CaseIterable {
    case upper, title, lower

    var label: String {
        switch self {
        case .upper: "AA"
        case .title: "Aa"
        case .lower: "aa"
        }
    }

    var title: String {
        switch self {
        case .upper: "Uppercase"
        case .title: "Capitalize"
        case .lower: "Lowercase"
        }
    }

    func apply(to text: String, capitalSharpS: Bool = false) -> String {
        switch self {
        // Not in the Mac's language, which would put a Turkish user's i in capitals as İ.
        case .upper: (capitalSharpS ? text.replacingOccurrences(of: "ß", with: "ẞ") : text).uppercased()
        case .title: text.capitalized
        case .lower: text.lowercased()
        }
    }
}

struct CaseChange: Equatable {
    let conversion: CaseConversion
    let number: Int

    static func next(_ conversion: CaseConversion, after last: CaseChange?) -> CaseChange {
        CaseChange(conversion: conversion, number: (last?.number ?? 0) + 1)
    }
}

struct CaseButtons: NSViewRepresentable {
    let convert: (CaseConversion) -> Void
    private let labelPadding: CGFloat = 14

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: CaseConversion.allCases.map(\.label), trackingMode: .momentary,
                                         target: context.coordinator, action: #selector(SegmentTarget.choose(_:)))
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let widest = CaseConversion.allCases.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let segmentWidth = (widest + labelPadding).rounded(.up)
        for (index, conversion) in CaseConversion.allCases.enumerated() {
            control.setWidth(segmentWidth, forSegment: index)
            control.setToolTip(conversion.title, forSegment: index)
        }
        control.setAccessibilityLabel("Case")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onChoose = { index in
            guard CaseConversion.allCases.indices.contains(index) else { return }
            convert(CaseConversion.allCases[index])
        }
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
    @ViewBuilder func fadingTopBar(@ViewBuilder _ bar: () -> some View) -> some View {
        let fade: CGFloat = 18
        let fadingBar = bar()
            .background(.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.background)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: fade)
                    .offset(y: fade)
                    .allowsHitTesting(false)
            }
        if #available(macOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
                .contentMargins(.top, fade, for: .scrollContent)
                .safeAreaBar(edge: .top, spacing: 0) { fadingBar }
        } else {
            contentMargins(.top, fade, for: .scrollContent)
                .safeAreaInset(edge: .top, spacing: 0) { fadingBar }
        }
    }

    func formFooter() -> some View {
        padding(.top, -4)
    }

    func formRowCentered() -> some View {
        offset(y: 2)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    struct Child {
        var size: CGSize
        var baseline: CGFloat
    }

    func makeCache(subviews: Subviews) -> [Child] {
        subviews.map { subview in
            let dimensions = subview.dimensions(in: .unspecified)
            return Child(size: CGSize(width: dimensions.width, height: dimensions.height), baseline: dimensions[.firstTextBaseline])
        }
    }

    func updateCache(_ cache: inout [Child], subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [Child]) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(of: cache, width: width)
        let widest = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: min(widest, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [Child]) {
        var y = bounds.minY
        for line in lines(of: cache, width: bounds.width) {
            var x = bounds.minX
            for index in line.children {
                let child = cache[index]
                subviews[index].place(at: CGPoint(x: x, y: y + line.baseline - child.baseline), proposal: ProposedViewSize(child.size))
                x += child.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var children: [Int] = []
        var width: CGFloat = 0
        var baseline: CGFloat = 0
        var below: CGFloat = 0
        var height: CGFloat { baseline + below }
    }

    private func lines(of children: [Child], width: CGFloat) -> [Line] {
        var lines: [Line] = []
        for (index, child) in children.enumerated() {
            let gap = lines.last.map { $0.children.isEmpty ? 0 : spacing } ?? 0
            if lines.isEmpty || (lines[lines.count - 1].width > 0 && lines[lines.count - 1].width + gap + child.size.width > width) {
                lines.append(Line())
            }
            var line = lines.removeLast()
            line.width += (line.children.isEmpty ? 0 : spacing) + child.size.width
            line.baseline = max(line.baseline, child.baseline)
            line.below = max(line.below, child.size.height - child.baseline)
            line.children.append(index)
            lines.append(line)
        }
        return lines
    }
}

struct OwnPreviewOptions {
    var text: Binding<String>
    var placeholder: String
    var size: Binding<Double>
    var sizeRange: ClosedRange<Double>
}

struct PreviewOptionsButton: View {
    var own: OwnPreviewOptions?
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Preview Options", systemImage: "textformat.size")
        }
        .toolbarButtonStyle()
        .help("Preview text and size")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { PreviewOptions(own: own) }
    }
}

private struct PreviewOptions: View {
    @Environment(PreviewSettings.self) private var preview
    let own: OwnPreviewOptions?

    var body: some View {
        @Bindable var preview = preview
        let text = own?.text ?? $preview.sampleText
        Form {
            Section {
                TextField("Preview Text", text: text, prompt: Text(own?.placeholder ?? "Preview Text"))
                    .labelsHidden()
                HStack {
                    Menu("Presets\u{200A}") {
                        ForEach(preview.savedPresets, id: \.self) { sample in
                            Button(Self.title(of: sample)) { text.wrappedValue = sample }
                        }
                        if !preview.savedPresets.isEmpty {
                            Divider()
                        }
                        ForEach(PreviewSettings.presets, id: \.self) { sample in
                            Button(sample) { text.wrappedValue = sample }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    Spacer()
                    if preview.isSavedPreset(text.wrappedValue) {
                        Button("Remove Preset") { preview.savedPresets.removeAll { $0 == text.wrappedValue } }
                            .help("Takes the preview text out of Presets")
                    } else {
                        Button("Save as Preset") { preview.savedPresets.append(text.wrappedValue) }
                            .disabled(!preview.canSavePreset(text.wrappedValue))
                            .help("Adds the preview text to Presets")
                    }
                }
                // ß in capitals is SS, as the text is set in every font, not all of which have ẞ.
                LabeledContent("Case") {
                    CaseButtons { text.wrappedValue = $0.apply(to: text.wrappedValue) }
                }
            }
            Section {
                if let own {
                    row("Size", own.size, range: own.sizeRange, unit: " pt")
                } else if let factor = GridScale.shared.factor {
                    row("Size", Binding {
                        GridScale.drawn(preview.size, factor: factor)
                    } set: {
                        preview.size = min(max(GridScale.chosen(drawing: $0, factor: factor), PreviewSettings.sizes.lowerBound), PreviewSettings.sizes.upperBound)
                    }, range: GridScale.drawn(PreviewSettings.sizes.lowerBound, factor: factor)...GridScale.drawn(PreviewSettings.sizes.upperBound, factor: factor), unit: " pt")
                    .help("The size the grid shows now. With the sidebar shown and the Info panel closed, it’s \(Int(preview.size)) pt.")
                } else {
                    row("Size", $preview.size, range: PreviewSettings.sizes, unit: " pt")
                }
            }
        }
        .formStyle(.grouped)
        .popoverFormMargins()
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func title(of preset: String) -> String {
        preset.count > 48 ? String(preset.prefix(47)) + "…" : preset
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

extension View {
    @ViewBuilder func popoverFormMargins() -> some View {
        if #available(macOS 26, *) {
            self
        } else {
            // Not contentMargins, which add to the 20 pt macOS 15 leaves around a popover's sections rather than replace them.
            padding(-10)
        }
    }
}

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
