import AppKit
import SwiftUI

enum PresentationWindow {
    static let compare = "compare"
    static let slideshow = "slideshow"
}

/// Compare and Slideshow items for the Fonts menu.
struct PresentationCommands: View {
    let library: LibraryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let selection = library.selectedFamilies
        Button("Compare") {
            library.prepareCompare(selection)
            openWindow(id: PresentationWindow.compare)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(selection.count < 2)
        Button("Slideshow") {
            library.prepareSlideshow(selection)
            openWindow(id: PresentationWindow.slideshow)
        }
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(library.families.isEmpty)
    }
}

/// The same items for a family's right-click menu.
struct PresentationMenuItems: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openWindow) private var openWindow
    let families: [FontFamily]

    var body: some View {
        if families.count > 1 {
            Button("Compare") {
                library.prepareCompare(families)
                openWindow(id: PresentationWindow.compare)
            }
        }
        Button("Slideshow") {
            library.prepareSlideshow(families)
            openWindow(id: PresentationWindow.slideshow)
        }
    }
}

/// Starts a slideshow of the selection, or of the whole list, from the browser's toolbar.
struct SlideshowToolbarButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            library.prepareSlideshow(library.selectedFamilies)
            openWindow(id: PresentationWindow.slideshow)
        } label: {
            Label("Slideshow", systemImage: "play.rectangle")
        }
        .help("Show these fonts one at a time, full screen")
        .disabled(library.families.isEmpty)
    }
}

/// Hands the hosting NSWindow to SwiftUI once the view is on screen.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.configure = configure
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        var configure: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure?(window) }
        }
    }
}
