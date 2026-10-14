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

/// A segmented picker for toolbars, its choice highlighted like a toggle that's on. Segments show a
/// symbol when there's one, else the title.
struct ToolbarPicker<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let symbol: ((Value) -> String)?

    init(_ values: [Value], selection: Binding<Value>, title: @escaping (Value) -> String, symbol: ((Value) -> String)? = nil) {
        self.values = values
        _selection = selection
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        // Segments as wide as the widest, like AppKit's.
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    if let symbol { Label(title(value), systemImage: symbol(value)) } else { Text(title(value)) }
                }
                .buttonStyle(ToolbarButtonStyle(isOn: selection == value, segment: symbol == nil ? .title : .symbol))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

/// A toolbar button, highlighted while it's on or pressed, and dimmed like AppKit's while it's disabled
/// or its window is in the background. Sizes are AppKit's: a button fills its 36 pt glass capsule, and a
/// picker's segment is highlighted inside it.
struct ToolbarButtonStyle: ButtonStyle {
    var isOn = false
    fileprivate var segment: Segment?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive

    /// A picker's segment, padded like AppKit's: less around a symbol than around a title.
    fileprivate enum Segment { case symbol, title }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .foregroundStyle(isEnabled && appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, segment == .title ? 12 : segment == .symbol ? 6 : 8)
            .frame(minWidth: segment == nil ? 36 : 34, maxWidth: segment == nil ? nil : .infinity, minHeight: segment == nil ? 36 : 28)
            .background(isOn || configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .capsule)
            .padding(.horizontal, segment == nil ? 0 : 1.5)
            .padding(.vertical, segment == nil ? 0 : 4)
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
