import AppKit
import CiceroCore
import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    var title: String { rawValue.capitalized }

    /// A dot for menus, which draw SF Symbols as templates, in one colour.
    var menuImage: NSImage {
        let nsColor = NSColor(color)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// A family's tag colours as small overlapping dots, as the Finder shows them next to a name.
struct TagDots: View {
    let colors: [TagColor]

    var body: some View {
        if !colors.isEmpty {
            HStack(spacing: -3) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 8, height: 8)
                        .overlay { Circle().strokeBorder(Color.canvas, lineWidth: 1).padding(-1) }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(colors.map(\.title).formatted(.list(type: .and)))
        }
    }
}

/// The Tags submenu of a family's menu and the Info panel: a switch per tag and New Tag….
struct TagMenuItems: View {
    let families: [Family]
    let model: AppModel

    var body: some View {
        ForEach(model.data.tags, id: \.self) { tag in
            Toggle(isOn: Binding(
                get: { families.allSatisfy { model.hasTag(tag, $0) } },
                set: { model.setTag(tag, $0, for: families) }
            )) {
                if let color = model.data.tagColors[tag] {
                    Label { Text(tag) } icon: { Image(nsImage: color.menuImage) }
                } else {
                    Text(tag)
                }
            }
        }
        if !model.data.tags.isEmpty { Divider() }
        Button("New Tag…") { model.newTag(for: families) }
    }
}
