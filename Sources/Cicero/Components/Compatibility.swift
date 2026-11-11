import SwiftUI

extension View {
    @ViewBuilder func glass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background {
                shape.fill(.bar)
                    .overlay(shape.stroke(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
        }
    }

    @ViewBuilder func topBar(@ViewBuilder _ bar: () -> some View) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { bar().background(.bar) }
        }
    }

    @ViewBuilder func bottomBar(@ViewBuilder _ bar: () -> some View) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) { bar().frame(maxWidth: .infinity).background(.bar) }
        }
    }

    @ViewBuilder func hardTopScrollEdge(_ isHard: Bool = true) -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(isHard ? .hard : nil, for: .top) } else { self }
    }

    func toolbarGlassFollowsAppearance() -> some View {
        modifier(FreshScrollEdges())
    }

    @ViewBuilder func lineHeight(_ points: Double?, natural: Double) -> some View {
        if #available(macOS 26, *) {
            lineHeight(points.map { .exact(points: $0) })
        } else {
            lineSpacing(points.map { max(0, $0 - natural) } ?? 0)
        }
    }
}

private struct FreshScrollEdges: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHard = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .scrollEdgeEffectStyle(isHard ? .hard : nil, for: .top)
                .onChange(of: colorScheme) {
                    // Hard for a moment, so macOS sets the top edges up afresh: on macOS 26 the toolbar's glass over them could keep the old appearance until something scrolled.
                    isHard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isHard = false }
                }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func outsideFileDrops(isOver: @escaping (Bool) -> Void, perform action: @escaping ([URL]) -> Void) -> some View {
        if #available(macOS 26, *) {
            dropDestination(for: URL.self) { items, session in
                if session.localSession != nil { return }
                action(items)
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: isOver(session.localSession == nil)
                default: isOver(false)
                }
            }
        } else {
            dropDestination(for: URL.self) { items, _ in
                action(items)
                return true
            } isTargeted: { isOver($0) }
        }
    }
}

extension CTFont {
    var naturalLineHeight: Double {
        CTFontGetAscent(self) + CTFontGetDescent(self) + CTFontGetLeading(self)
    }
}

extension Section where Parent: View, Content: View, Footer: View {
    @ViewBuilder func notCollapsible() -> some View {
        if #available(macOS 26, *) { self } else { collapsible(false) }
    }
}
