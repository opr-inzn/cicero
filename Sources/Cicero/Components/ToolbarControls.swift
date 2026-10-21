import SwiftUI

// Toolbar controls that highlight only what's chosen or on, never what's under the pointer: AppKit's
// light up on hover, in a gray of their own, and Cicero has no hover states. On macOS 15, which has no glass, the
// toolbar has the system's own controls instead.

/// A toolbar item in a glass capsule of its own, 8 pt from the next as the Info button is from the search
/// field. AppKit puts neighbouring items in one capsule, and a ToolbarSpacer between them leaves 16 pt.
struct ToolbarCapsule<Content: View>: ToolbarContent {
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem { content().glassEffect(.regular, in: .capsule) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem { content() }
        }
    }
}

/// A segmented picker for toolbars, its choice on a lens of glass that slides to the next one chosen, 3 pt inside the
/// capsule all round. Segments show a symbol when there's one, else the title.
struct ToolbarPicker<Value: Hashable>: View {
    /// What VoiceOver calls the control.
    let label: String
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let symbol: ((Value) -> String)?
    /// Each segment's tooltip.
    let help: String?
    @Namespace private var lens

    init(_ label: String, values: [Value], selection: Binding<Value>, title: @escaping (Value) -> String,
         symbol: ((Value) -> String)? = nil, help: String? = nil) {
        self.label = label
        self.values = values
        _selection = selection
        self.title = title
        self.symbol = symbol
        self.help = help
    }

    var body: some View {
        if #available(macOS 26, *) {
            onGlass
        } else {
            Picker(label, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Group {
                        if let symbol { Label(title(value), systemImage: symbol(value)) } else { Text(title(value)) }
                    }
                    .tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            .help(help ?? "")
        }
    }

    @available(macOS 26, *)
    private var onGlass: some View {
        // Segments as wide as the widest, like AppKit's.
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = value }
                } label: {
                    if let symbol { Label(title(value), systemImage: symbol(value)) } else { Text(title(value)) }
                }
                .buttonStyle(ToolbarButtonStyle(isOn: selection == value, segment: symbol == nil ? .title : .symbol))
                .background {
                    if selection == value {
                        // Grey on glass, so it shows on the capsule's own glass in the dark too.
                        Capsule()
                            .fill(.quaternary)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .matchedGeometryEffect(id: "lens", in: lens)
                    }
                }
                .help(help ?? "")
            }
        }
        .padding(ToolbarButtonStyle.segmentInset)
        .fixedSize()
        // To accessibility, a segmented control: as buttons in a toolbar item, every segment took its name from the
        // item, the first segment's title, as soon as the window updated.
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(values, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(label)
        }
    }
}

/// A size between − and + buttons, for a toolbar capsule. The buttons, ⌘− and ⌘+, step through common sizes,
/// ⌘= too where + takes ⇧, and the size takes one typed in.
struct ToolbarSizeStepper: View {
    @Binding var size: Double
    let range: ClosedRange<Double>
    @Environment(\.appearsActive) private var appearsActive

    /// Each a fifth to a third bigger than the one before; a size typed in between goes to the next one either way.
    static let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 24, 30, 36, 48, 60, 72, 96, 120, 144, 192, 240, 288, 384, 480, 576, 720, 960]

    var body: some View {
        HStack(spacing: 0) {
            Button("Smaller", systemImage: "minus", action: smaller)
                .keyboardShortcut("-", modifiers: .command)
                .disabled(size <= range.lowerBound)
                .help("Smaller")
            // As wide as the biggest size, so the stepper keeps its width, with the size in the middle. Grey in a
            // window in the background, as the buttons are: a toolbar greys a field's text, not the unit's.
            Text("\(Int(range.upperBound)) pt")
                .hidden()
                .overlay {
                    HStack(spacing: 0) {
                        ValueField("Size", value: $size, range: range, width: nil)
                        Text(" pt")
                    }
                    .foregroundStyle(appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .fixedSize()
                }
                .monospacedDigit()
                .padding(.horizontal, 2)
            Button("Bigger", systemImage: "plus", action: bigger)
                .keyboardShortcut("+", modifiers: .command)
                .disabled(size >= range.upperBound)
                .help("Bigger")
        }
        .modifier(StepperButtonStyle())
        .background {
            Button("Bigger", action: bigger)
                .keyboardShortcut("=", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .fixedSize()
    }

    private func bigger() {
        size = min(Self.sizes.first { $0 > size } ?? range.upperBound, range.upperBound)
    }

    private func smaller() {
        size = max(Self.sizes.last { $0 < size } ?? range.lowerBound, range.lowerBound)
    }

    /// `ToolbarButtonStyle` on macOS 26, inside the capsule's glass; on macOS 15, just the symbols, as one control.
    private struct StepperButtonStyle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 26, *) { content.buttonStyle(.toolbar) } else { content.buttonStyle(.borderless).labelStyle(.iconOnly) }
        }
    }
}

/// A toolbar button, highlighted while it's on or pressed, and dimmed like AppKit's while it's disabled
/// or its window is in the background. Sizes are AppKit's: a button fills its 36 pt glass capsule, and a
/// picker's segments are inside it, `segmentInset` from its edges; the picker draws the chosen one's lens.
struct ToolbarButtonStyle: ButtonStyle {
    var isOn = false
    fileprivate var segment: Segment?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive

    /// A picker's segment, padded like AppKit's: less around a symbol than around a title.
    fileprivate enum Segment { case symbol, title }

    /// Between a picker's segments and its capsule, at the ends as above and below.
    static let segmentInset: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        // A chosen segment has the picker's lens, not a fill.
        let filled = segment == nil ? isOn || configuration.isPressed : configuration.isPressed && !isOn
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .foregroundStyle(isEnabled && appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, segment == .title ? 12 : segment == .symbol ? 6 : 8)
            .frame(minWidth: segment == nil ? 36 : 36 - 2 * Self.segmentInset, maxWidth: segment == nil ? nil : .infinity,
                   minHeight: 36 - (segment == nil ? 0 : 2 * Self.segmentInset))
            .background(filled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .capsule)
            .contentShape(.rect)
    }
}

/// A toolbar toggle, highlighted while it's on.
struct ToolbarToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            Button { configuration.isOn.toggle() } label: { configuration.label }
                .buttonStyle(ToolbarButtonStyle(isOn: configuration.isOn))
        } else {
            Toggle(configuration).toggleStyle(.button)
        }
    }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { ToolbarButtonStyle() }
}

extension View {
    /// `ToolbarButtonStyle` on macOS 26; the system's toolbar buttons on macOS 15.
    @ViewBuilder func toolbarButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.toolbar) } else { self }
    }
}

extension ToggleStyle where Self == ToolbarToggleStyle {
    static var toolbar: ToolbarToggleStyle { ToolbarToggleStyle() }
}
