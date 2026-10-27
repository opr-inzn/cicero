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

    private func saveSize() {
        guard let panel, panel.isVisible else { return }
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

    /// How much bigger than in the panel at its first width the type and the room around it are: they grow and shrink
    /// with the panel's width, the margins at the sides stay.
    private var scale: CGFloat {
        max(0.1, (width - 2 * Self.inset) / (QuickLook.defaultSize.width - 2 * Self.inset))
    }

    /// A size in the panel at its first width, at the panel's width, in whole points.
    private func size(_ points: Double) -> Double {
        max(1, (points * scale).rounded())
    }

    var body: some View {
        let styleSize = size(22)
        ScrollView {
            // Lazy, so a family with hundreds of named instances makes only the rows on screen.
            LazyVStack(alignment: .leading, spacing: 0) {
                sample()
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 12 * scale)
                    .padding(.bottom, 24 * scale)
                // With one style the sample already shows it.
                if family.faces.count > 1 {
                    Divider()
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 15 * scale)
                    ForEach(family.faces) { style in
                        QuickLookText(text: style.face.styleName, face: style.face, size: styleSize, weight: style.face.styleWeight)
                            // As tall as the font's own line spacing, without padding: some fonts keep room above their
                            // capitals (for accents, a taller style), and padding as well spread the rows far apart.
                            // At least 1.25 × the size, for fonts set tight.
                            .frame(minHeight: styleSize * 1.25)
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
                VStack(alignment: .leading, spacing: 14 * scale) {
                    QuickLookText(text: model.scriptSamples.text(PreviewSettings.tileSample, for: face), face: face, size: size(96),
                                  variations: variations)
                        .minimumScaleFactor(0.4)
                    QuickLookText(text: model.scriptSamples.text(Self.alphabet, for: face, long: true), face: face, size: size(24),
                                  variations: variations, lineLimit: nil, lineHeight: size(24) * 1.2)
                }
            } else {
                QuickLookText(text: model.scriptSamples.text(preview.sampleText, for: face, long: true), face: face, size: size(56),
                              variations: variations, lineLimit: nil, lineHeight: preview.lineHeight(at: size(56)))
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
