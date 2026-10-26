import AppKit
import CiceroCore
import SwiftUI

/// One family's page, pushed over the browser: a type tester, every style, the families that look most like it, then the
/// glyphs, the ligatures among them, one under the other.
struct FontPage: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let familyID: String
    @State private var glyphColumns: Int?
    /// The ligatures and characters of the face shown, when they weren't ready as the page opened.
    @State private var loaded: (face: FaceID, content: PageContent)?
    @FocusState private var focused: Bool

    var body: some View {
        if let family = model.family(familyID) {
            page(family)
        } else {
            ContentUnavailableView("Font Not Available", systemImage: "textformat",
                                   description: Text("This font is no longer in your library."))
                .onExitCommand { model.openFamilyID = nil }
        }
    }

    private func page(_ family: Family) -> some View {
        // The style the text is set in, whose glyphs the page lists.
        let face = model.previewStyle(of: family, weight: preview.weight).face.face
        // Usually ready before the page opens: the browser starts on a family when it's selected. While another style's
        // are read, the last one's stay, in that style, rather than a spinner in their place.
        let ready = model.pageContents.content(of: face) ?? loaded.flatMap { $0.face == face.id ? $0.content : nil }
        let shown = ready.map { (face: face, content: $0) } ?? loaded.flatMap { last in
            family.faces.first { $0.id == last.face }.map { (face: $0.face, content: last.content) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Header(family: family)
                Divider()
                TypeTester(family: family)
                // With one style the tester already shows it.
                if family.faces.count > 1 {
                    StyleRows(family: family)
                }
                SimilarSection(family: family)
                // Lazy for the glyphs, which can run to thousands of cells. Their group titles scroll with them
                // rather than pin, so the cells only meet the toolbar, where they fade out, instead of showing
                // between it and a pinned title and ending at the title's edge. Only rows about one height go in it:
                // it guesses the height of rows it hasn't placed from those it has, and with the styles in it too
                // (fifty of them are 2,000 pt) the guesses swung so far that, scrolled to the end, the page laid
                // itself out again and again at full CPU.
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Glyphs and ligatures together, once the page's width is known: one arriving after the other, or
                    // their cells after their titles, moved what was already there.
                    if let shown {
                        if let glyphColumns {
                            let content = shown.content
                            GlyphsSection(family: family, face: shown.face, columns: glyphColumns, sections: content.glyphs,
                                          characterCount: content.characterCount, ligatures: content.ligatures,
                                          ligatureCharacters: content.ligatureCharacters, alternates: content.alternates)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 56)
                    }
                }
            }
            // The stack's width is the scroll view's less the Info panel's inset, never the rows', so this settles
            // at once; only a change in the count redraws the glyphs.
            .onGeometryChange(for: Int.self) { GlyphsSection.columns(fitting: $0.size.width) } action: { glyphColumns = $0 }
        }
        // Here, not on a row of the lazy stack, which wouldn't see a change of style while scrolled out of view.
        .task(id: face.id) {
            loaded = (face.id, await model.pageContents.content(loading: face))
        }
        .background(Color.canvas)
        // The page takes focus when it opens, rather than the first field on it, the type tester's size.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .defaultFocus($focused, true)
        .navigationTitle(family.name)
        // No Preview Options: the page has its own size and alignment, and takes the rest (text in the styles
        // list, weight, spacing) from the browser's.
        .toolbar { ToolbarCapsule { InfoButton() } }
        .onExitCommand { model.openFamilyID = nil }
    }
}

/// The family name in its own regular face, a line of facts, and Activate/Deactivate.
private struct Header: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                FamilyName(name: family.name, face: family.regular.face)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            // Worded as in the family's right-click menu: "Activate in All Apps" for one in Adobe's folder.
            let titles = ActivationTitles([family])
            HStack(spacing: 8) {
                if family.hasActivatable {
                    Button(titles.activate) { model.activate([family]) }
                        .buttonStyle(.borderedProminent)
                }
                if family.hasDeactivatable {
                    Button(titles.deactivate) { model.deactivate([family]) }
                } else if !family.hasActivatable && !hasAdobeFonts {
                    Button("Deactivate") {}
                        .disabled(true)
                        .help(lockedReason)
                }
                // Creative Cloud turns Adobe Fonts on and off, not Cicero: on the family's page on Adobe Fonts' website.
                if hasAdobeFonts {
                    if let page = CreativeCloud.page(for: family) {
                        Button("Manage in Adobe Fonts") { NSWorkspace.shared.open(page) }
                            .help("Opens the family’s page on Adobe Fonts, where you turn it on and off")
                    } else {
                        Button("Manage in Creative Cloud") { CreativeCloud.open() }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        // The family's menu, as in the browser; the sample below has it too.
        .contentShape(.rect)
        .contextMenu { FamilyMenu(families: [family], model: model) }
    }

    private var summary: String {
        var parts: [String] = []
        if let foundry = model.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.format.rawValue)
        if family.isVariable { parts.append("Variable") }
        parts.append("\(family.stylesLabel) · \(activation)")
        return parts.joined(separator: " · ")
    }

    /// How many styles are active, partly active (on in one app only, like those in an Adobe folder) and
    /// inactive, leaving out the kinds with none: "3 active · 2 partly active", "2 inactive".
    private var activation: String {
        let partly = family.faces.count { if case .appOnly = $0.state { true } else { false } }
        let counts = [(family.activeCount, "active"), (partly, "partly active"), (family.faces.count - family.activeCount - partly, "inactive")]
        return counts.filter { $0.0 > 0 }.map { "\($0.0.formatted()) \($0.1)" }.joined(separator: " · ")
    }

    private var hasAdobeFonts: Bool { family.faces.contains(where: \.isAdobeFonts) }

    private var lockedReason: String {
        switch family.faces.first?.state.source {
        case .macOS: "Installed with macOS, so it can’t be turned off"
        case .allUsers: "Installed for all users; an administrator has to remove it"
        case .app: "Comes with an app, which manages it"
        default: "Managed outside Cicero"
        }
    }
}

/// The family's name in its own regular face, for the header: 34 pt on a line as tall as most fonts' names take, the same
/// for every family, so headers don't grow with a font's line spacing; or, when its glyphs reach further than the room
/// around that line, like Zapfino's swashes, smaller, just as much as it takes for them to fit whole, in the middle of it.
/// Cut short with "…" when it's wider than the room.
private struct FamilyName: View {
    let name: String
    let face: FontFace
    static let size: CGFloat = 34
    /// The line, and the room its glyphs may take above it, short of the toolbar's edge, and below it, short of the summary.
    static let line: CGFloat = 41
    static let above: CGFloat = 16
    static let below: CGFloat = 4
    /// Room before the name for glyphs reaching back past its start, like a swash on a first capital.
    static let lead: CGFloat = 12

    var body: some View {
        ReadingFonts(paths: [face.path]) {
            Canvas { context, area in
                let color = Color.primary.resolve(in: context.environment).cgColor
                context.withCGContext { Self.draw(name, face: face, in: area, color: color, into: $0) }
            }
        }
        .frame(height: Self.above + Self.line + Self.below)
        .padding(.top, -Self.above)
        .padding(.bottom, -Self.below)
        .padding(.leading, -Self.lead)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
    }

    private static func draw(_ name: String, face: FontFace, in area: CGSize, color: CGColor, into context: CGContext) {
        func line(_ size: CGFloat) -> (font: CTFont, line: CTLine, ink: CGRect) {
            let font = FontLoader.shared.font(face, size: size, weight: 400)
            let line = TextLine(name, font: font, kerning: 0).line
            return (font, line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
        }
        var set = line(size)
        // On the line as the font's own spacing would put it, its ascent and descent in the middle of it.
        let ascent = CTFontGetAscent(set.font), descent = CTFontGetDescent(set.font)
        var baseline = above + (Self.line - ascent - descent) / 2 + ascent
        if !set.ink.isNull, baseline - set.ink.maxY < 0 || baseline - set.ink.minY > area.height {
            set = line(size * min(1, area.height / set.ink.height))
            baseline = (area.height - set.ink.height) / 2 + set.ink.maxY
        }
        let ellipsis = TextLine("…", font: set.font, kerning: 0).line
        let shown = CTLineCreateTruncatedLine(set.line, max(1, area.width - lead), .end, ellipsis) ?? set.line
        context.saveGState()
        context.setFillColor(color)
        context.textMatrix = .identity
        context.translateBy(x: lead, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(shown, context)
        context.restoreGState()
    }
}

/// A large, editable sample in one style.
private struct TypeTester: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @AppStorage("typeTester.size") private var size = 72.0
    @AppStorage("typeTester.alignment") private var alignment = Self.savedAlignment
    /// The space added between letters, in percent of the em, on top of the font's kerning: the page's own, not the
    /// overview's, which sets every font with its own spacing.
    @AppStorage("typeTester.tracking") private var tracking = Self.savedTracking
    /// What's typed over the text in a font's own script, on this family's page only (see `TesterText.shownText`).
    @State private var ownScript: (family: String, text: String)?

    var body: some View {
        let (face, weight) = model.previewStyle(of: family, weight: preview.weight)
        let variations = model.variations(for: family, face: face.id)
        VStack(spacing: 0) {
            TesterControls {
                stylePicker(isAdjusted: !variations.isEmpty)
                sliders
                buttons(hasAxes: !face.face.axes.isEmpty)
            }
            .padding(.top, 12)
            // A style on a server is read off the main thread first, in the room the editor takes at least.
            ReadingFonts(paths: [face.face.path]) {
                TesterText(family: family, face: face.face,
                           font: FontLoader.shared.font(face.face, size: size, weight: weight, variations: variations,
                                                        features: model.features(for: family)),
                           size: size, tracking: tracking, alignment: alignment, ownScript: $ownScript)
            }
            .frame(minHeight: 320)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func stylePicker(isAdjusted: Bool) -> some View {
        if family.faces.count > 1 {
            Picker("Style", selection: choice(isAdjusted: isAdjusted)) {
                Text("Automatic").tag(StyleChoice.automatic)
                Divider()
                ForEach(family.faces) { Text($0.face.styleName).tag(StyleChoice.style($0.id)) }
                if isAdjusted {
                    Divider()
                    Text("Custom").tag(StyleChoice.custom)
                }
            }
            .fixedSize()
            .help("Which style to show; Automatic shows the regular style, or a style the search names, like Italic")
            .layoutValue(key: TesterControls.RoleKey.self, value: .menu)
        }
    }

    /// The text's size and tracking, and its leading, which is Preview Options' too.
    @ViewBuilder
    private var sliders: some View {
        slider("Size", symbol: "textformat.size.larger", $size, range: 12...240, unit: " pt")
        slider("Tracking", symbol: "arrow.left.and.right.text.vertical", $tracking, range: -10...40, step: 0.5, unit: "%")
            .help("The space added between letters, in percent of the em, on top of the font’s kerning")
        slider("Leading", symbol: "arrow.up.and.down.text.horizontal",
               Binding { preview.lineSpacing } set: { preview.lineSpacing = $0 }, range: 80...250, step: 5, unit: "%")
            .help("The distance between lines, in percent of the size; the same as Leading in Preview Options")
    }

    /// A label, a slider that narrows where the row is short of room, and the value, which takes a number typed in too.
    /// The label is there as a word and as a symbol, as in a layout app's character panel, with the word as its tooltip
    /// (Preview Options' symbol is `textformat.size`, so Size's is the larger A alone); `TesterControls` shows one of them.
    private func slider(_ title: String, symbol: String, _ value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1,
                        unit: String) -> some View {
        Group {
            Text(title)
                .controlLabel(.word)
            // The word stands for it to VoiceOver, whichever is shown.
            Image(systemName: symbol).help(title).accessibilityHidden(true)
                .controlLabel(.symbol)
            // Ideally as narrow as at the least: the row they fit in is the menu's, while they fit at all.
            ValueSlider(value: value, range: range, step: step).frame(minWidth: 80, idealWidth: 80, maxWidth: .infinity)
                .layoutValue(key: TesterControls.RoleKey.self, value: .slider)
            ValueField(title, value: value, range: range, step: step, unit: unit, alignment: .leading)
                .layoutValue(key: TesterControls.RoleKey.self, value: .value)
        }
    }

    @ViewBuilder
    private func buttons(hasAxes: Bool) -> some View {
        IconSegments(title: "Alignment", options: SampleAlignment.allCases.map { ($0.title, $0.icon, $0) }, selection: $alignment)
            .help("Align left, center or right")
        if hasAxes {
            AxesButton()
        }
    }

    /// The Style menu's choice: Custom once an axis has been moved, until a style is chosen again.
    private func choice(isAdjusted: Bool) -> Binding<StyleChoice> {
        Binding {
            isAdjusted ? .custom : model.pageStyleID.map(StyleChoice.style) ?? .automatic
        } set: { choice in
            switch choice {
            case .automatic: model.pageStyleID = nil
            case .style(let id): model.pageStyleID = id
            case .custom: return
            }
            model.familyAxes[family.id] = nil
        }
    }
}

private enum StyleChoice: Hashable {
    case automatic
    case style(FaceID)
    case custom
}

/// Shows the Info panel at its Axes tab, or hides it when it's showing them.
private struct AxesButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            let isShowing = model.isInfoPresented && model.infoTab == .axes
            model.infoTab = .axes
            model.isInfoPresented = !isShowing
        } label: {
            Label("Axes", systemImage: "slider.horizontal.3")
        }
        .help("Move the style’s axes, in the Info panel")
    }
}

/// The type tester's controls: the Style menu, the sliders with their labels and values, the alignment and Axes buttons.
/// On one row wherever the sliders fit at their narrowest, with symbols for labels where the words don't fit, else the
/// sliders on a row of their own under the menu, with their words again: with the Info panel open, a narrow window has
/// too little for all of them, and squeezed further, the labels would wrap and the row grow. Either way the sliders share
/// all the width their row leaves, as long as each other, and the last value ends where the row does. Each slider's
/// label, slider and value are 8 pt apart, everything else 16. A layout of its own, not `ViewThatFits` over the three
/// ways, which made each of them afresh, menu, fields and buttons, whenever it weighed them again: with each letter typed
/// and each step of a slider, a third of a second.
private struct TesterControls: Layout {
    enum Role {
        case menu, word, symbol, slider, value, button
    }

    struct RoleKey: LayoutValueKey {
        static let defaultValue = Role.button
    }

    struct Cache {
        var roles: [Role]
        /// Each one's ideal size: the sliders' is their narrowest.
        var sizes: [CGSize]
    }

    private enum Arrangement {
        case words, symbols, twoRows
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(roles: subviews.map { $0[RoleKey.self] }, sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let arrangement = arrangement(width: proposed, cache)
        guard arrangement == .twoRows else {
            let row = oneRow(symbols: arrangement == .symbols, cache)
            return CGSize(width: proposed ?? width(of: row, cache), height: height(of: row, cache))
        }
        let (top, bottom) = twoRows(cache)
        return CGSize(width: max(proposed ?? 0, width(of: top, cache), width(of: bottom, cache)),
                      height: height(of: top, cache) + 10 + height(of: bottom, cache))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let arrangement = arrangement(width: bounds.width, cache)
        guard arrangement == .twoRows else {
            place(oneRow(symbols: arrangement == .symbols, cache), in: bounds, subviews, cache)
            return
        }
        let (top, bottom) = twoRows(cache)
        let topHeight = height(of: top, cache)
        // The menu at the left, the buttons at the right.
        let buttons = top.filter { cache.roles[$0] == .button }
        var x = bounds.minX
        for index in top {
            if index == buttons.first { x = bounds.maxX - width(of: buttons, cache) }
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY + topHeight / 2), anchor: .leading,
                                  proposal: ProposedViewSize(cache.sizes[index]))
            x += cache.sizes[index].width + 16
        }
        let rest = CGRect(x: bounds.minX, y: bounds.minY + topHeight + 10, width: bounds.width, height: height(of: bottom, cache))
        place(bottom, in: rest, subviews, cache)
    }

    /// `row` from the left of `bounds`, in the middle of its height, the sliders sharing what the rest leave; the labels
    /// not in it at no width, where they'd be, with nothing to see.
    private func place(_ row: [Int], in bounds: CGRect, _ subviews: Subviews, _ cache: Cache) {
        let sliders = row.filter { cache.roles[$0] == .slider }
        let extra = max(0, bounds.width - width(of: row, cache)) / CGFloat(max(1, sliders.count))
        var x = bounds.minX
        for index in subviews.indices {
            let size = cache.sizes[index]
            guard row.contains(index) else {
                if cache.roles[index] == .word || cache.roles[index] == .symbol {
                    subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                          proposal: ProposedViewSize(width: 0, height: size.height))
                }
                continue
            }
            if index != row.first { x += gap(before: index, cache) }
            let width = cache.roles[index] == .slider ? size.width + extra : size.width
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: width, height: size.height))
            x += width
        }
    }

    private func arrangement(width: CGFloat?, _ cache: Cache) -> Arrangement {
        guard let width else { return .words }
        if self.width(of: oneRow(symbols: false, cache), cache) <= width { return .words }
        if self.width(of: oneRow(symbols: true, cache), cache) <= width { return .symbols }
        return .twoRows
    }

    /// Everything, with the labels' words or their symbols.
    private func oneRow(symbols: Bool, _ cache: Cache) -> [Int] {
        cache.roles.indices.filter { cache.roles[$0] != (symbols ? .word : .symbol) }
    }

    /// The menu and buttons, then the sliders with their words.
    private func twoRows(_ cache: Cache) -> (top: [Int], bottom: [Int]) {
        let top = cache.roles.indices.filter { cache.roles[$0] == .menu || cache.roles[$0] == .button }
        return (top, cache.roles.indices.filter { [.word, .slider, .value].contains(cache.roles[$0]) })
    }

    private func gap(before index: Int, _ cache: Cache) -> CGFloat {
        cache.roles[index] == .slider || cache.roles[index] == .value ? 8 : 16
    }

    private func width(of row: [Int], _ cache: Cache) -> CGFloat {
        row.reduce(0) { width, index in width + (index == row.first ? 0 : gap(before: index, cache)) + cache.sizes[index].width }
    }

    private func height(of row: [Int], _ cache: Cache) -> CGFloat {
        row.map { cache.sizes[$0].height }.max() ?? 0
    }
}

private extension View {
    /// A slider's label in `TesterControls`, as a word or as a symbol: grey, and at no width, with nothing to see, when
    /// the controls show the other one.
    func controlLabel(_ role: TesterControls.Role) -> some View {
        foregroundStyle(.secondary)
            .fixedSize()
            .frame(minWidth: 0, alignment: .leading)
            .clipped()
            .layoutValue(key: TesterControls.RoleKey.self, value: role)
    }
}

/// The type tester's text, a view of its own so that typing updates it alone, not the controls above it.
private struct TesterText: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let face: FontFace
    let font: CTFont
    let size: Double
    let tracking: Double
    let alignment: SampleAlignment
    @Binding var ownScript: (family: String, text: String)?
    @Bindable private var store = TesterTextStore.shared

    private var text: String {
        get { store.text }
        nonmutating set { store.text = newValue }
    }

    var body: some View {
        let (text, defaultText) = shownText
        let kerning = size * tracking / 100
        let lineHeightPoints = size * preview.lineSpacing / 100
        let room = Self.room(for: text.wrappedValue, in: font, kerning: kerning, lineHeight: lineHeightPoints)
        // As tall as its lines, so it grows with the page instead of scrolling inside it (see `SampleEditor`).
        SampleEditor(text: text, defaultText: defaultText, font: font, kerning: kerning, lineHeight: lineHeightPoints,
                     alignment: alignment.paragraph, margin: 24, roomAbove: room.above, roomBelow: room.below) {
            FamilyMenu(families: [family], model: model)
        }
            .frame(minHeight: 280)
            .padding(.vertical, 20)
            // Out over the page's margins, for glyphs reaching past the lines' ends, like a swash at the start of one.
            .padding(.horizontal, -24)
            // Around the text too, which has it in its own menu (see `SampleEditor`).
            .contentShape(.rect)
            .contextMenu { FamilyMenu(families: [family], model: model) }
            // Text left empty as the last page closed, which the editor doesn't hear about.
            .onAppear {
                if self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.text = Self.defaultText }
            }
    }

    /// The text to show and type into: what's been typed, kept from one page to the next, or, for a font with none of its
    /// letters, like a Syriac font for Latin text, text in its own script, which typing changes on this page only. And
    /// what it goes back to when it's left empty.
    private var shownText: (text: Binding<String>, defaultText: String) {
        let sample = model.scriptSamples.text(text, for: face, long: true)
        guard sample != text else { return ($store.text, Self.defaultText) }
        let family = family.id
        let text = Binding {
            ownScript.flatMap { $0.family == family ? $0.text : nil } ?? sample
        } set: {
            ownScript = (family, $0)
        }
        return (text, sample)
    }

    /// Room above and below the lines for glyphs that reach past them, which would otherwise run into the controls
    /// above or what follows. The editor sets each baseline the font's descent above the bottom of its line, so all
    /// that the line spacing leaves out of the font's height goes above the first line, like a script font's
    /// ascenders at tight spacing, and below the last only what reaches lower than the font's descent. Its glyphs'
    /// own reach counts where it's greater than the font's (see `TextLine`).
    static func room(for text: String, in font: CTFont, kerning: Double, lineHeight: Double) -> (above: CGFloat, below: CGFloat) {
        let line = TextLine(text, font: font, kerning: kerning)
        let descent = CTFontGetDescent(font).rounded()
        return (max(0, line.ascent - (lineHeight - descent)).rounded(.up), max(0, line.descent - descent).rounded(.up))
    }

    static let defaultText = "Sphinx of black quartz, judge my vow."
}

/// The type tester's text, kept from one page to the next and for the next launch: saved a second after typing stops, and
/// as Cicero quits, rather than with each letter. SwiftUI draws every view with an `@AppStorage` again whenever anything
/// is saved to the defaults, whatever the key, so with each letter typed the browser behind the page was drawn again too,
/// and Settings and the Compare window where they were open.
@Observable
private final class TesterTextStore {
    static let shared = TesterTextStore()
    private static let key = "typeTester.text"

    var text: String {
        didSet { saveSoon() }
    }

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private init() {
        text = UserDefaults.standard.string(forKey: Self.key) ?? TesterText.defaultText
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TesterTextStore.shared.save() }
        }
    }

    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        UserDefaults.standard.set(text, forKey: Self.key)
    }
}

private extension TypeTester {
    /// What Preview Options' Tracking was set to, before it moved here.
    static var savedTracking: Double {
        UserDefaults.standard.object(forKey: "preview.tracking") as? Double ?? 0
    }

    /// Centered, unless the left alignment was chosen when there were only those two.
    static var savedAlignment: SampleAlignment {
        UserDefaults.standard.object(forKey: "typeTester.centered") as? Bool == false ? .leading : .center
    }
}

/// Every style with its own switch, laid out like a table. Not a Table, which scrolls by itself
/// rather than with the page. Each style is set as it is: the features chosen in the Info panel are for the text above.
/// Weight when the styles are of more than one (see `Family.stylesDifferInWeight`), then a column for each other axis
/// the styles sit apart on, like Width or one of the designer's own, in the order the styles are listed by (see
/// `Family.styleAxes`).
private struct StyleRows: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    var body: some View {
        let model = self.model
        let headerFont = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        let axes = family.styleAxes.map { (tag: $0.tag, name: $0.name, width: Self.width(fitting: [$0.name], in: headerFont)) }
        // As wide as the longest name, up to a point: some run to Serif Compressed Thin Italic.
        let styleWidth = Self.width(fitting: family.faces.map(\.face.styleName), in: .preferredFont(forTextStyle: .body), minimum: 140, maximum: 240)
        // The switch and the longest status its styles say, or come to with their switches, so turning one on or off
        // doesn't move the columns; the rest of the page's width goes to the samples.
        let statuses = family.faces.flatMap { style in
            [style.state.label, "Active", "Inactive"] + (style.app.map { [FaceState.appOnly($0).label] } ?? [])
        }
        let statusWidth = 26 + 8 + Self.width(fitting: statuses, in: .preferredFont(forTextStyle: .body))
        let showsWeight = family.stylesDifferInWeight
        VStack(spacing: 0) {
            row(styleWidth: styleWidth, statusWidth: statusWidth, showsWeight: showsWeight) {
                Text("Styles")
            } style: {
                Text("Style")
            } weight: {
                Text("Weight")
            } axes: {
                ForEach(axes, id: \.tag) { Text($0.name).frame(width: $0.width, alignment: .leading) }
            } status: {
                Text("Status")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            ForEach(family.faces) { style in
                Divider()
                row(styleWidth: styleWidth, statusWidth: statusWidth, showsWeight: showsWeight) {
                    FontText(text: model.scriptSamples.text(preview.text(for: family), for: style.face), face: style.face, size: 20,
                             weight: style.face.styleWeight)
                } style: {
                    Text(style.face.styleName)
                } weight: {
                    Text("\(Int(style.face.styleWeight.rounded()))").monospacedDigit().foregroundStyle(.secondary)
                } axes: {
                    ForEach(axes, id: \.tag) { axis in
                        Text(style.face.styleValue(on: axis.tag)?.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: axis.width, alignment: .leading)
                    }
                } status: {
                    HStack(spacing: 8) {
                        MiniSwitch(position: model.position(of: style), isEnabled: style.canActivate || style.canDeactivate) {
                            model.toggle(style, in: family)
                        }
                        Text(style.state.label).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(.rect)
                .contextMenu { StyleMenu(family: family, face: style, model: model) }
                // Onto a set in the sidebar, which takes just this style.
                .fontDrag { FontDrag(family: family.id, style: style.face.postScriptName) } preview: {
                    FontText(text: "\(family.name) \(style.face.styleName)", face: style.face, size: 20, weight: style.face.styleWeight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.background, in: .rect(cornerRadius: 8))
                }
            }
            Divider()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// As wide as the widest of `texts` set in `font`, within `minimum` and `maximum`.
    private static func width(fitting texts: [String], in font: NSFont, minimum: CGFloat = 56, maximum: CGFloat = .infinity) -> CGFloat {
        let widest = texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(max(minimum, widest.rounded(.up)), maximum)
    }

    private func row(styleWidth: CGFloat, statusWidth: CGFloat, showsWeight: Bool,
                     @ViewBuilder preview: () -> some View, @ViewBuilder style: () -> some View,
                     @ViewBuilder weight: () -> some View, @ViewBuilder axes: () -> some View,
                     @ViewBuilder status: () -> some View) -> some View {
        HStack(spacing: 12) {
            preview().frame(maxWidth: .infinity, alignment: .leading)
            style().lineLimit(1).frame(width: styleWidth, alignment: .leading)
            if showsWeight { weight().frame(width: 56, alignment: .leading) }
            axes().lineLimit(1)
            status().frame(width: statusWidth, alignment: .leading)
        }
    }
}
