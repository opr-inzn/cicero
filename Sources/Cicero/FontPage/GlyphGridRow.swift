import AppKit
import CiceroCore
import SwiftUI

/// What a cell of the font page's glyph grid draws (see `GlyphGridRow`).
struct GridCell: Hashable {
    enum Content: Hashable {
        /// Text set as `Text` sets it, on the pixel it puts it on, like a character; one wider than the cell is fitted to
        /// it as a glyph is.
        case text(String)
        /// A glyph by its ID, like an alternate or a ligature, centred on its ink and scaled down to fit (see `GlyphDrawing`).
        case glyph(CGGlyph)
    }

    let content: Content
    /// A dot in the accent colour at the top right, for an alternate of the cell before it.
    var isAlternate = false
    /// What VoiceOver reads for it.
    let label: String
}

/// What a row's cells do, by their index in it.
struct GridRowActions {
    /// A click, or VoiceOver's press: opens the cell's popover, with the cell's frame in the row for it to point at
    /// (see `cellPopover`).
    let open: (Int, CGRect?) -> Void
    /// The cell's right-click menu.
    let menu: (Int) -> [GridMenuItem]
    /// The file a cell is dragged out of the page as, made as the drag starts; nil when there's nothing to drag, like a
    /// glyph without an outline.
    let file: (Int) -> URL?
    /// The cell's tooltip, where cells have one.
    var help: ((Int) -> String)?
}

/// An item of a cell's right-click menu.
struct GridMenuItem {
    let title: String
    var isEnabled = true
    let action: () -> Void
}

/// A row of the font page's glyph or ligature cells, drawn as one view. A view for each cell, with its background, dot,
/// menu, drag and click, made scrolling a font with thousands of glyphs stutter: the page's stack built about twenty of
/// them for each row coming into view, some 12 ms for every 40 pt scrolled, where a row like this takes 2. The cells look
/// as they did; AppKit tells which one a click, drag or right-click is on, and gives VoiceOver a button for each.
struct GlyphGridRow: View {
    let cells: [GridCell]
    /// Cells per row: a short last row's cells are as wide as a full one's.
    let columns: Int
    let face: FontFace
    /// The version of the face's file the cells were read from (see `PageContent.generation`).
    let generation: Int
    let weight: Double
    /// Axes moved in the Info panel, by tag.
    let variations: [String: Double]
    /// Room at the sides of each cell's glyph: a ligature's 2 pt.
    var padding: CGFloat = 0
    /// The cell whose popover is open, drawn darker.
    let selected: Int?
    let actions: GridRowActions
    @Environment(\.topRowKeeper) private var keeper

    var body: some View {
        let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize, weight: weight, variations: variations)
        let room = Self.room(for: cells, in: font, columns: columns)
        let drawing = GridRowDrawing(cells: cells, columns: columns, face: face, generation: generation, weight: weight,
                                     variations: variations, padding: padding, selected: selected, room: room)
        drawing.equatable()
            // VoiceOver reads the cells from the events view over it.
            .accessibilityHidden(true)
            // Out past the row, for text reaching past its cell, as `UnclippedText` lets it.
            .padding(EdgeInsets(top: -room.top, leading: -room.leading, bottom: -room.bottom, trailing: -room.trailing))
            .modifier(SquareRow(columns: columns))
            // Where it is in the page, for the page to keep the row at its top in place as the squares change size.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TopRowKeeper.space)) } action: { [keeper, key] in
                keeper?.moved(key, to: $0)
            }
            .onDisappear { [keeper, key] in keeper?.gone(key) }
            .overlay {
                GridRowEvents(labels: cells.map(\.label), columns: columns, actions: actions) { index, size, isDark, scale in
                    // The cell as it's drawn, to drag.
                    let cell = GridRowDrawing(cells: [cells[index]], columns: 1, face: face, generation: generation, weight: weight,
                                              variations: variations, padding: padding, selected: nil, room: EdgeInsets())
                    let renderer = ImageRenderer(content: cell.frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, isDark ? .dark : .light))
                    renderer.scale = scale
                    return renderer.nsImage
                }
            }
    }

    /// Which row this is, among the page's: its cells' labels, which no other row has all of.
    private var key: Int {
        cells.map(\.label).hashValue
    }

    /// The cells' frames across a row `width` wide, as a stack of views shares it out among `columns` cells, `spacing`
    /// apart: on whole pixels, as their backgrounds were drawn, or where the stack put them, which a cell's text was
    /// centred in. Worked out as the stack does, each cell taking what's left over the cells left: a character can sit
    /// exactly between two pixels, where the last bit of the sums decides which one it's drawn on.
    nonisolated static func frames(width: CGFloat, columns: Int, count: Int, scale: CGFloat? = nil) -> [CGRect] {
        let spacing = GlyphsSection.spacing
        func pixel(_ x: CGFloat) -> CGFloat { scale.map { (x * $0).rounded() / $0 } ?? x }
        var left = width - spacing * CGFloat(columns - 1)
        var x: CGFloat = 0
        return (0..<count).map { index in
            let cell = left / CGFloat(columns - index)
            defer {
                left -= cell
                x += cell + spacing
            }
            return CGRect(x: pixel(x), y: 0, width: pixel(x + cell) - pixel(x), height: side(width: width, columns: columns))
        }
    }

    /// How wide a cell is, and so how high, in a row `width` wide of `columns` cells: squares, `spacing` apart. The row
    /// is as many as fit with the sidebar shown and the Info panel shut (see `GlyphColumnsReader`), so hiding the sidebar
    /// or opening the panel makes them bigger or smaller, and their glyphs with them (`zoom`), as the browser's grid does
    /// its tiles, rather than moving glyphs to the next row.
    nonisolated static func side(width: CGFloat, columns: Int) -> CGFloat {
        max(1, (width - GlyphsSection.spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// How much bigger than at `GlyphsSection.cell` a square this wide draws its glyph.
    nonisolated static func zoom(side: CGFloat) -> CGFloat {
        side / GlyphsSection.cell
    }

    /// The most a row's glyphs are zoomed, as far as how much room their text needs above and below goes: a page so
    /// narrow that one square fits, with the sidebar then hidden.
    private static let mostZoom: CGFloat = 3

    /// Where `Text` puts its baseline in a cell this tall: its line, the font's ascent and descent to the nearest point
    /// and no leading, in the middle, on a whole pixel.
    nonisolated static func baseline(in height: CGFloat, font: CTFont, scale: CGFloat = 1) -> CGFloat {
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        return ((height - ascent - descent) / 2 * scale).rounded() / scale + ascent
    }

    /// How far past the row its text may be drawn: above and below, as far as the font's glyphs reach past its line,
    /// and at least half its size, as `UnclippedText` lets text go; at the sides, into the page's margin. None for a row
    /// of glyphs, which fit their cells.
    /// Worked out at the squares' resting size, as `font` is, and made room for at the most they're zoomed (`mostZoom`),
    /// so it's the same whatever the row's width: the row doesn't know it until it's laid out.
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

/// A row of squares: as high as its cells are wide (see `GlyphGridRow.side`).
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
    /// The popover of a row's cell, open while there's a `column`. Pointed at the clicked cell's frame in the row, `cell`,
    /// it has its arrow at the cell's top when it opens above, at its bottom when below, so it leaves the row clear for
    /// clicking the cells beside it. Pointed at the cell's bottom middle, as it still is for VoiceOver's press, which
    /// gives no frame, one opening above covered the cell and the row up to it. The frame comes with the click: a view
    /// over each row measuring it (a GeometryReader) left rows in the middle of the page undrawn on macOS 15.
    func cellPopover<Content: View>(column: Int?, columns: Int, cell: CGRect?, close: @escaping () -> Void,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        let anchor: PopoverAttachmentAnchor = cell.map { .rect(.rect($0)) }
            ?? .point(UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1))
        return popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { close() } }), attachmentAnchor: anchor,
                       content: content)
    }
}

/// A row's cells, drawn again only when they or the open popover change, or when they're read from a new version of
/// the file, even as the ones they were.
private struct GridRowDrawing: View, Equatable {
    let cells: [GridCell]
    let columns: Int
    let face: FontFace
    let generation: Int
    let weight: Double
    let variations: [String: Double]
    let padding: CGFloat
    let selected: Int?
    /// The room around the row, which its frame takes in.
    let room: EdgeInsets

    /// A cell's, as `background(_:in:)` had it.
    private static let background: RoundedRectangle = .rect(cornerRadius: 6)

    var body: some View {
        Canvas { context, size in
            let width = size.width - room.leading - room.trailing
            let side = GlyphGridRow.side(width: width, columns: columns)
            // At the size the square is zoomed to: a CoreText font at that size, not the resting one scaled, for glyphs
            // hinted and placed on pixels as text at that size is.
            let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize * GlyphGridRow.zoom(side: side), weight: weight,
                                              variations: variations)
            // Glyphs by ID read from the file before it changed would be the new version's glyphs with those IDs; the
            // cells stay empty until the page has read it again. Characters are drawn by character, which stays right.
            let isCurrent = generation == FontLoader.shared.generation(of: face.path)
            let scale = context.environment.displayScale
            let frames = GlyphGridRow.frames(width: width, columns: columns, count: cells.count, scale: scale)
            let unrounded = GlyphGridRow.frames(width: width, columns: columns, count: cells.count)
            let color = Color.ink.resolve(in: context.environment).cgColor
            let baseline = GlyphGridRow.baseline(in: side, font: font, scale: scale)
            // A cell at a time, each over the one before, as when they were views of their own.
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

/// Glyphs and text drawn into a context with its origin at the top left, for the glyph grid and `GlyphImage`. Drawn as
/// text is, not filled from their outlines, which came out a quarter lighter than characters set next to them, as macOS
/// thickens text a little when it draws it.
enum GlyphDrawing {
    /// A glyph centred on its ink and on the font's ascender and descender, so glyphs side by side share a baseline,
    /// and scaled down when it's wider than `rect`.
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
        CTFontDrawGlyphs(font, &glyph, &position, 1, context)
        context.restoreGState()
    }

    /// Text where `Text` put it in a cell `rect` was the frame of, on `baseline`: as wide as its advance, to the pixel
    /// above, in the middle, on a whole pixel, reaching into the cells beside it where its ink does, like a swash. Or,
    /// where its advance is wider than the cell, like a long Arabic ligature's, fitted to it as a glyph is.
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

    /// Room at the sides of a fitted glyph.
    private static let margin: CGFloat = 6

    /// Where ink with these bounds has its baseline's start in `rect`, and at what scale: in the middle of its width,
    /// with the font's ascent and descent, or the ink where it reaches further, in the middle of its height.
    private static func fit(_ bounds: CGRect, font: CTFont, in rect: CGRect) -> (origin: CGPoint, scale: CGFloat) {
        let ascent = max(CTFontGetAscent(font), bounds.maxY), descent = max(CTFontGetDescent(font), -bounds.minY)
        let scale = min(1, (rect.width - margin) / max(bounds.width, 1), rect.height / max(ascent + descent, 1))
        return (CGPoint(x: rect.minX + (rect.width - bounds.width * scale) / 2 - bounds.minX * scale,
                        y: rect.minY + (rect.height + (ascent - descent) * scale) / 2), scale)
    }
}

/// Clicks, drags, right-clicks, tooltips and VoiceOver on a row's cells. A view per row, which SwiftUI's gestures and
/// menus can't tell the cells of apart, so AppKit's events, which say where they are.
private struct GridRowEvents: NSViewRepresentable {
    /// What VoiceOver reads for each cell.
    let labels: [String]
    let columns: Int
    let actions: GridRowActions
    /// A cell, as it looks, at its size, in dark or light, at a scale.
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

    /// What the button going down started.
    private enum Press {
        /// A click on a cell, where it went down, until the pointer moves.
        case cell(Int, CGPoint)
        /// A drag, or a click that moved too far to be one.
        case moved
        /// A click between cells, which the page takes.
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

    /// A button for each cell, made when VoiceOver or another client first asks, and kept until the cells change. They
    /// were SwiftUI buttons in the row's `accessibilityRepresentation`, some 600 SwiftUI elements a row, built for every
    /// row the page's lazy stack had made each time a client read the page: Arial Unicode MS went past 1.3 GB.
    private var cellElements: [GridCellElement]?

    private var elements: [GridCellElement] {
        if let cellElements { return cellElements }
        let made = labels.indices.map { GridCellElement(row: self, index: $0, label: labels[$0]) }
        cellElements = made
        return made
    }

    /// The row itself isn't one: its cells are read as the page's, as the buttons were.
    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? { elements }

    // AppKit asks on the main thread, as for the rest.
    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        MainActor.assumeIsolated { element(at: point) } ?? super.accessibilityHitTest(point)
    }

    /// The cell at a point on the screen.
    private func element(at point: NSPoint) -> GridCellElement? {
        guard let window, let index = index(at: convert(window.convertPoint(fromScreen: point), from: nil)) else { return nil }
        return elements[index]
    }

    /// A cell's frame on the screen; none once it's gone.
    fileprivate func screenFrame(of index: Int) -> CGRect {
        let frames = frames
        guard let window, frames.indices.contains(index) else { return .zero }
        return window.convertToScreen(convert(frames[index], to: nil))
    }

    /// VoiceOver's press, as a click: the popover points at the cell.
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

    /// The cell at a point in the view; none in the gaps between cells.
    private func index(at point: CGPoint) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    private func point(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// A click on a cell counts in a window in the background too, as a tap on a SwiftUI view does.
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

    /// Out of the page as an SVG file, or into a design app as a vector, once the pointer moves 3 pt, as SwiftUI starts a
    /// drag; the cell's picture goes with the pointer from where the cell is.
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
            // The item holds on to its action: a target alone it doesn't.
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

/// A cell of a row, as VoiceOver reads it: a button with the cell's label, where the cell is, which opens its popover.
/// It asks the row for its frame each time, as the row moves with the page. AppKit calls it on the main thread only,
/// where it's made.
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

/// What a menu item runs.
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
