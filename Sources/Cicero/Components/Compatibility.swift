import SwiftUI

// What Cicero uses of macOS 26, with what macOS 15 has instead: there Cicero looks as apps do on macOS 15, with
// materials where macOS 26 has glass.

extension View {
    /// Liquid Glass in a shape. On macOS 15, the material of its bars, with an edge and a shadow so it stands out
    /// from a white page as glass does.
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

    /// A bar over the top of the scroll view in this view that what scrolls goes under, behind the scroll edge
    /// effect; on macOS 15, which has none, an inset on the material of its bars.
    @ViewBuilder func topBar(@ViewBuilder _ bar: () -> some View) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { bar().background(.bar) }
        }
    }

    /// A hard scroll edge along the top, a line under what's over it; macOS 15 draws none.
    @ViewBuilder func hardTopScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }

    /// The toolbar's glass in light or dark as the window is, after the appearance changes too (see
    /// `FreshScrollEdges`); macOS 15 has no glass.
    func toolbarGlassFollowsAppearance() -> some View {
        modifier(FreshScrollEdges())
    }

    /// The distance from one line's baseline to the next, in points; nil for the font's own. macOS 15 can only add
    /// space between lines, so there lines set tighter than the font's own spacing keep it.
    @ViewBuilder func lineHeight(_ points: Double?, natural: Double) -> some View {
        if #available(macOS 26, *) {
            lineHeight(points.map { .exact(points: $0) })
        } else {
            lineSpacing(points.map { max(0, $0 - natural) } ?? 0)
        }
    }
}

/// A scroll view's soft top edge makes the toolbar's glass over it light or dark from what it sees under it, and on
/// macOS 26 it could keep the old appearance's: switched to Dark in Settings, the search field turned dark, went
/// light again half a second later and stayed so until something scrolled. As the appearance changes, the top edges
/// turn hard for a tenth of a second, which has macOS set them up afresh, in the new appearance. Scroll views with an
/// edge style of their own, like the list's hard one, keep it.
private struct FreshScrollEdges: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHard = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .scrollEdgeEffectStyle(isHard ? .hard : nil, for: .top)
                .onChange(of: colorScheme) {
                    isHard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isHard = false }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Takes drops of `T`. `isOver` hears as a drag comes over and leaves; with `fromOutsideOnly`, drags from Cicero's
    /// own windows don't count, which macOS 15 can't tell.
    @ViewBuilder func drops<T: Transferable>(of type: T.Type, fromOutsideOnly: Bool = false, isOver: ((Bool) -> Void)? = nil,
                                             perform action: @escaping ([T]) -> Void) -> some View {
        if #available(macOS 26, *) {
            let destination = dropDestination(for: type) { items, _ in action(items) }
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
    /// The distance from one line's baseline to the next that the font sets itself.
    var naturalLineHeight: Double {
        CTFontGetAscent(self) + CTFontGetDescent(self) + CTFontGetLeading(self)
    }
}

extension Section where Parent: View, Content: View, Footer: View {
    /// A sidebar section the list can't collapse itself. macOS 15 gives each a chevron of its own, after the header's
    /// + and next to the header's own chevron (see `SectionHeader`).
    @ViewBuilder func notCollapsible() -> some View {
        if #available(macOS 26, *) { self } else { collapsible(false) }
    }
}
