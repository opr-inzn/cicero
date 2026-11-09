import SwiftUI

// What Cicero uses of macOS 26, with what macOS 15 has instead: there Cicero looks as apps do on macOS 15, with
// materials where macOS 26 has glass.

extension View {
    @ViewBuilder func glass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
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

    @ViewBuilder func hardTopScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
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
    @ViewBuilder func drops<T: Transferable>(of type: T.Type, fromOutsideOnly: Bool = false, isOver: ((Bool) -> Void)? = nil,
                                             perform action: @escaping ([T]) -> Void) -> some View {
        if #available(macOS 26, *) {
            let destination = dropDestination(for: type) { items, session in
                if fromOutsideOnly, session.localSession != nil { return }
                action(items)
            }
            if let isOver {
                destination.onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active: isOver(!fromOutsideOnly || session.localSession == nil)
                    default: isOver(false)
                    }
                }
            } else {
                destination
            }
        } else {
            dropDestination(for: type) { items, _ in
                action(items)
                return true
            } isTargeted: { isOver?($0) }
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
