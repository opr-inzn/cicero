import AppKit
import CiceroCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct FontDrag: Codable, Transferable {
    var families: [String]
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
        ProxyRepresentation(exporting: { $0.families.joined(separator: "\n") },
                            importing: { FontDrag(families: $0.split(whereSeparator: \.isNewline).map(String.init)) })
    }
}

extension UTType {
    nonisolated static let ciceroFontStyle = UTType(exportedAs: "com.maximilianinzinger.cicero.font-style")
}

struct FamilyDragPreview: View {
    let family: Family
    let count: Int

    var body: some View {
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
                Text(count.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.red, in: .capsule)
                    .offset(x: 8, y: -8)
            }
        }
        .padding(10)
    }
}

final class FontDragSource: NSObject, NSDraggingSource {
    static let shared = FontDragSource()
    private var started: CGPoint?

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
    func fontDrag<Preview: View>(_ drag: @escaping () -> FontDrag, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
            FontDragSource.shared.begin(drag(), from: value.startLocation, preview: preview)
        })
    }
}

struct FontDropTarget: NSViewRepresentable {
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

        // Clicks go to the view in front, and drags still find this one: AppKit finds where a drag is over by the types registered here.
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
