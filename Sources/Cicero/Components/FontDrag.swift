import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct FontDrag: Codable {
    var families: [String]
    var style: String?

    init(families: [String]) {
        self.families = families
    }

    init(family: String, style: String) {
        families = [family]
        self.style = style
    }
}

extension UTType {
    nonisolated static let ciceroFontStyle = UTType(exportedAs: "com.maximilianinzinger.cicero.font-style")
}

struct FamilyDragPreview: View {
    let family: Family

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            FontText(text: "Aa", face: family.regular.face, size: 16, weight: family.regular.face.styleWeight)
            Text(family.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

final class FontDragSource: NSObject, NSDraggingSource {
    struct Entry {
        var drag: FontDrag
        var paths: () -> [String]
        var preview: () -> AnyView
    }

    static let shared = FontDragSource()
    private var started: CGPoint?
    private var draggedPaths: Set<String> = []

    func isDragging(_ url: URL) -> Bool {
        draggedPaths.contains(url.path)
    }

    func begin(_ entries: [Entry], from start: CGPoint) {
        guard start != started, !entries.isEmpty, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let window = event.window, let view = window.contentView else { return }
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let point = view.convert(event.locationInWindow, from: nil)
        var top = point.y
        var items: [NSDraggingItem] = []
        var dragged = Set<String>()
        for (index, entry) in entries.enumerated() {
            guard let data = try? JSONEncoder().encode(entry.drag) else { continue }
            let paths = entry.paths().filter { dragged.insert($0).inserted }
            let first = NSPasteboardItem()
            first.setData(data, forType: NSPasteboard.PasteboardType(UTType.ciceroFontStyle.identifier))
            let writers = [first] + paths.dropFirst().map { _ in NSPasteboardItem() }
            for (writer, path) in zip(writers, paths) {
                writer.setString(URL(fileURLWithPath: path, isDirectory: false).absoluteString, forType: .fileURL)
            }
            for (number, writer) in writers.enumerated() {
                let dragging = NSDraggingItem(pasteboardWriter: writer)
                if index < 10, number == 0 {
                    let renderer = ImageRenderer(content: entry.preview().environment(\.colorScheme, isDark ? .dark : .light))
                    renderer.scale = window.backingScaleFactor
                    guard let image = renderer.nsImage else { continue }
                    if index == 0 { top += image.size.height / 2 }
                    dragging.setDraggingFrame(NSRect(x: point.x - 24, y: top - image.size.height, width: image.size.width, height: image.size.height), contents: image)
                    top -= image.size.height + 4
                } else {
                    dragging.setDraggingFrame(NSRect(x: point.x - 24, y: top, width: 1, height: 1), contents: nil)
                }
                items.append(dragging)
            }
        }
        guard !items.isEmpty else { return }
        started = start
        draggedPaths = dragged
        let session = view.beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = items.count > 1 ? .pile : .none
    }

    // Copy only, also to Finder: a move would take the font files out of the library, and the Trash takes no copy.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        started = nil
        draggedPaths = []
    }

    static func paths(of family: Family, including: @escaping (LibraryFace) -> Bool = { _ in true }) -> [String] {
        FontExportPlan(families: [family]) { including($1) }.items.flatMap(\.paths)
    }
}

extension View {
    func styleDrag(_ face: LibraryFace, of family: Family, @ViewBuilder preview: @escaping () -> some View) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
            let entry = FontDragSource.Entry(drag: FontDrag(family: family.id, style: face.face.postScriptName),
                                             paths: { FontDragSource.paths(of: family) { $0.id == face.id } }, preview: { AnyView(preview()) })
            FontDragSource.shared.begin([entry], from: value.startLocation)
        })
    }

    func familyDrag(_ families: @escaping () -> [Family]) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
            let entries = families().map { family in
                FontDragSource.Entry(drag: FontDrag(families: [family.id]), paths: { FontDragSource.paths(of: family) },
                                     preview: { AnyView(FamilyDragPreview(family: family)) })
            }
            FontDragSource.shared.begin(entries, from: value.startLocation)
        })
    }
}

struct FontDropTarget: NSViewRepresentable {
    var isOver: ((Bool) -> Void)?
    var files: FileDrops?
    var perform: (([FontDrag]) -> Void)?

    init(isOver: ((Bool) -> Void)? = nil, files: FileDrops? = nil, perform: @escaping ([FontDrag]) -> Void) {
        self.isOver = isOver
        self.files = files
        self.perform = perform
    }

    init(files: FileDrops) {
        self.files = files
    }

    struct FileDrops {
        var isOver: (Bool) -> Void
        var perform: ([URL]) -> Void
    }

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registerForDraggedTypes(TargetView.types)
        return view
    }

    func updateNSView(_ view: TargetView, context: Context) {
        view.isOver = isOver
        view.files = files
        view.perform = perform
    }

    final class TargetView: NSView {
        static let types = [NSPasteboard.PasteboardType(UTType.ciceroFontStyle.identifier), .string, .fileURL]
        var isOver: ((Bool) -> Void)?
        var files: FileDrops?
        var perform: (([FontDrag]) -> Void)?

        // Clicks go to the view in front, and drags still find this one: AppKit finds where a drag is over by the types registered here.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(for: sender) }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { isOver?(false); files?.isOver(false) }

        override func draggingEnded(_ sender: any NSDraggingInfo) { isOver?(false); files?.isOver(false) }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            isOver?(false)
            if let files, sender.draggingSource == nil, case let urls = Self.fileURLs(on: sender.draggingPasteboard), !urls.isEmpty {
                files.isOver(false)
                files.perform(urls)
                return true
            }
            let drags = Self.drags(on: sender.draggingPasteboard)
            guard let perform, !drags.isEmpty else { return false }
            perform(drags)
            return true
        }

        private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
            if let files, sender.draggingSource == nil, !Self.fileURLs(on: sender.draggingPasteboard).isEmpty {
                isOver?(false)
                files.isOver(true)
                sender.draggingFormation = .pile
                return .copy
            }
            let takes = perform != nil && sender.draggingPasteboard.availableType(from: Array(Self.types.prefix(2))) != nil
            isOver?(takes)
            if takes, case let count = (sender.draggingPasteboard.pasteboardItems ?? []).count(where: { $0.availableType(from: [Self.types[0]]) != nil }), count > 0 {
                sender.numberOfValidItemsForDrop = count
            }
            return takes ? .copy : []
        }

        static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
            pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
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
