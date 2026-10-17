import SwiftUI

// Toolbar controls that highlight only what's chosen or on, never what's under the pointer: AppKit's
// light up on hover, in a gray of their own, and Cicero has no hover states.

/// A toolbar item in a glass capsule of its own, 8 pt from the next as the Info button is from the search
/// field. AppKit puts neighbouring items in one capsule, and a ToolbarSpacer between them leaves 16 pt.
struct ToolbarCapsule<Content: View>: ToolbarContent {
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        ToolbarItem { content().glassEffect(.regular, in: .capsule) }
            .sharedBackgroundVisibility(.hidden)
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
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(ToolbarButtonStyle(isOn: configuration.isOn))
    }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { ToolbarButtonStyle() }
}

extension ToggleStyle where Self == ToolbarToggleStyle {
    static var toolbar: ToolbarToggleStyle { ToolbarToggleStyle() }
}
