import AppKit
import SwiftUI

/// The font page's editable sample: a text view of its own rather than SwiftUI's TextEditor, which cuts off
/// whatever reaches past the font's ascent and descent (descenders lower than the font says, swashes), and
/// past each line when the lines are closer than the font is tall. Its lines draw every glyph wherever it
/// reaches. It fills the room the page gives it, an invisible copy of the text's, and keeps `overhang` above
/// and below the lines for glyphs reaching past them. A right-click shows Cut, Copy and Paste, then `menu`.
struct SampleEditor<MenuContent: View>: NSViewRepresentable {
    @Binding var text: String
    let font: CTFont
    let kerning: Double
    let lineHeight: Double
    let alignment: NSTextAlignment
    let overhang: CGFloat
    @ViewBuilder let menu: () -> MenuContent

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextView {
        let view = SampleTextView(usingTextLayoutManager: true)
        view.textLayoutManager?.delegate = context.coordinator
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        // The page sizes it; it neither grows by itself nor scrolls.
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.string = text
        update(view, context: context)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.text = $text
        if view.string != text { view.string = text }
        update(view, context: context)
    }

    /// Made at each right-click, so its checkmarks are up to date.
    private func setMenu(of view: NSTextView) {
        (view as? SampleTextView)?.makeMenu = { [menu] in
            NSHostingMenu(rootView: SampleMenu(view: view, content: menu()))
        }
    }

    /// Sets the font, spacing and alignment when they change, not on every keystroke, which would upset typing
    /// with an input method.
    private func update(_ view: NSTextView, context: Context) {
        setMenu(of: view)
        view.textContainerInset = NSSize(width: 0, height: overhang)
        let style = Style(font: font, kerning: kerning, lineHeight: lineHeight, alignment: alignment)
        guard style != context.coordinator.style || view.textStorage?.length != context.coordinator.styledLength else { return }
        context.coordinator.style = style
        let attributes = style.attributes
        view.typingAttributes = attributes
        view.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        if let storage = view.textStorage {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            context.coordinator.styledLength = storage.length
        }
    }

    struct Style: Equatable {
        let font: CTFont
        let kerning: Double
        let lineHeight: Double
        let alignment: NSTextAlignment

        var attributes: [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.alignment = alignment
            return [.font: font as NSFont, .kern: kerning, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        }

        static func == (a: Style, b: Style) -> Bool {
            CFEqual(a.font, b.font) && a.kerning == b.kerning && a.lineHeight == b.lineHeight && a.alignment == b.alignment
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextLayoutManagerDelegate {
        var text: Binding<String>
        var style: Style?
        /// The text's length when the style was last set: text pasted since may have brought its own.
        var styledLength = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            styledLength = view.textStorage?.length ?? 0
            text.wrappedValue = view.string
        }

        func textLayoutManager(_ manager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                               in element: NSTextElement) -> NSTextLayoutFragment {
            UnclippedFragment(textElement: element, range: element.elementRange)
        }
    }
}

/// Esc goes back from the font page, as everywhere else on it, rather than offering completions. A right-click
/// shows the page's menu, not the text view's.
private final class SampleTextView: NSTextView {
    var makeMenu: (() -> NSMenu)?
    /// The menu last shown, kept until the next: its items act once it has closed.
    private var shownMenu: NSMenu?

    override func cancelOperation(_ sender: Any?) {
        nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let makeMenu else { return super.menu(for: event) }
        shownMenu = makeMenu()
        return shownMenu
    }
}

/// The sample's right-click menu: editing the text, then what the page gives it.
private struct SampleMenu<Content: View>: View {
    weak var view: NSTextView?
    let content: Content

    var body: some View {
        let hasSelection = (view?.selectedRange().length ?? 0) > 0
        Button("Cut", systemImage: "scissors") { view?.cut(nil) }
            .disabled(!hasSelection)
        Button("Copy", systemImage: "doc.on.doc") { view?.copy(nil) }
            .disabled(!hasSelection)
        Button("Paste", systemImage: "doc.on.clipboard") { view?.paste(nil) }
        Divider()
        content
    }
}

/// A paragraph of the sample whose glyphs draw however far past their lines they reach. TextKit draws each
/// paragraph within its rendering surface, which is only as tall as the font's ascent and descent.
nonisolated private final class UnclippedFragment: NSTextLayoutFragment {
    override var renderingSurfaceBounds: CGRect {
        textLineFragments.reduce(super.renderingSurfaceBounds) { bounds, line in
            let string = line.attributedString.attributedSubstring(from: line.characterRange)
            let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(string), .useGlyphPathBounds)
            guard !ink.isNull, !ink.isEmpty else { return bounds }
            // From the line's baseline, y up, to the paragraph's coordinates, y down.
            let x = line.typographicBounds.minX + line.glyphOrigin.x
            let baseline = line.typographicBounds.minY + line.glyphOrigin.y
            let glyphs = CGRect(x: x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            return bounds.union(glyphs.insetBy(dx: -2, dy: -2))
        }
    }
}
