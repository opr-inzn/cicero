import AppKit
import SwiftUI

final class SidebarFit {
    private var slack: [String: CGFloat] = [:]

    var narrowing: CGFloat? { slack.values.min() }

    func set(_ key: String, room: CGFloat?, title: CGFloat?) {
        if let room, let title { slack[key] = room - title } else { slack[key] = nil }
    }
}

extension View {
    func sidebarTitle(_ title: String, key: String, fit: SidebarFit) -> some View {
        modifier(SidebarTitle(title: title, key: key, fit: fit))
    }
}

private struct SidebarTitle: ViewModifier {
    let title: String
    let key: String
    let fit: SidebarFit
    @State private var widths = Widths()

    final class Widths {
        var room: CGFloat?
        var title: CGFloat?
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                widths.room = $0
                fit.set(key, room: widths.room, title: widths.title)
            }
            // The whole title, in the same font, measured where it can't be seen.
            .background(alignment: .leading) {
                Text(title)
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        widths.title = $0
                        fit.set(key, room: widths.room, title: widths.title)
                    }
            }
            .onDisappear { fit.set(key, room: nil, title: nil) }
    }
}

enum SidebarSnap {
    static let distance: CGFloat = 10
    private typealias Constrain = @convention(c) (AnyObject, Selector, NSSplitView, CGFloat, Int) -> CGFloat
    private static var snapping: Set<ObjectIdentifier> = []
    private static let fitKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func install(on splitView: NSSplitView, fit: SidebarFit) {
        objc_setAssociatedObject(splitView, fitKey, fit, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard let delegate = splitView.delegate, let type = object_getClass(delegate),
              !snapping.contains(ObjectIdentifier(type)) else { return }
        let selector = #selector(NSSplitViewDelegate.splitView(_:constrainSplitPosition:ofSubviewAt:))
        // The class's own, or its superclass's, which the one added to the class hands on to.
        let previous = class_getInstanceMethod(type, selector).map { unsafeBitCast(method_getImplementation($0), to: Constrain.self) }
        let answer: @convention(block) (AnyObject, NSSplitView, CGFloat, Int) -> CGFloat = { delegate, splitView, proposed, index in
            let position = previous?(delegate, selector, splitView, proposed, index) ?? proposed
            // Dragged far enough left to hide the sidebar: left to AppKit, which hides it.
            guard index == 0, let sidebar = splitView.arrangedSubviews.first,
                  position >= sidebar.frame.minX + SidebarWidth.hiding else { return position }
            var snapped = position
            if let fit = objc_getAssociatedObject(splitView, fitKey) as? SidebarFit, let narrowing = fit.narrowing {
                let whole = sidebar.frame.maxX - narrowing
                if abs(position - whole) < distance { snapped = whole }
            }
            // Within the sidebar's widths: AppKit's own limits don't hold a drag.
            return min(max(snapped, sidebar.frame.minX + SidebarWidth.minimum), sidebar.frame.minX + SidebarWidth.maximum)
        }
        let implementation = imp_implementationWithBlock(answer)
        // CGFloat, the split view, CGFloat, NSInteger: what NSSplitViewDelegate's method takes and returns.
        if !class_addMethod(type, selector, implementation, "d@:@dq"),
           let method = class_getInstanceMethod(type, selector) {
            method_setImplementation(method, implementation)
        }
        snapping.insert(ObjectIdentifier(type))
        // A split view asks its delegate only what it answered when it was set.
        splitView.delegate = delegate
    }
}

enum SidebarWidth {
    static let minimum: CGFloat = 210
    static let ideal: CGFloat = 240
    static let maximum: CGFloat = 340
    // Under about 75 pt, where AppKit hides the sidebar; above that AppKit leaves it at its own 148 pt, so a drag from here up stops at `minimum` instead.
    static let hiding: CGFloat = 60

    static func keep(in splitView: NSSplitView) {
        guard let controller = splitView.delegate as? NSSplitViewController,
              let item = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) else { return }
        item.minimumThickness = minimum
        item.maximumThickness = maximum
        // Once the window has laid out its columns.
        DispatchQueue.main.async {
            // A window opened without a saved width can give the sidebar less than its minimum, cutting its titles short, and save that.
            guard !item.isCollapsed, let sidebar = splitView.arrangedSubviews.first, sidebar.frame.width < minimum else { return }
            splitView.setPosition(ideal, ofDividerAt: 0)
        }
    }
}

struct SidebarSnapReader: NSViewRepresentable {
    let fit: SidebarFit

    func makeNSView(context: Context) -> ReaderView { ReaderView(fit: fit) }
    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        let fit: SidebarFit

        init(fit: SidebarFit) {
            self.fit = fit
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSSplitView) { view = current.superview }
            if let splitView = view as? NSSplitView {
                SidebarSnap.install(on: splitView, fit: fit)
                SidebarWidth.keep(in: splitView)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
