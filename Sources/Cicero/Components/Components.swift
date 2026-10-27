import AppKit
import CiceroCore
import SwiftUI

extension Color {
    /// The background behind specimens: the text background, light or dark with the appearance.
    static let canvas = Color(nsColor: .textBackgroundColor)
    /// Specimen text on it: the text colour, full black or white, as in the type tester, rather than the labels' grey.
    static let ink = Color(nsColor: .textColor)
    /// The Variable tag's: green, which no status tag uses (teal was too close to Temporary's blue), darker than the
    /// system green in light mode, which is too light for small text on its own tint.
    static let variable = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemGreen : NSColor(srgbRed: 0.16, green: 0.55, blue: 0.24, alpha: 1)
    })
    /// The App Folder tag's: graphite, a blue-grey, so it doesn't look like Temporary's blue or System's grey.
    static let appSet = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.72, green: 0.77, blue: 0.85, alpha: 1)
            : NSColor(srgbRed: 0.27, green: 0.31, blue: 0.38, alpha: 1)
    })
}

/// Text set in a font face, straight from its file (so it works for fonts that aren't active). A file on a server, or one
/// a cloud service keeps online only, is read off the main thread first, with room kept for the text: a server that's slow
/// to answer, or stopped answering, never holds up the window.
struct FontText: View {
    let text: String
    let face: FontFace
    let size: Double
    var weight: Double = 400
    /// Axes moved in the Info panel, by tag.
    var variations: [String: Double] = [:]
    var features: [FeatureSetting] = []
    var lineLimit: Int? = 1
    /// For text that runs over several lines, the distance from one line's baseline to the next in points; nil for the
    /// font's own line spacing.
    var lineHeight: Double?
    /// What to multiply the size by, for the font at the size: the grid draws fonts too wide for its tiles smaller.
    var scale: ((CTFont) -> CGFloat)?
    /// False makes the font without keeping it, for text whose size changes smoothly, as Quick Look's does while its
    /// panel is resized: kept, every size would push fonts on screen out of the cache, which keeps sizes to half a point
    /// and so would hand back a font a little bigger or smaller.
    var cached = true
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
        } else {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: size))
                .lineLimit(lineLimit)
                .lineHeight(lineHeight, natural: (NSFont.systemFont(ofSize: size) as CTFont).naturalLineHeight)
                .hidden()
                .task(id: face.path) {
                    await FontLoader.shared.read(face.path)
                    readPath = face.path
                }
        }
    }
}

/// Its content once the font files it draws from have been read, so making their fonts never reads a file on the main
/// thread: at once when they're on the Mac's own disks or were read before, as almost all are; for files on a server,
/// or online only, once they've been read in the background, with empty room in its place meanwhile (see
/// `FontLoader.wouldWait`).
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
    /// A symbol before the text.
    var systemImage: String?
    /// Filled with the tint, the text in black, rather than tinted: for a label that isn't a status, like BETA,
    /// so it stands out and never reads as one.
    var isFilled = false

    var body: some View {
        HStack(spacing: 2.5) {
            if let systemImage {
                // Its drawing on the middle of the capitals, with no height of its own, so tags with a symbol are as
                // tall as those without.
                Image(systemName: systemImage)
                    .offset(y: Self.capitalsDrop - Self.inkDrop(of: systemImage))
                    .frame(height: 0)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(Self.font)
        .padding(.horizontal, 5)
        // The capitals in the middle of the capsule, measured at 1x and 2x. They sit on whole pixels, so the capsule is
        // 14.5 pt high: at 2x that leaves 16 pixels around the 13 of the capitals, 8 above and 8 below, and at 1x it's 15
        // pixels, within an eighth of one. At 14 pt they were half a pixel high at 2x and a third at 1x. Any top from 1.5
        // to 1.7 pt does it; 1.6 keeps away from both ends.
        .padding(.top, 1.6)
        .padding(.bottom, 1.9)
        .background(tint.opacity(isFilled ? 1 : 0.14), in: .capsule)
        .foregroundStyle(isFilled ? Color.black : tint.opacity(0.9))
        .fixedSize()
    }

    private static let font = Font.system(size: 9, weight: .semibold)

    /// How far the middle of the capitals sits below the middle of the text's line: SwiftUI puts the line's height and
    /// baseline on whole points, as NSLayoutManager does, which leaves them a third of a point low.
    private static let capitalsDrop: CGFloat = {
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let layout = NSLayoutManager()
        return layout.defaultBaselineOffset(for: font) - font.capHeight / 2 - layout.defaultLineHeight(for: font) / 2
    }()

    private static var inkDrops: [String: CGFloat] = [:]

    /// How far the middle of a symbol's drawing sits below the middle of its frame, measured once per symbol: some
    /// frames leave room the drawing doesn't use, like app.badge.checkmark's, which drew it 0.35 pt high.
    private static func inkDrop(of symbol: String) -> CGFloat {
        if let drop = inkDrops[symbol] { return drop }
        let scale = 20
        let renderer = ImageRenderer(content: Image(systemName: symbol).font(font))
        renderer.scale = CGFloat(scale)
        var drop: CGFloat = 0
        if let image = renderer.cgImage,
           let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                   bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let pixels = context.data?.assumingMemoryBound(to: UInt8.self) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // The rows with ink, from the top.
            let inked = (0..<image.height).filter { row in
                (0..<image.width).contains { pixels[(row * image.width + $0) * 4 + 3] > 127 }
            }
            if let top = inked.first, let bottom = inked.last {
                drop = CGFloat(top + bottom + 1 - image.height) / 2 / CGFloat(scale)
            }
        }
        inkDrops[symbol] = drop
        return drop
    }
}

/// Marks a variable family wherever it's listed, apart from the kinds of file, with the symbol of its axes and, on
/// hover, their names.
struct VariableTag: View {
    let family: Family

    var body: some View {
        if family.isVariable {
            Tag(text: "Variable", tint: .variable, systemImage: "slider.horizontal.3")
                .help(help)
        }
    }

    /// "Variable: Weight, Width, Optical Size", the axes of all its styles in the font's order.
    private var help: String {
        var axes: [VariationAxis] = []
        for face in family.faces {
            for axis in face.face.axes where !axes.contains(where: { $0.name == axis.name }) { axes.append(axis) }
        }
        return axes.isEmpty ? "Variable" : "Variable: " + axes.map(\.name).joined(separator: ", ")
    }
}

/// A small capsule for families that aren't simply on or off.
struct StatusTag: View {
    let family: Family

    var body: some View {
        if let (text, tint, symbol) = content {
            Tag(text: text, tint: tint, systemImage: symbol).help(help)
        }
    }

    private var content: (String, Color, String?)? {
        // With the symbols of New App Folder and Activate Temporarily.
        if family.temporaryScope == .whileAppsRun { return ("App Folder", .appSet, "app.badge.checkmark") }
        if family.temporaryScope != nil { return ("Temporary", .blue, "clock") }
        // Creative Cloud's, apart from the fonts type designers put in Adobe's folders to test them, tagged Proofing.
        if family.isAdobeFonts { return ("Adobe Fonts", .purple, nil) }
        switch family.state {
        case .system: return ("System", .secondary, nil)
        case .partial: return ("Partly active", .orange, nil)
        case .appOnly(let app): return (app == "Adobe" ? "Proofing" : app, .red, nil)
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

/// The system slider on macOS 27, which draws it itself, and one drawn by Cicero before that: macOS 26's slider's
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
    /// Where the number sits in the field's width: trailing lines values up in a column, 52 pt wide; leading keeps it
    /// as close to the slider as a label is on the other side, in a field as wide as the widest value the range allows.
    var alignment = HorizontalAlignment.trailing
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, unit: String = "", alignment: HorizontalAlignment = .trailing) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.alignment = alignment
        // The number from the start, not once it appears: a field measured before it's on screen, as the font page's
        // controls measure theirs to choose a layout (see `TesterControls`), would measure as wide as its title, which it
        // shows while empty.
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
                // Nothing after it moves as the value changes, and a row's last value ends where the row does.
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
        // The slider moved; typing leaves the value alone until it's committed.
        .onChange(of: value) { text = formatted($1) }
        .onChange(of: isFocused) { if !$1 { commit() } }
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
            // As wide as the number, growing as it's typed, so the unit follows it; the field keeps 4 pt for
            // the caret after the number, which the unit takes back to sit as close as after a right-aligned one.
            field.fixedSize().padding(.trailing, -4)
        } else {
            field.multilineTextAlignment(.trailing)
        }
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
        Self.formatted(value, step: step)
    }

    private static func formatted(_ value: Double, step: Double) -> String {
        String(format: step < 0.1 ? "%.2f" : step < 1 ? "%.1f" : "%.0f", value)
    }
}

/// A button that's just its label, the same while it's held down: a plain one darkens it as it's clicked.
struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(.rect)
    }
}

/// A push button the same as the default one, to the pixel on macOS 26, in light and dark, that stays the same while
/// it's held down rather than darkening. Greyed out within a point or two of the default one.
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
    /// A list in a card with + and − along its bottom, like the lists in System Settings: Settings → Locations,
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

/// What a folder's fonts are, in its row in Settings → Locations and its menu in the sidebar: Inactive, Active
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
            Label("Fonts in This Location", systemImage: "switch.2")
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

    /// As wide as its widest choice, whichever is chosen.
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
    /// A bar over the top of the scroll view in this view, on the window's background, which what scrolls under it
    /// fades into just below it, as under the main window's title, rather than meeting at an edge. The system's soft
    /// edge fades less far than a tall bar reaches, so rows showed behind its lower half. macOS 15 has no edge effect to
    /// hide, and an inset that what scrolls goes under does the same there.
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

/// Lays children out left to right, wrapping onto new lines, each line's children on its first text's baseline: a
/// family's styles, each set in itself, would otherwise sit as high as each face's ascent puts it.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// A child's size and how far down its first text's baseline is.
    struct Child {
        var size: CGSize
        var baseline: CGFloat
    }

    /// The children measured once per update rather than for every proposal and again to place them: specimens are
    /// a lazy stack's rows, which it measures over and over while scrolling, and each child is text in a face of its
    /// own.
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

    /// The children on a line, its width, its baseline, as far down as the lowest of theirs, and its height, down to
    /// the lowest of their bottoms below that.
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

/// The toolbar button with sample text, size, weight and spacing.
struct PreviewOptionsButton: View {
    /// A size of the window's own, as Compare has, in place of the previews'.
    var size: Binding<Double>?
    var sizeRange: ClosedRange<Double> = PreviewSettings.sizes
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Preview Options", systemImage: "textformat.size")
        }
        .toolbarButtonStyle()
        .help("Preview text, size and leading")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { PreviewOptions(size: size, sizeRange: sizeRange) }
    }
}

private struct PreviewOptions: View {
    @Environment(PreviewSettings.self) private var preview
    let size: Binding<Double>?
    let sizeRange: ClosedRange<Double>

    var body: some View {
        @Bindable var preview = preview
        Form {
            Section {
                TextField("Preview Text", text: $preview.sampleText, prompt: Text("Preview Text"))
                    .labelsHidden()
                HStack {
                    // A hair space after the word: the button's own chevron a point further from it, 5 pt rather than 4.
                    Menu("Presets\u{200A}") {
                        // Yours first, in the order saved, then Cicero's.
                        ForEach(preview.savedPresets, id: \.self) { sample in
                            Button(Self.title(of: sample)) { preview.sampleText = sample }
                        }
                        if !preview.savedPresets.isEmpty {
                            Divider()
                        }
                        ForEach(PreviewSettings.presets, id: \.self) { sample in
                            Button(sample) { preview.sampleText = sample }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    Spacer()
                    // Once the text is one of yours, the button takes it out again.
                    if preview.isSavedPreset {
                        Button("Remove Preset") { preview.savedPresets.removeAll { $0 == preview.sampleText } }
                            .help("Takes the preview text out of Presets")
                    } else {
                        Button("Save as Preset") { preview.savedPresets.append(preview.sampleText) }
                            .disabled(!preview.canSavePreset)
                            .help("Adds the preview text to Presets")
                    }
                }
            }
            Section {
                if size == nil, let factor = GridScale.shared.factor {
                    // The size the grid draws at while the sidebar is hidden or the Info panel open (see `GridScale`).
                    row("Size", Binding {
                        GridScale.drawn(preview.size, factor: factor)
                    } set: {
                        preview.size = min(max(GridScale.chosen(drawing: $0, factor: factor), sizeRange.lowerBound), sizeRange.upperBound)
                    }, range: GridScale.drawn(sizeRange.lowerBound, factor: factor)...GridScale.drawn(sizeRange.upperBound, factor: factor), unit: " pt")
                    .help("The grid’s size while the sidebar is hidden or the Info panel open: \(Int(preview.size)) pt with the sidebar shown and the panel closed")
                } else {
                    row("Size", size ?? $preview.size, range: sizeRange, unit: " pt")
                }
                row("Leading", $preview.lineSpacing, range: PreviewSettings.lineSpacings, step: 5, unit: "%")
                    .help("The distance between lines, in percent of the size, where a sample runs over several lines")
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A preset as its menu item shows it: a long one cut short, so the menu isn't as wide as the text.
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
