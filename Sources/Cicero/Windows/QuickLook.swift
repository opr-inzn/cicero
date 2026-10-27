import AppKit
import CiceroCore
import SwiftUI

/// Quick Look: a floating panel with the family selected in the browser, opened and closed with Space or ⌘Y.
/// With several selected it shows one at a time. The panel never takes the keyboard, so the browser's arrow
/// keys go on moving the selection and the panel follows. The model owns it; `QuickLookHost` in the main
/// window hands it the window and the selection's changes.
@Observable
final class QuickLook {
    private(set) var isOpen = false
    /// The browser's families in the order it shows them, so several selected ones go in that order.
    private(set) var order: [String] = []
    /// The family added to the selection last (a click, an arrow key) or gone to with ‹ ›; shown while it's selected.
    private var currentID: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var preview: PreviewSettings?
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private var mainWindowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var panel: QuickLookPanel?

    /// Saved once the user resizes it. (The size under "quickLook.size" was saved on every close, so it was
    /// the old default, 680 × 620, for most.)
    private static let sizeKey = "quickLook.panelSize"
    static let defaultSize = NSSize(width: 520, height: 440)

    // MARK: What it shows

    /// The selected families, in the browser's order.
    var families: [Family] {
        guard let model else { return [] }
        let selected = model.selectedIDs
        if selected.count == 1, let id = selected.first { return model.family(id).map { [$0] } ?? [] }
        var ids = order.filter(selected.contains)
        if ids.count < selected.count {
            // Selected but not in the order the browser last gave (sorted or filtered since): after the others.
            let listed = Set(ids)
            ids += model.library.families.lazy.map(\.id).filter { selected.contains($0) && !listed.contains($0) }
        }
        return ids.compactMap(model.family)
    }

    /// The family the panel shows, its place among the selected ones and how many there are.
    var shown: (family: Family, index: Int, count: Int)? {
        let families = families
        guard !families.isEmpty else { return nil }
        // One family doesn't depend on `currentID`, which every arrow key changes too.
        let index = families.count == 1 ? 0 : families.firstIndex { $0.id == currentID } ?? 0
        return (families[index], index, families.count)
    }

    func updateOrder(_ ids: [String]) {
        if ids != order { order = ids }
    }

    /// Goes to the next or previous of several selected families, round to the first after the last.
    /// False when there's only one.
    func step(_ delta: Int) -> Bool {
        let families = families
        guard isOpen, families.count > 1 else { return false }
        let index = families.firstIndex { $0.id == currentID } ?? 0
        currentID = families[(index + delta + families.count) % families.count].id
        return true
    }

    /// Follows the browser: shows a family that's just been added to the selection, and closes when nothing is selected.
    func selectionChanged(from old: Set<String>, to new: Set<String>) {
        let added = new.subtracting(old)
        // Several at once (⌘A, a ⇧-click) keep the one shown.
        if added.count == 1 {
            currentID = added.first
        } else if let id = currentID, !new.contains(id) {
            currentID = nil
        }
        if new.isEmpty { close() }
    }

    // MARK: Opening and closing

    /// `order` is the browser's families in the order it shows them.
    func toggle(order: [String]? = nil) {
        if isOpen { close() } else { open(order: order) }
    }

    /// Opens over the main window, unless nothing is selected or a font page is open.
    func open(order: [String]? = nil) {
        guard !isOpen, let model, let preview, model.openFamilyID == nil, !model.selectedIDs.isEmpty else { return }
        if let order { updateOrder(order) }
        let panel = panel ?? makePanel(model: model, preview: preview)
        isOpen = true
        place(panel)
        panel.orderFront(nil)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        panel?.orderOut(nil)
    }

    func setTitle(_ title: String) {
        panel?.title = title
    }

    /// The main window: the panel opens centred over it, closes with it, and steps aside while it shows a sheet.
    func attach(to window: NSWindow, model: AppModel, preview: PreviewSettings) {
        self.model = model
        self.preview = preview
        guard window !== mainWindow else { return }
        mainWindow = window
        let center = NotificationCenter.default
        for observer in mainWindowObservers { center.removeObserver(observer) }
        mainWindowObservers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
            // Sheets and alerts (the activation prompt, say, from the panel's switch) would open under the panel.
            center.addObserver(forName: NSWindow.willBeginSheetNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
            },
            center.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.panel?.orderFront(nil)
                }
            },
            // It goes to the Dock with the window and comes back with it.
            center.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
            },
            center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.panel?.orderFront(nil)
                }
            },
        ]
    }

    private func makePanel(model: AppModel, preview: PreviewSettings) -> QuickLookPanel {
        let panel = QuickLookPanel(size: Self.defaultSize)
        let content = FirstClickHostingView(rootView: QuickLookView().environment(model).environment(preview))
        // The panel's size is the user's, not the content's.
        content.sizingOptions = []
        panel.contentView = content
        let center = NotificationCenter.default
        // Its close button.
        center.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSize() }
        }
        self.panel = panel
        return panel
    }

    /// Centres the panel over the main window, at the size it was last left at, on the main window's screen.
    private func place(_ panel: NSPanel) {
        var size = NSSizeFromString(UserDefaults.standard.string(forKey: Self.sizeKey) ?? "")
        if size.width < panel.minSize.width || size.height < panel.minSize.height { size = Self.defaultSize }
        let screen = (mainWindow?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let over = mainWindow?.frame ?? screen
        size.width = min(size.width, screen.width)
        size.height = min(size.height, screen.height)
        let x = min(max(over.midX - size.width / 2, screen.minX), screen.maxX - size.width)
        let y = min(max(over.midY - size.height / 2, screen.minY), screen.maxY - size.height)
        panel.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: false)
    }

    /// Not while it fills the screen: filling it and going back end as a live resize does.
    private func saveSize() {
        guard let panel, panel.isVisible, !panel.isZoomed else { return }
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: Self.sizeKey)
    }
}

/// A floating panel that never becomes key: the main window keeps the keyboard, so the browser's arrow
/// keys move the selection while the panel shows it. Hides while Cicero isn't the active app. A full title
/// bar, not a utility window's, whose buttons and title are smaller than other windows'.
final class QuickLookPanel: NSPanel {
    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size),
                  styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                  backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        isRestorable = false
        isExcludedFromWindowsMenu = true
        collectionBehavior.insert(.fullScreenAuxiliary)
        minSize = NSSize(width: 420, height: 320)
        // The title bar in the page's colour, so the name sits on the specimen.
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        backgroundColor = .textBackgroundColor
        addTitleBar()
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFillButton() }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override var title: String {
        didSet { titleLabel.stringValue = title }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private var fillButton: QuickLookTitleButton?

    /// Finder's Quick Look's title bar: two buttons in place of the window's own, which a panel that's never key shows
    /// grey and empty (one closes it, the other fills the screen with it and goes back to the size it had, as the green
    /// button did), and the title beside them. A title of its own: AppKit sets its title after the buttons it shows, and
    /// elsewhere once the title bar has views of its own.
    private func addTitleBar() {
        guard let close = standardWindowButton(.closeButton), let bar = close.superview else { return }
        titleVisibility = .hidden
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
        let closeButton = QuickLookTitleButton(glyph: .close) { [weak self] in self?.close() }
        closeButton.toolTip = "Close"
        closeButton.setAccessibilityLabel("Close")
        let fillButton = QuickLookTitleButton(glyph: .fill) { [weak self] in self?.zoom(nil) }
        // Where Finder's are: the close button 1.5 pt right of the window's own, the other 20 pt on. Kept from the bar's
        // top and left.
        let top: NSView.AutoresizingMask = bar.isFlipped ? .maxYMargin : .minYMargin
        let centre = NSPoint(x: close.frame.midX + 1.5, y: close.frame.midY)
        for (index, button) in [closeButton, fillButton].enumerated() {
            let side = QuickLookTitleButton.side
            button.frame = NSRect(x: centre.x + CGFloat(index) * 20 - side / 2, y: centre.y - side / 2, width: side, height: side)
            button.autoresizingMask = [.maxXMargin, top]
            bar.addSubview(button)
        }
        titleLabel.font = .titleBarFont(ofSize: 0)
        titleLabel.textColor = QuickLookTitleButton.titleColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.sizeToFit()
        // Its letters 9 pt after the second circle, less the label's own inset.
        let start = (centre.x + 20 + QuickLookTitleButton.diameter / 2 + 9 - 2.5).rounded()
        titleLabel.frame = NSRect(x: start, y: (centre.y - titleLabel.frame.height / 2).rounded(),
                                  width: max(0, bar.bounds.width - start - 12), height: titleLabel.frame.height)
        titleLabel.autoresizingMask = [.width, top]
        bar.addSubview(titleLabel)
        self.fillButton = fillButton
        updateFillButton()
    }

    private func updateFillButton() {
        guard let fillButton else { return }
        let filled = isZoomed
        fillButton.glyph = filled ? .unfill : .fill
        fillButton.toolTip = filled ? "Return to the previous size" : "Fill the screen"
        fillButton.setAccessibilityLabel(filled ? "Return to Previous Size" : "Fill")
    }
}

/// A grey circle with its symbol cut out, drawn as Finder's Quick Look draws its own: a 12 pt circle, an × of round
/// strokes or the full-screen triangles. Drawn here rather than as a tinted symbol, which AppKit greys in a window that
/// isn't key, as this one never is. It takes the first click in the panel.
private final class QuickLookTitleButton: NSButton {
    enum Glyph {
        case close, fill, unfill
    }

    static let diameter: CGFloat = 12
    /// Room to click around the circle.
    static let side: CGFloat = 16
    /// Finder's greys, measured from its Quick Look on screen: black or white, partly see-through.
    private static let circle = grey(light: 0.55, dark: 0.8)
    private static let pressedCircle = grey(light: 0.72, dark: 0.92)
    static let titleColor = grey(light: 0.71, dark: 0.74)

    private static func grey(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: dark) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: light)
        }
    }

    private let perform: () -> Void

    var glyph: Glyph {
        didSet { if glyph != oldValue { needsDisplay = true } }
    }

    init(glyph: Glyph, action: @escaping () -> Void) {
        self.glyph = glyph
        perform = action
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        self.action = #selector(clicked)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func clicked() { perform() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX - Self.diameter / 2, y: bounds.midY - Self.diameter / 2)
        // The symbol cuts the circle only.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor((isHighlighted ? Self.pressedCircle : Self.circle).cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        context.setBlendMode(.clear)
        switch glyph {
        case .close:
            context.setLineWidth(1.75)
            context.setLineCap(.round)
            context.strokeLineSegments(between: [CGPoint(x: 3.57, y: 3.57), CGPoint(x: 8.43, y: 8.43),
                                                 CGPoint(x: 3.57, y: 8.43), CGPoint(x: 8.43, y: 3.57)])
        case .fill:
            // Pointing out to the top left and the bottom right.
            context.addPath(Self.triangle(corner: CGPoint(x: 3, y: 3), legs: 4.25, towards: 1))
            context.addPath(Self.triangle(corner: CGPoint(x: 9, y: 9), legs: 4.25, towards: -1))
            context.fillPath()
        case .unfill:
            // Pointing in, at each other.
            context.addPath(Self.triangle(corner: CGPoint(x: 5.25, y: 5.25), legs: 3.5, towards: -1))
            context.addPath(Self.triangle(corner: CGPoint(x: 6.75, y: 6.75), legs: 3.5, towards: 1))
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// A right triangle with its right angle at `corner`, rounded, and its legs running right and down from it
    /// (`towards` 1) or left and up (-1).
    private static func triangle(corner: CGPoint, legs: CGFloat, towards direction: CGFloat) -> CGPath {
        let across = CGPoint(x: corner.x + legs * direction, y: corner.y)
        let path = CGMutablePath()
        path.move(to: across)
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + legs * direction))
        path.addArc(tangent1End: corner, tangent2End: across, radius: 1)
        path.closeSubpath()
        return path
    }
}

/// Takes a click in a window that isn't key as a click, not as a request to bring the window forward:
/// the panel is never key, so every click in it is a first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// In the main window: hands Quick Look the window and has it follow the selection, closing when a font page opens.
struct QuickLookHost: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        WindowReader { window in model.quickLook.attach(to: window, model: model, preview: preview) }
            .onChange(of: model.selectedIDs) { old, new in model.quickLook.selectionChanged(from: old, to: new) }
            .onChange(of: model.openFamilyID) { _, id in if id != nil { model.quickLook.close() } }
    }
}

/// Calls `found` with the window the view is in, once it's in one.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReaderView { WindowReaderView(found: found) }
    func updateNSView(_ view: WindowReaderView, context: Context) {}
}

final class WindowReaderView: NSView {
    let found: (NSWindow) -> Void

    init(found: @escaping (NSWindow) -> Void) {
        self.found = found
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { found(window) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Content

/// The panel's content, while it's open, in the panel's width, which its type follows.
private struct QuickLookView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.quickLook.isOpen, let shown = model.quickLook.shown {
            GeometryReader { proxy in
                FamilyQuickLook(family: shown.family, index: shown.index, count: shown.count, width: proxy.size.width)
                    // A new family starts at the top.
                    .id(shown.family.id)
            }
        }
    }
}

/// A large sample in the regular style, every style set in itself, and a line about the family with its switch.
private struct FamilyQuickLook: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let index: Int
    let count: Int
    let width: CGFloat

    /// Under "Aa Gg 123" when no sample text is set.
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789"
    private static let inset: CGFloat = 28

    /// How much bigger than in the panel at its first width the sample and the styles are drawn: they're laid out as
    /// there and zoomed to the panel's width, the margins at the sides staying as they are (see `Zoomed`).
    private var scale: CGFloat {
        max(0.1, (width - 2 * Self.inset) / (QuickLook.defaultSize.width - 2 * Self.inset))
    }

    var body: some View {
        let scale = scale
        ScrollView {
            // Lazy, so a family with hundreds of named instances makes only the rows on screen.
            LazyVStack(alignment: .leading, spacing: 0) {
                sample()
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .zoomed(scale)
                    .padding(.horizontal, Self.inset)
                // With one style the sample already shows it.
                if family.faces.count > 1 {
                    Divider()
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 15 * scale)
                    ForEach(family.faces) { style in
                        QuickLookText(text: style.face.styleName, face: style.face, size: 22, weight: style.face.styleWeight)
                            // As tall as the font's own line spacing, without padding: some fonts keep room above their
                            // capitals (for accents, a taller style), and padding as well spread the rows far apart.
                            // At least 1.25 × the size, for fonts set tight.
                            .frame(minHeight: 22 * 1.25)
                            .zoomed(scale)
                            .padding(.horizontal, Self.inset)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onChange(of: family.name, initial: true) { model.quickLook.setTitle(family.name) }
    }

    /// On the left. The sample text with Preview Options' leading; the alphabet, three lines of letters rather than
    /// text, always 120 % of its size apart, so a high Leading set for the text doesn't spread them out.
    private func sample() -> some View {
        let face = family.regular.face
        let variations = model.variations(for: family)
        return Group {
            if preview.sampleText.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    QuickLookText(text: model.scriptSamples.text(PreviewSettings.tileSample, for: face), face: face, size: 96,
                                  variations: variations)
                        .minimumScaleFactor(0.4)
                    QuickLookText(text: model.scriptSamples.text(Self.alphabet, for: face, long: true), face: face, size: 24, variations: variations,
                                  lineLimit: nil, lineHeight: 24 * 1.2)
                }
            } else {
                QuickLookText(text: model.scriptSamples.text(preview.sampleText, for: face, long: true), face: face, size: 56,
                              variations: variations, lineLimit: nil, lineHeight: preview.lineHeight(at: 56))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if count > 1 {
                HStack(spacing: 6) {
                    Button("Previous", systemImage: "chevron.left") { _ = model.quickLook.step(-1) }
                        .help("Show the previous font")
                    Text("\((index + 1).formatted()) of \(count.formatted())").monospacedDigit()
                    Button("Next", systemImage: "chevron.right") { _ = model.quickLook.step(1) }
                        .help("Show the next font")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                Divider().frame(height: 16)
            }
            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(summary)
            Spacer(minLength: 8)
            ActivationSwitch(family: family, model: model)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glass(in: .capsule)
        .padding(12)
    }

    /// "Foundry · OpenType PostScript · Variable · 12 styles · Active".
    private var summary: String {
        var parts: [String] = []
        if let foundry = model.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.format.rawValue)
        if family.isVariable { parts.append("Variable") }
        parts.append(family.stylesLabel)
        parts.append(status)
        return parts.joined(separator: " · ")
    }

    /// The styles' status when they share one ("Inactive", "Active until Cicero quits"), else how many are on.
    private var status: String {
        let labels = Set(family.faces.map(\.state.label))
        if labels.count == 1, let label = labels.first { return label }
        return family.activeCount == family.faces.count ? "Active" : "\(family.activeCount) of \(family.faces.count) active"
    }
}

/// Lays its content out `scale` times smaller than the room it's given and draws it `scale` times bigger, so it looks the
/// same at any width, only bigger or smaller: resizing the panel zooms it smoothly, where setting the type a size bigger
/// or smaller had lines jump from one whole point to the next and rows move with them.
private struct Zoomed: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / scale },
                                                         height: proposal.height.map { $0 / scale }))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}

private extension View {
    func zoomed(_ scale: CGFloat) -> some View {
        Zoomed(scale: scale) { scaleEffect(scale, anchor: .topLeading) }
    }
}

/// `FontText` once its face's file has been read. Until then the file is read off the main thread, with room
/// kept for the text, so stepping onto a family whose files nothing has read yet never holds up the selection.
private struct QuickLookText: View {
    let text: String
    let face: FontFace
    let size: Double
    var weight: Double = 400
    var variations: [String: Double] = [:]
    var lineLimit: Int? = 1
    var lineHeight: Double?
    @State private var readPath: String?

    var body: some View {
        if readPath == face.path || FontLoader.shared.hasDescriptors(for: face.path) {
            FontText(text: text, face: face, size: size, weight: weight, variations: variations,
                     lineLimit: lineLimit, lineHeight: lineHeight)
        } else {
            Text(text)
                .font(.system(size: size))
                .lineLimit(lineLimit)
                .lineHeight(lineHeight, natural: (NSFont.systemFont(ofSize: size) as CTFont).naturalLineHeight)
                .hidden()
                .task(id: face.id) {
                    let (face, size, weight, variations) = (face, size, weight, variations)
                    // Makes the font too, so drawing it is a cache hit.
                    await Task.detached(priority: .userInitiated) {
                        _ = FontLoader.shared.font(face, size: size, weight: weight, variations: variations)
                    }.value
                    readPath = face.path
                }
        }
    }
}
