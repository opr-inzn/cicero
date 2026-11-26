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

    private static let menuImages: [TagColor: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, .menuDot(NSColor($0.color))) })

    var menuImage: NSImage { Self.menuImages[self] ?? .menuDot(NSColor(color)) }
}

extension NSImage {
    // Not an SF Symbol, which menus draw as a template in one colour. Its label needs .titleAndIcon: built with the macOS 27 SDK, menus hide every other image.
    static func menuDot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

nonisolated struct TagDot: Hashable, Sendable {
    let name: String
    let color: TagColor?
}

struct TagDots: View {
    let dots: [TagDot]

    private static let size: CGFloat = 8
    private static let step: CGFloat = 6
    private static let iconStep: CGFloat = 6
    private static let dotToIconStep: CGFloat = 3.5
    private static let iconSize = CGSize(width: 12, height: 11)
    private static let gap: CGFloat = 1.25

    var body: some View {
        if !dots.isEmpty {
            let colors = dots.compactMap(\.color)
            let marks: [TagColor?] = colors + Array(repeating: nil, count: dots.count - colors.count)
            let starts = marks.indices.map { index in
                (0..<index).reduce(CGFloat(0)) { x, previous in
                    x + (marks[previous + 1] != nil ? Self.step : marks[previous] != nil ? Self.dotToIconStep : Self.iconStep)
                }
            }
            ZStack(alignment: .leading) {
                ForEach(marks.indices.reversed(), id: \.self) { index in
                    Self.mark(marks[index])
                        .mask { cutout(index, marks: marks, starts: starts) }
                        .offset(x: starts[index])
                }
            }
            .frame(width: starts[starts.count - 1] + Self.width(marks[marks.count - 1]),
                   height: marks.contains(nil) ? Self.iconSize.height : Self.size, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel("Tags: \(dots.map(\.name).listed())")
        }
    }

    private static func width(_ mark: TagColor?) -> CGFloat { mark == nil ? iconSize.width : size }

    @ViewBuilder
    private static func mark(_ color: TagColor?) -> some View {
        if let color {
            Circle().fill(color.color).frame(width: size, height: size)
        } else {
            Image(systemName: SidebarSection.tags.icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: iconSize.width, height: iconSize.height)
        }
    }

    @ViewBuilder
    private func cutout(_ index: Int, marks: [TagColor?], starts: [CGFloat]) -> some View {
        if index == 0 {
            Rectangle()
        } else {
            let above = index - 1
            let shift = starts[above] + Self.width(marks[above]) / 2 - starts[index] - Self.width(marks[index]) / 2
            Rectangle()
                .overlay {
                    Group {
                        if marks[above] == nil {
                            ZStack {
                                ForEach(0..<8, id: \.self) { step in
                                    let angle = Double(step) * .pi / 4
                                    Image(systemName: SidebarSection.tags.icon + ".fill")
                                        .font(.system(size: 9))
                                        .offset(x: cos(angle) * Self.gap, y: sin(angle) * Self.gap)
                                }
                            }
                        } else {
                            Circle().frame(width: Self.size + 2 * Self.gap, height: Self.size + 2 * Self.gap)
                        }
                    }
                    .offset(x: shift)
                    .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

struct TagMenuItems: View {
    let families: [Family]
    let model: AppModel

    var body: some View {
        ForEach(model.data.orderedTags, id: \.self) { tag in
            Toggle(isOn: Binding(
                get: { families.allSatisfy { model.hasTag(tag, $0) } },
                set: { model.setTag(tag, $0, for: families) }
            )) {
                if let color = model.data.tagColors[tag] {
                    Label { Text(tag) } icon: { Image(nsImage: color.menuImage) }
                        .labelStyle(.titleAndIcon)
                } else {
                    Label(tag, systemImage: SidebarSection.tags.icon)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        Divider()
        Button("Remove All", systemImage: "tag.slash") { model.removeTags(from: families) }
            .disabled(families.allSatisfy { model.data.tags(of: $0.id).isEmpty })
        Button("New Tag", systemImage: "plus") { model.newTag(for: families) }
    }
}
