import AppKit
import CiceroCore
import SwiftUI

struct GridCell: Hashable {
    enum Content: Hashable {
        case text(String)
        case glyph(CGGlyph)
    }

    let content: Content
    var isAlternate = false
    let label: String
}

struct GridRowActions {
    let open: (Int, CGRect?) -> Void
    let menu: (Int) -> [GridMenuItem]
    let file: (Int) -> URL?
    var help: ((Int) -> String)?
}

struct GridMenuItem {
    let title: String
    var isEnabled = true
    let action: () -> Void
}

struct GlyphGridRow: View {
    let cells: [GridCell]
    let columns: Int
    let face: FontFace
    let generation: Int
    let weight: Double
    let variations: [String: Double]
    var padding: CGFloat = 0
    let selected: Int?
    let actions: GridRowActions
    @Environment(\.topRowKeeper) private var keeper

    var body: some View {
        let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize, weight: weight, variations: variations)
        let room = Self.room(for: cells, in: font, columns: columns)
        let drawing = GridRowDrawing(cells: cells, columns: columns, face: face, generation: generation, weight: weight,
                                     variations: variations, padding: padding, selected: selected, room: room)
        drawing.equatable()
            .accessibilityHidden(true)
            .padding(EdgeInsets(top: -room.top, leading: -room.leading, bottom: -room.bottom, trailing: -room.trailing))
            .modifier(SquareRow(columns: columns))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TopRowKeeper.space)) } action: { [keeper, key] in
                keeper?.moved(key, to: $0)
            }
            .onDisappear { [keeper, key] in keeper?.gone(key) }
            .overlay {
                GridRowEvents(labels: cells.map(\.label), columns: columns, actions: actions) { index, size, isDark, scale in
                    let cell = GridRowDrawing(cells: [cells[index]], columns: 1, face: face, generation: generation, weight: weight,
                                              variations: variations, padding: padding, selected: nil, room: EdgeInsets())
                    let renderer = ImageRenderer(content: cell.frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, isDark ? .dark : .light))
                    renderer.scale = scale
                    return renderer.nsImage
                }
            }
    }

    private var key: Int {
        cells.map(\.label).hashValue
    }

    nonisolated static func frames(width: CGFloat, columns: Int, count: Int, scale: CGFloat? = nil) -> [CGRect] {
        let spacing = GlyphsSection.spacing
        func pixel(_ x: CGFloat) -> CGFloat { scale.map { (x * $0).rounded() / $0 } ?? x }
        var left = width - spacing * CGFloat(columns - 1)
        var x: CGFloat = 0
        return (0..<count).map { index in
            // As SwiftUI's stack shares out its width, to the last bit: a character can sit exactly between two pixels, where the last bit of the sums decides which one it's drawn on.
            let cell = left / CGFloat(columns - index)
            defer {
                left -= cell
                x += cell + spacing
            }
            return CGRect(x: pixel(x), y: 0, width: pixel(x + cell) - pixel(x), height: side(width: width, columns: columns))
        }
    }

    nonisolated static func side(width: CGFloat, columns: Int) -> CGFloat {
        max(1, (width - GlyphsSection.spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    nonisolated static func zoom(side: CGFloat) -> CGFloat {
        side / GlyphsSection.cell
    }

    private static let mostZoom: CGFloat = 3

    nonisolated static func baseline(in height: CGFloat, font: CTFont, scale: CGFloat = 1) -> CGFloat {
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        return ((height - ascent - descent) / 2 * scale).rounded() / scale + ascent
    }

    private static func room(for cells: [GridCell], in font: CTFont, columns: Int) -> EdgeInsets {
        guard cells.contains(where: { if case .text = $0.content { true } else { false } }) else { return EdgeInsets() }
        let box = CTFontGetBoundingBox(font)
        let half = CTFontGetSize(font) / 2
        let baseline = baseline(in: GlyphsSection.cell, font: font)
        let above = max(box.maxY, CTFontGetAscent(font) + half) - baseline
        let below = baseline + max(-box.minY, CTFontGetDescent(font) + half) - GlyphsSection.cell
        return EdgeInsets(top: max(0, (above * mostZoom).rounded(.up)), leading: GlyphsSection.inset,
                          bottom: max(0, (below * mostZoom).rounded(.up)), trailing: GlyphsSection.inset)
    }
}

private struct SquareRow: ViewModifier {
    let columns: Int

    func body(content: Content) -> some View {
        SquareRowLayout(columns: columns) { content }
    }
}

private struct SquareRowLayout: Layout {
    let columns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let resting = GlyphsSection.cell * CGFloat(columns) + GlyphsSection.spacing * CGFloat(columns - 1)
        let width = proposal.width ?? resting
        return CGSize(width: width, height: GlyphGridRow.side(width: width, columns: columns))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

extension View {
    func cellPopover<Content: View>(column: Int?, columns: Int, cell: CGRect?, close: @escaping () -> Void,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        // The cell's frame comes with the click: a GeometryReader over each row to measure it left rows in the middle of the page undrawn on macOS 15.
        let anchor: PopoverAttachmentAnchor = cell.map { .rect(.rect($0)) }
            ?? .point(UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1))
        return popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { close() } }), attachmentAnchor: anchor,
                       content: content)
    }
}

private struct GridRowDrawing: View, Equatable {
    let cells: [GridCell]
    let columns: Int
    let face: FontFace
    let generation: Int
    let weight: Double
    let variations: [String: Double]
    let padding: CGFloat
    let selected: Int?
    let room: EdgeInsets

    private static let background: RoundedRectangle = .rect(cornerRadius: 6)

    var body: some View {
        Canvas { context, size in
            let width = size.width - room.leading - room.trailing
            let side = GlyphGridRow.side(width: width, columns: columns)
            let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize * GlyphGridRow.zoom(side: side), weight: weight,
                                              variations: variations)
            // Glyphs by ID read from the file before it changed would be the new version's glyphs with those IDs; characters are drawn by character, which stays right.
            let isCurrent = generation == FontLoader.shared.generation(of: face.path)
            let scale = context.environment.displayScale
            let frames = GlyphGridRow.frames(width: width, columns: columns, count: cells.count, scale: scale)
            let unrounded = GlyphGridRow.frames(width: width, columns: columns, count: cells.count)
            let color = Color.ink.resolve(in: context.environment).cgColor
            let baseline = GlyphGridRow.baseline(in: side, font: font, scale: scale)
            for (index, cell) in cells.enumerated() {
                let frame = frames[index].offsetBy(dx: room.leading, dy: room.top)
                context.fill(Self.background.path(in: frame),
                             with: .style(.quaternary.opacity(index == selected ? 0.9 : 0.35)))
                context.withCGContext { cg in
                    switch cell.content {
                    case .text(let text):
                        GlyphDrawing.draw(text, font: font, in: unrounded[index].offsetBy(dx: room.leading, dy: room.top),
                                          baseline: frame.minY + baseline, scale: scale, color: color, into: cg)
                    case .glyph(let glyph):
                        guard isCurrent else { break }
                        GlyphDrawing.draw(glyph, font: font, in: frame.insetBy(dx: padding, dy: 0), color: color, into: cg)
                    }
                }
                if cell.isAlternate {
                    context.fill(Circle().path(in: CGRect(x: frame.maxX - 11, y: frame.minY + 5, width: 6, height: 6)), with: .color(.accentColor))
                }
            }
        }
    }
}

enum GlyphDrawing {
    static func draw(_ glyph: CGGlyph, font: CTFont, in rect: CGRect, color: CGColor, into context: CGContext) {
        var glyph = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &bounds, 1)
        guard !bounds.isEmpty else { return }
        let (origin, scale) = fit(bounds, font: font, in: rect)
        context.saveGState()
        context.setFillColor(color)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: -scale)
        var position = CGPoint.zero
        // Drawn as text, not filled from the outline, which came out lighter than characters beside it, as macOS thickens text a little when it draws it.
        CTFontDrawGlyphs(font, &glyph, &position, 1, context)
        context.restoreGState()
    }

    static func draw(_ text: String, font: CTFont, in rect: CGRect, baseline: CGFloat, scale: CGFloat, color: CGColor,
                     into context: CGContext) {
        let line = TextLine(text, font: font, kerning: 0).line
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let width = (advance * scale).rounded(.up) / scale
        var fitted = (origin: CGPoint(x: ((rect.minX + (rect.width - width) / 2) * scale).rounded() / scale, y: baseline),
                      scale: CGFloat(1))
        if advance > rect.width {
            fitted = fit(CTLineGetBoundsWithOptions(line, .useGlyphPathBounds), font: font, in: rect)
        }
        context.saveGState()
        context.setFillColor(color)
        context.textMatrix = .identity
        context.translateBy(x: fitted.origin.x, y: fitted.origin.y)
        context.scaleBy(x: fitted.scale, y: -fitted.scale)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static let margin: CGFloat = 6

    private static func fit(_ bounds: CGRect, font: CTFont, in rect: CGRect) -> (origin: CGPoint, scale: CGFloat) {
        let ascent = max(CTFontGetAscent(font), bounds.maxY), descent = max(CTFontGetDescent(font), -bounds.minY)
        let scale = min(1, (rect.width - margin) / max(bounds.width, 1), rect.height / max(ascent + descent, 1))
        return (CGPoint(x: rect.minX + (rect.width - bounds.width * scale) / 2 - bounds.minX * scale,
                        y: rect.minY + (rect.height + (ascent - descent) * scale) / 2), scale)
    }
}

private struct GridRowEvents: NSViewRepresentable {
    let labels: [String]
    let columns: Int
    let actions: GridRowActions
    let picture: (Int, CGSize, Bool, CGFloat) -> NSImage?

    func makeNSView(context: Context) -> GridRowEventView {
        GridRowEventView()
    }

    func updateNSView(_ view: GridRowEventView, context: Context) {
        view.update(labels: labels, columns: columns, actions: actions, picture: picture)
    }
}

final class GridRowEventView: NSView, NSDraggingSource, NSViewToolTipOwner {
    private var labels: [String] = []
    private var count: Int { labels.count }
    private var columns = 1
    private var actions: GridRowActions?
    private var picture: ((Int, CGSize, Bool, CGFloat) -> NSImage?)?
    private var press: Press?

    private enum Press {
        case cell(Int, CGPoint)
        case moved
        case passedOn
    }

    override var isFlipped: Bool { true }

    fileprivate func update(labels: [String], columns: Int, actions: GridRowActions, picture: @escaping (Int, CGSize, Bool, CGFloat) -> NSImage?) {
        let hadHelp = self.actions?.help != nil
        if labels != self.labels, cellElements != nil {
            cellElements = nil
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        (self.labels, self.columns, self.actions, self.picture) = (labels, columns, actions, picture)
        if hadHelp || actions.help != nil { updateToolTips() }
    }

    // MARK: - Accessibility

    private var cellElements: [GridCellElement]?

    private var elements: [GridCellElement] {
        if let cellElements { return cellElements }
        let made = labels.indices.map { GridCellElement(row: self, index: $0, label: labels[$0]) }
        cellElements = made
        return made
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? { elements }

    // AppKit asks on the main thread.
    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        MainActor.assumeIsolated { element(at: point) } ?? super.accessibilityHitTest(point)
    }

    private func element(at point: NSPoint) -> GridCellElement? {
        guard let window, let index = index(at: convert(window.convertPoint(fromScreen: point), from: nil)) else { return nil }
        return elements[index]
    }

    fileprivate func screenFrame(of index: Int) -> CGRect {
        let frames = frames
        guard let window, frames.indices.contains(index) else { return .zero }
        return window.convertToScreen(convert(frames[index], to: nil))
    }

    fileprivate func press(_ index: Int) -> Bool {
        let frames = frames
        guard let actions, frames.indices.contains(index) else { return false }
        actions.open(index, frames[index])
        return true
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    private var frames: [CGRect] {
        GlyphGridRow.frames(width: bounds.width, columns: columns, count: count, scale: scale)
    }

    private func index(at point: CGPoint) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    private func point(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        event.map { index(at: point(of: $0)) != nil } ?? false
    }

    override func mouseDown(with event: NSEvent) {
        let point = point(of: event)
        if let index = index(at: point) {
            press = .cell(index, point)
        } else {
            press = .passedOn
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch press {
        case .cell(let index, let start):
            let point = point(of: event)
            guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
            press = .moved
            guard frames.indices.contains(index), let file = actions?.file(index) else { return }
            let frame = frames[index]
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            item.setDraggingFrame(frame, contents: picture?(index, frame.size, isDark, scale))
            beginDraggingSession(with: [item], event: event, source: self)
        case .passedOn:
            super.mouseDragged(with: event)
        case .moved, nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil }
        switch press {
        case .cell(let index, _) where index == self.index(at: point(of: event)):
            actions?.open(index, frames[index])
        case .passedOn:
            super.mouseUp(with: event)
        default:
            break
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = index(at: point(of: event)), let items = actions?.menu(index), !items.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            let action = MenuAction(item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(MenuAction.run), keyEquivalent: "")
            // The item holds on to its represented object, but not to its target.
            menuItem.target = action
            menuItem.representedObject = action
            menuItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if actions?.help != nil { updateToolTips() }
    }

    private func updateToolTips() {
        removeAllToolTips()
        guard actions?.help != nil else { return }
        for frame in frames {
            addToolTip(frame, owner: self, userData: nil)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        index(at: point).flatMap { actions?.help?($0) } ?? ""
    }
}

nonisolated private final class GridCellElement: NSAccessibilityElement, @unchecked Sendable {
    private weak var row: GridRowEventView?
    private let index: Int

    @MainActor
    init(row: GridRowEventView, index: Int, label: String) {
        self.row = row
        self.index = index
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityParent(row)
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityFrame() -> NSRect {
        let (row, index) = (row, index)
        return MainActor.assumeIsolated { row?.screenFrame(of: index) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        let (row, index) = (row, index)
        return MainActor.assumeIsolated { row?.press(index) ?? false }
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
