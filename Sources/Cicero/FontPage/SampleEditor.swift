import AppKit
import SwiftUI

/// The font page's editable sample: a text view of its own rather than SwiftUI's TextEditor, which cuts off
/// whatever reaches past the font's ascent and descent (descenders lower than the font says, swashes), and
/// past each line when the lines are closer than the font is tall. Its lines draw every glyph wherever it
/// reaches. It's as tall as its lines at the width the page gives it, and the room above and below them for
/// glyphs reaching past them (`roomAbove`, `roomBelow`); `margin` at either side of the lines is room for glyphs
/// reaching past their ends, as nothing is drawn outside the view. A right-click shows Cut, Copy and Paste, then
/// `menu`. Left empty, it shows `defaultText` again.
struct SampleEditor<MenuContent: View>: NSViewRepresentable {
    @Binding var text: String
    let defaultText: String
    let font: CTFont
    let kerning: Double
    let lineHeight: Double
    let alignment: NSTextAlignment
    let margin: CGFloat
    let roomAbove: CGFloat
    let roomBelow: CGFloat
    @ViewBuilder let menu: () -> MenuContent

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, defaultText: defaultText) }

    func makeNSView(context: Context) -> NSTextView {
        let view = SampleTextView(usingTextLayoutManager: true)
        view.textLayoutManager?.delegate = context.coordinator
        view.delegate = context.coordinator
        view.textStorage?.delegate = context.coordinator
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
        context.coordinator.defaultText = defaultText
        if view.string != text { view.string = text }
        update(view, context: context)
    }

    /// As tall as its lines, laid out at the width it's offered, and the room above and below them. An invisible
    /// SwiftUI copy of the text used to set the height, but it broke some lines elsewhere, so at some sizes the last
    /// line was cut off.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, let manager = view.textLayoutManager, let container = view.textContainer
        else { return nil }
        let lineWidth = width - 2 * margin
        if container.size.width != lineWidth { container.size = NSSize(width: lineWidth, height: .greatestFiniteMagnitude) }
        // The extra line after a final line break, and the one empty text has, count too.
        var bottom: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout, .ensuresExtraLineFragment]) {
            bottom = max(bottom, $0.layoutFragmentFrame.maxY)
            return true
        }
        return CGSize(width: width, height: bottom.rounded(.up) + roomAbove + roomBelow)
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
        view.textContainerInset = NSSize(width: margin, height: 0)
        (view as? SampleTextView)?.roomAbove = roomAbove
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
            var attributes: [NSAttributedString.Key: Any] = [.font: font as NSFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
            // Tracking is a kern added to the font's kerning, but a kern of 0 means no kerning at all, so pairs
            // like Va stood apart. Not tracking, which breaks ligatures apart once it isn't 0.
            if kerning != 0 { attributes[.kern] = kerning }
            return attributes
        }

        static func == (a: Style, b: Style) -> Bool {
            CFEqual(a.font, b.font) && a.kerning == b.kerning && a.lineHeight == b.lineHeight && a.alignment == b.alignment
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSTextLayoutManagerDelegate {
        var text: Binding<String>
        var defaultText: String
        var style: Style?
        /// The text's length when the style was last set: text pasted since may have brought its own.
        var styledLength = 0

        init(text: Binding<String>, defaultText: String) {
            self.text = text
            self.defaultText = defaultText
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            styledLength = view.textStorage?.length ?? 0
        }

        /// Every change to the text, an undone one too, which the text view doesn't tell its delegate about.
        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange,
                         changeInLength: Int) {
            guard editedMask.contains(.editedCharacters), storage.string != text.wrappedValue else { return }
            text.wrappedValue = storage.string
        }

        /// Puts the default text back when the text is left with nothing to see, as a step of its own to undo.
        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let storage = view.textStorage,
                  view.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let all = NSRange(location: 0, length: storage.length)
            view.breakUndoCoalescing()
            guard view.shouldChangeText(in: all, replacementString: defaultText) else { return }
            storage.replaceCharacters(in: all, with: NSAttributedString(string: defaultText, attributes: view.typingAttributes))
            view.didChangeText()
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
    /// Where the lines start: below the room for glyphs reaching above them. Not a container inset, which would
    /// leave as much room below.
    var roomAbove: CGFloat = 0 {
        didSet {
            guard roomAbove != oldValue else { return }
            invalidateTextContainerOrigin()
            needsDisplay = true
        }
    }
    /// The menu last shown, kept until the next: its items act once it has closed.
    private var shownMenu: NSMenu?

    override var textContainerOrigin: NSPoint { NSPoint(x: textContainerInset.width, y: roomAbove) }

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
