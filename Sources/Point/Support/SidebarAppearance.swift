import AppKit
import SwiftUI

/// Forces the sidebar column's AppKit view (including its glass material) into an appearance.
/// The window follows the canvas color, but the sidebar should keep the system's light/dark look.
struct SidebarAppearance: NSViewRepresentable {
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.appearanceName = colorScheme == .dark ? .darkAqua : .aqua
    }

    final class ProbeView: NSView {
        var appearanceName: NSAppearance.Name = .aqua {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            // The sidebar column is the split view's arranged subview containing this probe.
            var view = superview
            while let current = view {
                if let split = current.superview as? NSSplitView, split.arrangedSubviews.contains(current) {
                    current.appearance = NSAppearance(named: appearanceName)
                    return
                }
                view = current.superview
            }
        }
    }
}
