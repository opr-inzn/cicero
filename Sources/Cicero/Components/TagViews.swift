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
        case .sand: Self.sand
        }
    }

    private static let sand = Color(nsColor: NSColor(name: "sand") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.82, green: 0.75, blue: 0.62, alpha: 1)
            : NSColor(srgbRed: 0.76, green: 0.66, blue: 0.50, alpha: 1)
    })

    var title: String { rawValue.capitalized }

    var menuImage: NSImage { .menuDot(NSColor(color)) }
}

extension NSImage {
    // Not an SF Symbol, which menus draw as a template in one colour. Its label needs .titleAndIcon: built with the macOS 27 SDK, menus hide every other image.
    static func menuDot(_ color: NSColor, size: CGFloat = 12, inset: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct TagDots: View {
    let colors: [TagColor]

    var body: some View {
        if !colors.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(colors.map(\.title).listed())
        }
    }
}

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
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(tag)
                }
            }
        }
        Divider()
        Button("Remove All Tags", systemImage: "tag.slash") { model.removeTags(from: families) }
            .disabled(families.allSatisfy { model.data.tags(of: $0.id).isEmpty })
        Button("New Tag", systemImage: "plus") { model.newTag(for: families) }
    }
}
