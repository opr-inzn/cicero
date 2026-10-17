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

    /// A light brown between the Finder's colours, for Licensed + Non-Commercial: Licensed's, toned down.
    private static let sand = Color(nsColor: NSColor(name: "sand") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.82, green: 0.75, blue: 0.62, alpha: 1)
            : NSColor(srgbRed: 0.76, green: 0.66, blue: 0.50, alpha: 1)
    })

    var title: String { rawValue.capitalized }

    /// A dot for menus, which draw SF Symbols as templates, in one colour. Its label needs `.titleAndIcon`: built
    /// with the macOS 27 SDK, menus hide every other image.
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

    /// No Status's dot in menus: grey, like a status without a colour.
    static var noStatusImage: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// A family's license status as a small dot in its colour; side by side for one with several from before a family had
/// one at a time.
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
            .accessibilityLabel(colors.map(\.title).formatted(.list(type: .and)))
        }
    }
}

/// The License Status submenu of a family's menu and the Info panel: the statuses, the families' checked, No Status,
/// and New License Status…. Choosing one gives the families that status in place of the one they have.
struct TagMenuItems: View {
    let families: [Family]
    let model: AppModel

    var body: some View {
        ForEach(model.data.tags, id: \.self) { tag in
            Toggle(isOn: Binding(
                get: { families.allSatisfy { model.hasTag(tag, $0) } },
                set: { model.setLicenseStatus($0 ? tag : nil, for: families) }
            )) {
                if let color = model.data.tagColors[tag] {
                    Label { Text(tag) } icon: { Image(nsImage: color.menuImage) }
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(tag)
                }
            }
        }
        Toggle(isOn: Binding(
            get: { families.allSatisfy { model.data.tags(of: $0.id).isEmpty } },
            set: { if $0 { model.setLicenseStatus(nil, for: families) } }
        )) {
            Label { Text("No Status") } icon: { Image(nsImage: TagColor.noStatusImage) }
                .labelStyle(.titleAndIcon)
        }
        Divider()
        Button("New License Status", systemImage: "plus") { model.newTag(for: families) }
    }
}
