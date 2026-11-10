import AppKit
import SwiftUI

nonisolated struct GlyphHeading: Hashable, Sendable {
    let index: Int
    let category: String
    let name: String?
    let detail: String
    let startsCategory: Bool

    init(index: Int, category: String, name: String, detail: String, after previous: String?) {
        self.index = index
        self.category = category
        self.name = name == category ? nil : name
        self.detail = detail
        startsCategory = previous != category
    }
}

extension EnvironmentValues {
    @Entry var pinsHeadings = true
}

@Observable
final class GlyphsTitle {
    var y: CGFloat?
}

extension EnvironmentValues {
    @Entry var glyphsTitle: GlyphsTitle?
}

private struct WhenPinned: ViewModifier {
    @Environment(\.pinsHeadings) private var pins
    let always: Bool
    var below: CGFloat = 0

    func body(content: Content) -> some View {
        content.visualEffect { [pins, always, below] content, proxy in
            content.opacity(always || pins && proxy.frame(in: .scrollView).minY <= below + 1.5 ? 1 : 0)
        }
    }
}

struct GlyphHeader: View {
    static let line = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .headline)).rounded(.up)
    static let barHeight = line + 4
    static let headingHeight = line + 8

    @Environment(\.pinsHeadings) private var pins
    let heading: GlyphHeading

    var body: some View {
        let height = heading.name == nil ? Self.barHeight : Self.barHeight + Self.headingHeight
        VStack(alignment: .leading, spacing: 0) {
            CategoryBar(heading: heading)
                .modifier(WhenPinned(always: heading.startsCategory || heading.name == nil))
                .accessibilityHidden(!heading.startsCategory && heading.name != nil)
            if let name = heading.name {
                HStack(spacing: 4) {
                    Text(name).font(.headline).foregroundStyle(.primary.opacity(0.82))
                        .accessibilityLabel("\(heading.category), \(name)")
                        .accessibilityAddTraits(.isHeader)
                    Text(heading.detail).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, GlyphsSection.inset)
                .frame(height: Self.headingHeight, alignment: .top)
            }
        }
        .background(Color.canvas)
        .background(alignment: .top) {
            Color.canvas.frame(height: 200).alignmentGuide(.top) { $0[.bottom] }
                .modifier(WhenPinned(always: false, below: -200))
        }
        .overlay(alignment: .bottom) { Divider().modifier(WhenPinned(always: false, below: height - 1)) }
        .visualEffect { [pins, height] content, proxy in
            let y = proxy.frame(in: .scrollView).minY
            let pushed = pins && y < 0.5 && y > -height + 0.5
            return content.offset(y: pushed ? -y : 0).opacity(pins && y <= -height + 0.5 ? 0 : 1)
        }
        .zIndex(Double(100_000 - heading.index))
    }
}

private struct CategoryBar: View {
    let heading: GlyphHeading

    var body: some View {
        HStack(spacing: 4) {
            Text(heading.category).font(.headline)
                .accessibilityAddTraits(.isHeader)
            if heading.name == nil {
                Text(heading.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, GlyphsSection.inset)
        .frame(height: GlyphHeader.barHeight, alignment: .bottom)
    }
}
