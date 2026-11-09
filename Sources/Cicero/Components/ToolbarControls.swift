import SwiftUI

struct ToolbarCapsule<Content: View>: ToolbarContent {
    var spaced = false
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(macOS 26, *), spaced {
            ToolbarSpacer(.fixed)
            ToolbarItem { content() }
        } else {
            ToolbarItem { content() }
        }
    }
}

struct ToolbarGap: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }
}

struct ToolbarPicker<Value: Hashable>: View {
    let label: String
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let symbol: ((Value) -> String)?
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
        // To accessibility, a segmented control: as buttons in a toolbar item, every segment took its name from the item, the first segment's title, as soon as the window updated.
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(values, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(label)
        }
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    var isOn = false
    fileprivate var segment: Segment?

    fileprivate enum Segment { case symbol, title }

    static let segmentInset: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        ToolbarButton(configuration: configuration, isOn: isOn, segment: segment)
    }
}

private struct ToolbarButton: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    let segment: ToolbarButtonStyle.Segment?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @State private var isHovered = false

    var body: some View {
        let pressed = segment == nil ? isOn || configuration.isPressed : configuration.isPressed && !isOn
        let hovered = isHovered && isEnabled && !(segment != nil && isOn)
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .foregroundStyle(isEnabled && appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, segment == .title ? 12 : segment == .symbol ? 6 : 8)
            .frame(minWidth: segment == nil ? 36 : 36 - 2 * ToolbarButtonStyle.segmentInset, maxWidth: segment == nil ? nil : .infinity,
                   minHeight: 36 - (segment == nil ? 0 : 2 * ToolbarButtonStyle.segmentInset))
            .background(pressed ? AnyShapeStyle(.quaternary) : hovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear), in: .capsule)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}

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
    @ViewBuilder func toolbarButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.toolbar) } else { self }
    }
}

extension ToggleStyle where Self == ToolbarToggleStyle {
    static var toolbar: ToolbarToggleStyle { ToolbarToggleStyle() }
}
