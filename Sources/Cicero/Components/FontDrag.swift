import AppKit
import CiceroCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Families, or one style of one, being dragged onto the sidebar. The browser's grid and lists and the Character Toolbox
/// drag every selected family when the one dragged is selected, else just that one; a font page's style rows drag one
/// style, which a set takes on its own.
nonisolated struct FontDrag: Codable, Transferable {
    var families: [String]
    /// The style's PostScript name, of the one family; none for whole families.
    var style: String?

    init(families: [String]) {
        self.families = families
    }

    init(family: String, style: String) {
        families = [family]
        self.style = style
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroFontStyle)
        // Elsewhere it's the families' names, one per line, and names dropped from elsewhere come in the same way.
        ProxyRepresentation(exporting: { $0.families.joined(separator: "\n") },
                            importing: { FontDrag(families: $0.split(whereSeparator: \.isNewline).map(String.init)) })
    }
}

extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroFontStyle = UTType(exportedAs: "com.maximilianinzinger.cicero.font-style")
}

/// What families being dragged look like: "Aa" in the letters of the one under the pointer and its name, small, as the
/// Finder's sidebar shows a file dragged over it, rather than the whole card or row, with how many there are when it's
/// several, as the Finder counts files.
struct FamilyDragPreview: View {
    let family: Family
    let count: Int

    var body: some View {
        // On one baseline, however high or low the family's letters sit in their line.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            FontText(text: "Aa", face: family.regular.face, size: 16, weight: family.regular.face.styleWeight)
            Text(family.name)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text(count, format: .number)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.red, in: .capsule)
                    .offset(x: 8, y: -8)
            }
        }
        // Room for the count, and for letters that reach beyond their line.
        .padding(10)
    }
}

/// Starts dragging families, or a style, with AppKit rather than SwiftUI's `draggable`, so what's dragged is its small
/// preview at the pointer from start to end. `draggable` gives the dragged item the frame of the whole card or row,
/// however small its preview, where the pointer took it, and once it's dropped the preview, shown at the pointer while
/// dragging, slides off to that frame's corner. Drops take it as they take a `FontDrag`.
final class FontDragSource: NSObject, NSDraggingSource {
    static let shared = FontDragSource()
    /// Where the gesture that started the drag under way began, in the window: one drag per gesture, and a drag that
    /// never hears it ended doesn't hold up the next.
    private var started: CGPoint?

    /// Starts the drag from the mouse event being handled, as a drag gesture that began at `start` changes, unless it
    /// has started one already.
    func begin<Preview: View>(_ drag: FontDrag, from start: CGPoint, @ViewBuilder preview: () -> Preview) {
        guard start != started, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let window = event.window, let view = window.contentView, let data = try? JSONEncoder().encode(drag) else { return }
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.ciceroFontStyle.identifier))
        item.setString(drag.families.joined(separator: "\n"), forType: .string)
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(content: preview().environment(\.colorScheme, isDark ? .dark : .light))
        renderer.scale = window.backingScaleFactor
        guard let image = renderer.nsImage else { return }
        // The pointer on the preview's left, where a family's Aa is, halfway down.
        let point = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: point.x - 24, y: point.y - image.size.height / 2, width: image.size.width, height: image.size.height)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(frame, contents: image)
        started = start
        view.beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        started = nil
    }
}

extension View {
    /// Drags `drag` with `FontDragSource` once the pointer moves with the button down.
    func fontDrag<Preview: View>(_ drag: @escaping () -> FontDrag, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
            FontDragSource.shared.begin(drag(), from: value.startLocation, preview: preview)
        })
    }
}

/// Takes families, or a style, dropped on what it's behind, as AppKit takes a drop: the drag ends the moment it's
/// dropped, as in the Finder. SwiftUI's drop destination keeps the dragged label up a third of a second longer.
/// Behind a view, it leaves clicks to it: AppKit finds where a drag is over by the types registered there.
struct FontDropTarget: NSViewRepresentable {
    /// Hears as a drag that can be dropped comes over and leaves.
    var isOver: ((Bool) -> Void)?
    var perform: ([FontDrag]) -> Void

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registerForDraggedTypes(TargetView.types)
        return view
    }

    func updateNSView(_ view: TargetView, context: Context) {
        view.isOver = isOver
        view.perform = perform
    }

    final class TargetView: NSView {
        static let types = [NSPasteboard.PasteboardType(UTType.ciceroFontStyle.identifier), .string]
        var isOver: ((Bool) -> Void)?
        var perform: ([FontDrag]) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { isOver?(false) }

        override func draggingEnded(_ sender: any NSDraggingInfo) { isOver?(false) }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            isOver?(false)
            let drags = Self.drags(on: sender.draggingPasteboard)
            guard !drags.isEmpty else { return false }
            perform(drags)
            return true
        }

        private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
            let takes = sender.draggingPasteboard.availableType(from: Self.types) != nil
            isOver?(takes)
            return takes ? .copy : []
        }

        /// What `FontDragSource` puts on the pasteboard, or names from elsewhere, one per line.
        static func drags(on pasteboard: NSPasteboard) -> [FontDrag] {
            (pasteboard.pasteboardItems ?? []).compactMap { item in
                if let data = item.data(forType: types[0]), let drag = try? JSONDecoder().decode(FontDrag.self, from: data) {
                    return drag
                }
                let names = (item.string(forType: .string) ?? "").split(whereSeparator: \.isNewline).map(String.init)
                return names.isEmpty ? nil : FontDrag(families: names)
            }
        }
    }
}
