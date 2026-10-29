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
    /// A grey dot at the top right, for an alternate of the cell before it; grey, as colours stand for tags.
    var isAlternate = false
    /// What VoiceOver reads for it.
    let label: String
}

/// What a row's cells do, by their index in it.
struct GridRowActions {
    /// A click, or VoiceOver's press: opens the cell's popover. A click gives the cell's frame in the row, for the
    /// popover to point at (see `cellPopover`); VoiceOver's press, which doesn't know it, gives none.
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
/// as they did; AppKit tells which one a click, drag or right-click is on, and VoiceOver has a button for each.
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

    var body: some View {
        let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize, weight: weight, variations: variations)
        let room = Self.room(for: cells, in: font)
        let drawing = GridRowDrawing(cells: cells, columns: columns, face: face, generation: generation, weight: weight,
                                     variations: variations, padding: padding, selected: selected, room: room)
        drawing.equatable()
            // Out past the row, for text reaching past its cell, as `UnclippedText` lets it.
            .padding(EdgeInsets(top: -room.top, leading: -room.leading, bottom: -room.bottom, trailing: -room.trailing))
            .frame(height: GlyphsSection.cell)
            .overlay {
                GridRowEvents(count: cells.count, columns: columns, actions: actions) { index, size, isDark, scale in
                    // The cell as it's drawn, to drag.
                    let cell = GridRowDrawing(cells: [cells[index]], columns: 1, face: face, generation: generation, weight: weight,
                                              variations: variations, padding: padding, selected: nil, room: EdgeInsets())
                    let renderer = ImageRenderer(content: cell.frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, isDark ? .dark : .light))
                    renderer.scale = scale
                    return renderer.nsImage
                }
            }
            .accessibilityRepresentation {
                HStack(spacing: GlyphsSection.spacing) {
                    ForEach(cells.indices, id: \.self) { index in
                        Button(cells[index].label) { actions.open(index, nil) }
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(cells.count..<max(columns, cells.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
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
            return CGRect(x: pixel(x), y: 0, width: pixel(x + cell) - pixel(x), height: GlyphsSection.cell)
        }
    }

    /// Where `Text` puts its baseline in a cell this tall: its line, the font's ascent and descent to the nearest point
    /// and no leading, in the middle, on a whole pixel.
    nonisolated static func baseline(in height: CGFloat, font: CTFont, scale: CGFloat = 1) -> CGFloat {
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        return ((height - ascent - descent) / 2 * scale).rounded() / scale + ascent
    }

    /// How far past the row its text may be drawn: above and below, as far as the font's glyphs reach past its line,
    /// and at least half its size, as `UnclippedText` lets text go; at the sides, into the page's margin. None for a row
    /// of glyphs, which fit their cells.
    private static func room(for cells: [GridCell], in font: CTFont) -> EdgeInsets {
        guard cells.contains(where: { if case .text = $0.content { true } else { false } }) else { return EdgeInsets() }
        let box = CTFontGetBoundingBox(font)
        let half = CTFontGetSize(font) / 2
        let baseline = baseline(in: GlyphsSection.cell, font: font)
        let above = max(box.maxY, CTFontGetAscent(font) + half) - baseline
        let below = baseline + max(-box.minY, CTFontGetDescent(font) + half) - GlyphsSection.cell
        return EdgeInsets(top: max(0, above.rounded(.up)), leading: GlyphsSection.inset,
                          bottom: max(0, below.rounded(.up)), trailing: GlyphsSection.inset)
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
            let font = FontLoader.shared.font(face, size: GlyphsSection.glyphSize, weight: weight, variations: variations)
            // Glyphs by ID read from the file before it changed would be the new version's glyphs with those IDs; the
            // cells stay empty until the page has read it again. Characters are drawn by character, which stays right.
            let isCurrent = generation == FontLoader.shared.generation(of: face.path)
            let scale = context.environment.displayScale
            let width = size.width - room.leading - room.trailing
            let frames = GlyphGridRow.frames(width: width, columns: columns, count: cells.count, scale: scale)
            let unrounded = GlyphGridRow.frames(width: width, columns: columns, count: cells.count)
            let color = Color.ink.resolve(in: context.environment).cgColor
            let baseline = GlyphGridRow.baseline(in: GlyphsSection.cell, font: font, scale: scale)
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
                    context.fill(Circle().path(in: CGRect(x: frame.maxX - 11, y: frame.minY + 5, width: 6, height: 6)), with: .style(.secondary))
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

/// Clicks, drags, right-clicks and tooltips on a row's cells. A view per row, which SwiftUI's gestures and menus can't
/// tell the cells of apart, so AppKit's events, which say where they are.
private struct GridRowEvents: NSViewRepresentable {
    let count: Int
    let columns: Int
    let actions: GridRowActions
    /// A cell, as it looks, at its size, in dark or light, at a scale.
    let picture: (Int, CGSize, Bool, CGFloat) -> NSImage?

    func makeNSView(context: Context) -> GridRowEventView {
        GridRowEventView()
    }

    func updateNSView(_ view: GridRowEventView, context: Context) {
        view.update(count: count, columns: columns, actions: actions, picture: picture)
    }
}

final class GridRowEventView: NSView, NSDraggingSource, NSViewToolTipOwner {
    private var count = 0
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

    fileprivate func update(count: Int, columns: Int, actions: GridRowActions, picture: @escaping (Int, CGSize, Bool, CGFloat) -> NSImage?) {
        let hadHelp = self.actions?.help != nil
        (self.count, self.columns, self.actions, self.picture) = (count, columns, actions, picture)
        if hadHelp || actions.help != nil { updateToolTips() }
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    private var frames: [CGRect] {
        GlyphGridRow.frames(width: bounds.width, columns: columns, count: count, scale: scale)
    }

    /// The cell at a point in the view; none in the gaps between cells.
    func index(at point: CGPoint) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    private func point(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// A click on a cell counts in a window in the background too, as a cell's tap did when it was a view of its own.
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
            guard let file = actions?.file(index) else { return }
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
