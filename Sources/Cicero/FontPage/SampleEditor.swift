import AppKit
import CiceroCore
import SwiftUI

/// The font page's editable sample: a text view of its own rather than SwiftUI's TextEditor, which cuts off
/// whatever reaches past the font's ascent and descent (descenders lower than the font says, swashes), and
/// past each line when the lines are closer than the font is tall. Its lines draw every glyph wherever it
/// reaches. It's as tall as its lines at the width the page gives it, and the room above and below them for
/// glyphs reaching past them (`roomAbove`, `roomBelow`); `margin` at either side of the lines is room for glyphs
/// reaching past their ends, as nothing is drawn outside the view. A right-click shows Cut, Copy and Paste, then
/// `menu`. Left empty, it shows `defaultText` again. Glyphs copied from the page's Glyphs, like an alternate, are
/// drawn as copied where they're pasted (`glyphs`, see `SampleGlyph`), in `face`, a style of `family`. A new `caseChange`
/// converts the selection's case, or the whole text's with nothing selected, as a step to undo.
struct SampleEditor<MenuContent: View>: NSViewRepresentable {
    @Binding var text: String
    @Binding var glyphs: [SampleGlyphRun]
    let defaultText: String
    let family: String
    let face: FontFace
    let font: CTFont
    let kerning: Double
    let lineHeight: Double
    let alignment: NSTextAlignment
    let margin: CGFloat
    let roomAbove: CGFloat
    let roomBelow: CGFloat
    var caseChange: CaseChange?
    @ViewBuilder let menu: () -> MenuContent

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, glyphs: $glyphs, defaultText: defaultText) }

    func makeNSView(context: Context) -> NSTextView {
        // TextKit 2, with a layout manager of its own for the insertion point (see `SampleLayoutManager`).
        let content = NSTextContentStorage()
        let manager = SampleLayoutManager()
        // Lines exactly the Leading apart: TextKit added the font's own line gap below each line on top of it, so
        // 100 % of a font with a gap of 20 % of the em set its lines 120 % apart, and each sat high in its room.
        manager.usesFontLeading = false
        content.addTextLayoutManager(manager)
        manager.textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let view = SampleTextView(frame: .zero, textContainer: manager.textContainer)
        view.content = content
        content.delegate = context.coordinator
        manager.delegate = context.coordinator
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
        context.coordinator.caseChange = caseChange
        update(view, context: context)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.glyphs = $glyphs
        coordinator.defaultText = defaultText
        if view.string != text {
            coordinator.isSettingText = true
            view.string = text
            coordinator.isSettingText = false
            coordinator.markedGlyphs = nil
        }
        update(view, context: context)
        if caseChange != coordinator.caseChange {
            coordinator.caseChange = caseChange
            if let caseChange { (view as? SampleTextView)?.convert(caseChange.conversion, in: font) }
        }
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
    /// with an input method, and marks the pasted glyphs again when the text was set from outside.
    private func update(_ view: NSTextView, context: Context) {
        setMenu(of: view)
        view.textContainerInset = NSSize(width: margin, height: 0)
        (view as? SampleTextView)?.roomAbove = roomAbove
        let coordinator = context.coordinator
        let style = Style(font: font, kerning: kerning, lineHeight: lineHeight, alignment: alignment)
        let glyphStyle = GlyphStyle(family: family, face: face, font: font)
        guard let storage = view.textStorage else { return }
        let restyles = style != coordinator.style || storage.length != coordinator.styledLength
        guard restyles || glyphStyle != coordinator.glyphStyle || glyphs != coordinator.markedGlyphs else { return }
        coordinator.style = style
        coordinator.glyphStyle = glyphStyle
        coordinator.markedGlyphs = glyphs
        if let manager = view.textLayoutManager as? SampleLayoutManager {
            manager.font = font
            manager.raise = style.raise
        }
        let attributes = style.attributes
        view.typingAttributes = attributes
        view.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        // In one edit with the pasted glyphs, which setting the attributes takes off: the text is then drawn again,
        // with the style's glyphs for them.
        coordinator.isSettingText = true
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.addSampleGlyphs(glyphs)
        storage.endEditing()
        coordinator.isSettingText = false
        coordinator.styledLength = storage.length
    }

    /// What the pasted glyphs are drawn in.
    struct GlyphStyle: Equatable {
        let family: String
        let face: FontFace
        let font: CTFont

        static func == (a: GlyphStyle, b: GlyphStyle) -> Bool {
            a.family == b.family && a.face.id == b.face.id && CFEqual(a.font, b.font)
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

        /// How far each line is drawn above where TextKit sets it, the font's descent above the bottom of the line:
        /// half of what the line height adds to the font's height, so it sits in the middle of the line, as on the
        /// web. Below 0 when the lines are closer than the font is tall, which lowers it.
        var raise: CGFloat {
            (lineHeight - CTFontGetAscent(font).rounded() - CTFontGetDescent(font).rounded()) / 2
        }

        static func == (a: Style, b: Style) -> Bool {
            CFEqual(a.font, b.font) && a.kerning == b.kerning && a.lineHeight == b.lineHeight && a.alignment == b.alignment
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSTextLayoutManagerDelegate,
                             NSTextContentStorageDelegate {
        var text: Binding<String>
        var glyphs: Binding<[SampleGlyphRun]>
        var defaultText: String
        var style: Style?
        /// The text's length when the style was last set: text pasted since may have brought its own.
        var styledLength = 0
        var glyphStyle: GlyphStyle? {
            didSet { if glyphStyle != oldValue { shownGlyphs.removeAll() } }
        }
        /// Each pasted glyph's in the style shown, nil for one it doesn't have.
        private var shownGlyphs: [SampleGlyph: CGGlyph?] = [:]
        /// The pasted glyphs as last marked in the text, or as the text last told; nil once it's set from outside.
        var markedGlyphs: [SampleGlyphRun]?
        /// While the text is set from outside, when the glyphs pasted into it aren't marked yet.
        var isSettingText = false
        /// The case change last made, so that each is made once.
        var caseChange: CaseChange?

        init(text: Binding<String>, glyphs: Binding<[SampleGlyphRun]>, defaultText: String) {
            self.text = text
            self.glyphs = glyphs
            self.defaultText = defaultText
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            styledLength = view.textStorage?.length ?? 0
        }

        /// Every change to the text, an undone one too, which the text view doesn't tell its delegate about.
        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange,
                         changeInLength: Int) {
            guard editedMask.contains(.editedCharacters), !isSettingText else { return }
            if storage.string != text.wrappedValue { text.wrappedValue = storage.string }
            let pasted = storage.sampleGlyphs()
            markedGlyphs = pasted
            if pasted != glyphs.wrappedValue { glyphs.wrappedValue = pasted }
        }

        /// What's typed next to a pasted glyph is typed as it is, not as the glyph.
        func textView(_ view: NSTextView, shouldChangeTypingAttributes oldAttributes: [String: Any],
                      toAttributes newAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            newAttributes.filter { $0.key != .sampleGlyph && $0.key != .glyphInfo }
        }

        /// A paragraph as drawn: its pasted glyphs in place of their characters, where the style has them. Only
        /// drawn, so the text itself keeps its attributes as they are while typing.
        func textContentStorage(_ content: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            guard let storage = content.textStorage, let glyphStyle else { return nil }
            let pasted = storage.sampleGlyphs(in: range)
            guard !pasted.isEmpty else { return nil }
            let paragraph = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            for run in pasted where run.glyph.family == glyphStyle.family {
                guard let glyph = shownGlyph(run.glyph, in: glyphStyle),
                      let info = NSGlyphInfo(cgGlyph: glyph, for: glyphStyle.font as NSFont, baseString: run.glyph.characters)
                else { continue }
                paragraph.addAttribute(.glyphInfo, value: info, range: run.range)
            }
            return NSTextParagraph(attributedString: paragraph)
        }

        private func shownGlyph(_ glyph: SampleGlyph, in style: GlyphStyle) -> CGGlyph? {
            if let shown = shownGlyphs[glyph] { return shown }
            let shown = glyph.glyph(in: style.font, face: style.face)
            shownGlyphs[glyph] = shown
            return shown
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
/// shows the page's menu, not the text view's. Glyphs copied from the page's Glyphs paste as glyphs, and those in
/// its text copy as glyphs too.
private final class SampleTextView: NSTextView {
    /// The text, which the text view only points to.
    var content: NSTextContentStorage?
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

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.sampleClip] + super.readablePasteboardTypes
    }

    override func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType],
                                          restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? {
        if availableTypes.contains(.sampleClip), allowedTypes?.contains(.sampleClip) ?? true { return .sampleClip }
        return super.preferredPasteboardType(from: availableTypes, restrictedToTypesFrom: allowedTypes)
    }

    /// The selection in another case, or the whole text with nothing selected, as one step to undo, selected afterwards
    /// if it was before. ß in capitals is ẞ where `font` has it, SS where it doesn't. Pasted glyphs stay marked where their characters are the same, as figures are; a letter in
    /// another case is another glyph.
    func convert(_ conversion: CaseConversion, in font: CTFont) {
        guard let storage = textStorage else { return }
        let selected = selectedRange()
        let range = selected.length > 0 ? selected : NSRange(location: 0, length: storage.length)
        let old = storage.attributedSubstring(from: range)
        var capitalSharpS: UniChar = 0x1E9E, glyph: CGGlyph = 0
        let converted = conversion.apply(to: old.string, capitalSharpS: CTFontGetGlyphsForCharacters(font, &capitalSharpS, &glyph, 1))
        guard converted != old.string else { return }
        let new = NSMutableAttributedString(string: converted, attributes: typingAttributes.filter { $0.key != .sampleGlyph && $0.key != .glyphInfo })
        // Letter for letter, unless one became two, like ß as SS.
        if (converted as NSString).length == old.length {
            let oldString = old.string as NSString, newString = converted as NSString
            old.enumerateAttributes(in: NSRange(location: 0, length: old.length)) { attributes, run, _ in
                let same = oldString.substring(with: run) == newString.substring(with: run)
                new.setAttributes(same ? attributes : attributes.filter { $0.key != .sampleGlyph && $0.key != .glyphInfo }, range: run)
            }
        }
        // In the text, so that Undo, which goes to it, takes the change back, and typing carries on there.
        window?.makeFirstResponder(self)
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: converted) else { return }
        storage.replaceCharacters(in: range, with: new)
        didChangeText()
        breakUndoCoalescing()
        setSelectedRange(selected.length > 0 ? NSRange(location: range.location, length: new.length)
                                              : NSRange(location: min(selected.location, storage.length), length: 0))
    }

    /// The characters with their glyphs marked, in place of the selection, as one step to undo.
    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .sampleClip, let clip = SampleClip.read(from: pasteboard) else {
            return super.readSelection(from: pasteboard, type: type)
        }
        let range = rangeForUserTextChange
        guard range.location != NSNotFound, let storage = textStorage else { return false }
        // Not with what was typed before it or after.
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: clip.text) else { return false }
        let attributes = typingAttributes.filter { $0.key != .sampleGlyph && $0.key != .glyphInfo }
        let pasted = NSMutableAttributedString(string: clip.text, attributes: attributes)
        pasted.addSampleGlyphs(clip.glyphs)
        storage.replaceCharacters(in: range, with: pasted)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + pasted.length, length: 0))
        breakUndoCoalescing()
        return true
    }

    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard super.writeSelection(to: pasteboard, types: types) else { return false }
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count == 1, let range = ranges.first, let storage = textStorage {
            let glyphs = storage.sampleGlyphs(in: range)
            if !glyphs.isEmpty {
                SampleClip(text: (storage.string as NSString).substring(with: range), glyphs: glyphs).add(to: pasteboard)
            }
        }
        return true
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

/// Sets the insertion point on the font rather than on the line: from the font's ascent above the baseline to its
/// descent below, as far apart as the lines may be, and raised with the line (`raise`, see `UnclippedFragment`).
/// TextKit made it as tall as the line, so with the lines closer than the font is tall it started halfway up the
/// capitals and reached below the descenders, and with them farther apart it reached high above the letters.
nonisolated private final class SampleLayoutManager: NSTextLayoutManager {
    var font: CTFont?
    /// How far each line is drawn above where TextKit sets it (see `SampleEditor.Style.raise`).
    var raise: CGFloat = 0

    override func enumerateTextSegments(in textRange: NSTextRange, type: SegmentType, options: SegmentOptions = [],
                                        using block: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool) {
        guard textRange.isEmpty, let font else { return super.enumerateTextSegments(in: textRange, type: type, options: options, using: block) }
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        super.enumerateTextSegments(in: textRange, type: type, options: options) { range, frame, baseline, container in
            let caret = CGRect(x: frame.minX, y: frame.minY + baseline - raise - ascent, width: frame.width, height: ascent + descent)
            return block(range, caret, ascent, container)
        }
    }
}

/// A paragraph of the sample whose glyphs draw however far past their lines they reach, each line in the middle of
/// its height. TextKit draws each paragraph within its rendering surface, which is only as tall as the font's ascent
/// and descent, and sets each baseline the font's descent above the bottom of its line, so all the room a large
/// line height added went above the letters: a single line sat at the bottom of the text.
nonisolated private final class UnclippedFragment: NSTextLayoutFragment {
    private var raise: CGFloat { (textLayoutManager as? SampleLayoutManager)?.raise ?? 0 }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: CGPoint(x: point.x, y: point.y - raise), in: context)
    }

    override var renderingSurfaceBounds: CGRect {
        let raise = raise
        return textLineFragments.reduce(super.renderingSurfaceBounds.offsetBy(dx: 0, dy: -raise)) { bounds, line in
            let string = line.attributedString.attributedSubstring(from: line.characterRange)
            let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(string), .useGlyphPathBounds)
            guard !ink.isNull, !ink.isEmpty else { return bounds }
            // From the line's baseline, y up, to the paragraph's coordinates, y down.
            let x = line.typographicBounds.minX + line.glyphOrigin.x
            let baseline = line.typographicBounds.minY + line.glyphOrigin.y - raise
            let glyphs = CGRect(x: x + ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
            return bounds.union(glyphs.insetBy(dx: -2, dy: -2))
        }
    }
}
