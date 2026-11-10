import AppKit
import CiceroCore
import SwiftUI

@Observable
final class QuickLook {
    private(set) var isOpen = false
    private(set) var order: [String] = []
    private var currentID: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var preview: PreviewSettings?
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private var mainWindowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var panel: QuickLookPanel?
    @ObservationIgnored private var opening = 0

    private static let sizeKey = "quickLook.panelSize"
    static let defaultSize = NSSize(width: 520, height: 440)

    // MARK: What it shows

    var families: [Family] {
        guard let model else { return [] }
        let selected = model.shownSelection
        if selected.count == 1, let id = selected.first { return model.family(id).map { [$0] } ?? [] }
        var ids = order.filter(selected.contains)
        if ids.count < selected.count {
            let listed = Set(ids)
            ids += model.library.families.lazy.map(\.id).filter { selected.contains($0) && !listed.contains($0) }
        }
        return ids.compactMap(model.family)
    }

    var shown: (family: Family, index: Int, count: Int)? {
        let families = families
        guard !families.isEmpty else { return nil }
        let index = families.count == 1 ? 0 : families.firstIndex { $0.id == currentID } ?? 0
        return (families[index], index, families.count)
    }

    func updateOrder(_ ids: [String]) {
        if ids != order { order = ids }
    }

    func step(_ delta: Int) -> Bool {
        let families = families
        guard isOpen, families.count > 1 else { return false }
        let index = families.firstIndex { $0.id == currentID } ?? 0
        currentID = families[(index + delta + families.count) % families.count].id
        return true
    }

    func selectionChanged(from old: Set<String>, to new: Set<String>) {
        let added = new.subtracting(old)
        if added.count == 1 {
            currentID = added.first
        } else if let id = currentID, !new.contains(id) {
            currentID = nil
        }
        if new.isEmpty { close() }
    }

    // MARK: Opening and closing

    func toggle(order: [String]? = nil) {
        if isOpen { close() } else { open(order: order) }
    }

    func open(order: [String]? = nil) {
        guard !isOpen, let model, let preview, model.openFamilyID == nil, !model.shownSelection.isEmpty else { return }
        if let order { updateOrder(order) }
        let panel = panel ?? makePanel(model: model, preview: preview)
        isOpen = true
        place(panel)
        panel.orderFront(nil)
        opening += 1
        closeWhenNothingShows(opening)
    }

    private func closeWhenNothingShows(_ opening: Int) {
        withObservationTracking {
            _ = shown?.family.id
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen, self.opening == opening else { return }
                if self.shown == nil { self.close() } else { self.closeWhenNothingShows(opening) }
            }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        panel?.orderOut(nil)
    }

    func setTitle(_ title: String) {
        panel?.title = title
    }

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
            // Sheets and alerts would open under the panel.
            center.addObserver(forName: NSWindow.willBeginSheetNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
            },
            center.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.panel?.orderFront(nil)
                }
            },
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
        center.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSize() }
        }
        self.panel = panel
        return panel
    }

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

    private func saveSize() {
        guard let panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: Self.sizeKey)
    }
}

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
        if #available(macOS 26, *) { styleMask.insert(.fullSizeContentView) }
        minSize = NSSize(width: 420, height: 320)
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        backgroundColor = Self.page
        addTitleBar()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func zoom(_ sender: Any?) {}

    static let page = NSColor(name: nil) { appearance in
        var page = NSColor.textBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            // As an sRGB colour, as SwiftUI draws this grey, lighter in dark mode than AppKit draws it.
            if let grey = NSColor.textBackgroundColor.usingColorSpace(.genericGamma22Gray) {
                page = NSColor(srgbRed: grey.whiteComponent, green: grey.whiteComponent, blue: grey.whiteComponent, alpha: grey.alphaComponent)
            }
        }
        return page
    }

    override var title: String {
        didSet { titleLabel.stringValue = title }
    }

    private let titleLabel = NSTextField(labelWithString: "")

    private func addTitleBar() {
        guard let close = standardWindowButton(.closeButton), let bar = close.superview else { return }
        // A title of its own: AppKit sets its title after the buttons it shows, and elsewhere once the title bar has views of its own.
        titleVisibility = .hidden
        // A panel that's never key shows its own close button grey and empty.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
        let closeButton = QuickLookTitleButton { [weak self] in self?.close() }
        closeButton.toolTip = "Close"
        closeButton.setAccessibilityLabel("Close")
        let top: NSView.AutoresizingMask = bar.isFlipped ? .maxYMargin : .minYMargin
        let centre = NSPoint(x: close.frame.midX + 1.5, y: close.frame.midY)
        let side = QuickLookTitleButton.side
        closeButton.frame = NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        closeButton.autoresizingMask = [.maxXMargin, top]
        bar.addSubview(closeButton)
        titleLabel.font = .titleBarFont(ofSize: 0)
        titleLabel.textColor = QuickLookTitleButton.titleColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.sizeToFit()
        let start = (centre.x + QuickLookTitleButton.diameter / 2 + 9 - 2.5).rounded()
        titleLabel.frame = NSRect(x: start, y: (centre.y - titleLabel.frame.height / 2).rounded(),
                                  width: max(0, bar.bounds.width - start - 12), height: titleLabel.frame.height)
        titleLabel.autoresizingMask = [.width, top]
        bar.addSubview(titleLabel)
    }
}

private final class QuickLookTitleButton: NSButton {
    static let diameter: CGFloat = 12
    static let side: CGFloat = 16
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

    init(action: @escaping () -> Void) {
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
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor((isHighlighted ? Self.pressedCircle : Self.circle).cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        context.setBlendMode(.clear)
        context.setLineWidth(1.75)
        context.setLineCap(.round)
        context.strokeLineSegments(between: [CGPoint(x: 3.57, y: 3.57), CGPoint(x: 8.43, y: 8.43),
                                             CGPoint(x: 3.57, y: 8.43), CGPoint(x: 8.43, y: 3.57)])
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct QuickLookHost: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        WindowReader { window in model.quickLook.attach(to: window, model: model, preview: preview) }
            .onChange(of: model.selectedIDs) { old, new in model.quickLook.selectionChanged(from: old, to: new) }
            .onChange(of: model.openFamilyID) { _, id in if id != nil { model.quickLook.close() } }
    }
}

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

private struct QuickLookView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.quickLook.isOpen, let shown = model.quickLook.shown {
            GeometryReader { proxy in
                FamilyQuickLook(family: shown.family, index: shown.index, count: shown.count, width: proxy.size.width,
                                titleBar: proxy.safeAreaInsets.top)
                    .id(shown.family.id)
            }
        }
    }
}

private struct FamilyQuickLook: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.colorScheme) private var colorScheme
    let family: Family
    let index: Int
    let count: Int
    let width: CGFloat
    let titleBar: CGFloat
    @State private var isScrolled = false

    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789"
    private static let inset: CGFloat = 28

    private var scale: Double {
        max(0.1, (width - 2 * Self.inset) / (QuickLook.defaultSize.width - 2 * Self.inset))
    }

    var body: some View {
        let scale = scale
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sample(scale: scale)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 12 * scale)
                    .padding(.bottom, 24 * scale)
                if family.faces.count > 1 {
                    Divider()
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 15 * scale)
                    ForEach(family.faces) { style in
                        QuickLookText(text: style.face.styleName, face: style.face, size: 22 * scale, weight: style.face.styleWeight)
                            .frame(minHeight: 22 * scale * 1.25)
                            .padding(.horizontal, Self.inset)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            .foregroundStyle(Color.ink)
        }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 0.5 }) { _, scrolled in
            isScrolled = scrolled
        }
        .underTitleBar(titleBar, isScrolled: isScrolled)
        .background(Color(nsColor: QuickLookPanel.page))
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onChange(of: family.name, initial: true) { model.quickLook.setTitle(family.name) }
    }

    private func sample(scale: Double) -> some View {
        let face = family.regular.face
        let variations = model.variations(for: family)
        return Group {
            if preview.sampleText.isEmpty {
                VStack(alignment: .leading, spacing: 14 * scale) {
                    QuickLookText(text: model.scriptSamples.text(PreviewSettings.tileSample, for: face), face: face, size: 96 * scale,
                                  variations: variations)
                        .minimumScaleFactor(0.4)
                    QuickLookText(text: model.scriptSamples.text(Self.alphabet, for: face, long: true), face: face, size: 24 * scale,
                                  variations: variations, lineLimit: nil, lineHeight: 24 * scale * 1.2)
                }
            } else {
                QuickLookText(text: model.scriptSamples.text(preview.sampleText, for: face, long: true), face: face, size: 56 * scale,
                              variations: variations, lineLimit: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if count > 1 {
                HStack(spacing: 6) {
                    Button("Previous", systemImage: "chevron.left") { _ = model.quickLook.step(-1) }
                        .help("Show the previous family")
                    Text("\((index + 1).plain) of \(count.plain)").monospacedDigit()
                    Button("Next", systemImage: "chevron.right") { _ = model.quickLook.step(1) }
                        .help("Show the next family")
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
        .overlay {
            if #available(macOS 26, *), colorScheme == .dark {
                Capsule().fill(.white.opacity(0.06)).allowsHitTesting(false)
            }
        }
        .padding(12)
    }

    private var summary: String {
        var parts: [String] = []
        if let foundry = model.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.format.rawValue)
        if family.isVariable { parts.append("Variable") }
        parts.append(family.stylesLabel)
        parts.append(status)
        return parts.joined(separator: " · ")
    }

    private var status: String {
        let labels = Set(family.faces.map(\.state.label))
        if labels.count == 1, let label = labels.first { return label }
        return family.activeCount == family.faces.count ? "Active" : "\(family.activeCount) of \(family.faces.count) active"
    }
}

private extension View {
    @ViewBuilder func underTitleBar(_ height: CGFloat, isScrolled: Bool) -> some View {
        if #available(macOS 26, *) {
            // A bar that draws something, however faint: a clear one gets no edge effect under it.
            safeAreaBar(edge: .top, spacing: 0) {
                Color.black.opacity(0.001)
                    .frame(height: height)
                    .overlay(alignment: .bottom) { if isScrolled { Divider() } }
                    .allowsHitTesting(false)
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            .ignoresSafeArea(.container, edges: .top)
        } else {
            overlay(alignment: .top) { if isScrolled { Divider() } }
        }
    }
}

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
                     lineLimit: lineLimit, lineHeight: lineHeight, cached: false)
        } else {
            Text(text)
                .font(.system(size: size))
                .lineLimit(lineLimit)
                .lineHeight(lineHeight, natural: (NSFont.systemFont(ofSize: size) as CTFont).naturalLineHeight)
                .hidden()
                .task(id: face.id) {
                    await FontLoader.shared.read(face.path)
                    readPath = face.path
                }
        }
    }
}
