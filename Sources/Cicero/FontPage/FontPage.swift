import AppKit
import CiceroCore
import SwiftUI

struct FontPage: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let familyID: String
    @State private var glyphColumns: Int?
    @State private var loaded: (face: FaceID, content: PageContent)?

    private struct Reading: Equatable {
        let face: FaceID
        let generation: Int
    }
    @FocusState private var focused: Bool
    @State private var position = ScrollPosition()
    @State private var keeper = TopRowKeeper()

    var body: some View {
        if let family = model.family(familyID) {
            page(family)
        } else {
            EmptyState("Font Not Available", systemImage: "textformat",
                       description: Text("This font is no longer in your library."))
                .onExitCommand { model.openFamilyID = nil }
        }
    }

    private func page(_ family: Family) -> some View {
        let face = model.previewStyle(of: family, weight: preview.weight).face.face
        let ready = model.pageContents.content(of: face) ?? loaded.flatMap { $0.face == face.id ? $0.content : nil }
        let shown = ready.map { (face: face, content: $0) } ?? loaded.flatMap { last in
            family.faces.first { $0.id == last.face }.map { (face: $0.face, content: last.content) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Header(family: family)
                Divider()
                TypeTester(family: family)
                if family.faces.count > 1 {
                    StyleRows(family: family)
                }
                // Only rows of about one height go in this lazy stack: it guesses the height of rows it hasn't placed from those it has, and with the styles in it too the guesses swung so far that the page laid itself out again and again at full CPU.
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let shown {
                        if let glyphColumns {
                            let content = shown.content
                            GlyphsSection(family: family, face: shown.face, columns: glyphColumns, sections: content.glyphs,
                                          characterCount: content.characterCount, ligatures: content.ligatures,
                                          ligatureCharacters: content.ligatureCharacters, alternates: content.alternates,
                                          generation: content.generation)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 56)
                    }
                }
            }
            .modifier(GlyphColumnsReader(columns: $glyphColumns))
            .environment(\.topRowKeeper, keeper)
            .coordinateSpace(.named(TopRowKeeper.space))
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { [keeper] in keeper.visibleTop = $1 }
        .onAppear { [keeper] in keeper.scrollTo = { position.scrollTo(y: $0) } }
        .task(id: FileFace(family.face(nearestWeight: preview.weight).face)) {
            model.pageFeatures.prepare(family.face(nearestWeight: preview.weight).face)
        }
        // Here, not on a row of the lazy stack, which wouldn't see a change of style while scrolled out of view.
        .task(id: Reading(face: face.id, generation: FontLoader.shared.generation(of: face.path))) {
            let content = await model.pageContents.content(loading: face)
            guard !Task.isCancelled else { return }
            loaded = (face.id, content)
        }
        .background(Color.canvas)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .defaultFocus($focused, true)
        .navigationTitle(family.name)
        .toolbar {
            ToolbarCapsule { InfoButton() }
            ToolbarGap()
        }
        .onExitCommand { model.openFamilyID = nil }
    }
}

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

    private var activation: String {
        let partly = family.faces.count { if case .appOnly = $0.state { true } else { false } }
        let counts = [(family.activeCount, "active"), (partly, "partly active"), (family.faces.count - family.activeCount - partly, "inactive")]
        return counts.filter { $0.0 > 0 }.map { "\($0.0.plain) \($0.1)" }.joined(separator: " · ")
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

private struct FamilyName: View {
    let name: String
    let face: FontFace
    static let size: CGFloat = 34
    static let line: CGFloat = 41
    static let above: CGFloat = 16
    static let below: CGFloat = 4
    static let lead: CGFloat = 12

    var body: some View {
        ReadingFonts(paths: [face.path]) {
            Canvas { context, area in
                let color = Color.ink.resolve(in: context.environment).cgColor
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

private struct TypeTester: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @AppStorage("typeTester.size") private var size = 72.0
    @AppStorage("typeTester.alignment") private var alignment = Self.savedAlignment
    @AppStorage("typeTester.tracking") private var tracking = Self.savedTracking
    @State private var ownScript: OwnScriptText?
    @State private var caseChange: CaseChange?

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
            ReadingFonts(paths: [face.face.path]) {
                TesterText(family: family, face: face.face,
                           font: FontLoader.shared.font(face.face, size: size, weight: weight, variations: variations,
                                                        features: model.features(for: family)),
                           size: size, tracking: tracking, alignment: alignment, caseChange: caseChange, ownScript: $ownScript)
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

    @ViewBuilder
    private var sliders: some View {
        slider("Size", symbol: "textformat", $size, range: 12...240, unit: " pt")
        slider("Tracking", symbol: "arrow.left.and.right.text.vertical", $tracking, range: -10...40, step: 0.5, unit: "%")
            .help("The space added between letters, in percent of the em, on top of the font’s kerning")
        slider("Leading", symbol: "arrow.up.and.down.text.horizontal",
               Binding { preview.lineSpacing } set: { preview.lineSpacing = $0 }, range: PreviewSettings.lineSpacings, step: 5, unit: "%")
            .help("The distance between lines, in percent of the size")
    }

    private func slider(_ title: String, symbol: String, _ value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1,
                        unit: String) -> some View {
        Group {
            Image(systemName: symbol)
                .help(title)
                .accessibilityLabel(title)
                .foregroundStyle(.secondary)
                .fixedSize()
                .layoutValue(key: TesterControls.RoleKey.self, value: .label)
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
        CaseButtons { caseChange = .next($0, after: caseChange) }
        if hasAxes {
            AxesButton()
        }
    }

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

private struct TesterControls: Layout {
    enum Role {
        case menu, label, slider, value, button
    }

    struct RoleKey: LayoutValueKey {
        static let defaultValue = Role.button
    }

    struct Cache {
        var roles: [Role]
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(roles: subviews.map { $0[RoleKey.self] }, sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        guard !fitsOneRow(width: proposed, cache) else {
            let row = Array(cache.roles.indices)
            return CGSize(width: proposed ?? width(of: row, cache), height: height(of: row, cache))
        }
        let (top, bottom) = twoRows(cache)
        return CGSize(width: max(proposed ?? 0, width(of: top, cache), width(of: bottom, cache)),
                      height: height(of: top, cache) + 10 + height(of: bottom, cache))
    }

    static let longestSlider: CGFloat = 180
    static let groupGap: CGFloat = 16

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !fitsOneRow(width: bounds.width, cache) else {
            place(Array(cache.roles.indices), in: bounds, subviews, cache, grouped: true)
            return
        }
        let (top, bottom) = twoRows(cache)
        let topHeight = height(of: top, cache)
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

    private func place(_ row: [Int], in bounds: CGRect, _ subviews: Subviews, _ cache: Cache, grouped: Bool = false) {
        let sliders = row.filter { cache.roles[$0] == .slider }
        let room = max(0, bounds.width - width(of: row, cache))
        var extra = room / CGFloat(max(1, sliders.count))
        var before: CGFloat = 0, after: CGFloat = 0
        let group = row.filter { [.label, .slider, .value].contains(cache.roles[$0]) }
        if grouped, let first = group.first, let last = group.last, let slider = sliders.first {
            extra = min(extra, max(0, Self.longestSlider - cache.sizes[slider].width))
            let left = room - extra * CGFloat(sliders.count)
            switch (first != row.first, last != row.last) {
            case (true, true): (before, after) = (min(left / 2, Self.groupGap), min(left / 2, Self.groupGap))
            case (false, true): after = min(left, Self.groupGap)
            case (true, false): before = min(left, Self.groupGap)
            case (false, false): break
            }
            extra += (left - before - after) / CGFloat(sliders.count)
        }
        let afterGroup = group.last.flatMap { last in row.drop { $0 != last }.dropFirst().first }
        var x = bounds.minX
        for index in row {
            let size = cache.sizes[index]
            if let previous = row.last(where: { $0 < index }) { x += gap(between: previous, and: index, cache) }
            if index == group.first { x += before }
            if index == afterGroup { x += after }
            let width = cache.roles[index] == .slider ? size.width + extra : size.width
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: width, height: size.height))
            x += width
        }
    }

    private func fitsOneRow(width: CGFloat?, _ cache: Cache) -> Bool {
        guard let width else { return true }
        return self.width(of: Array(cache.roles.indices), cache) <= width
    }

    private func twoRows(_ cache: Cache) -> (top: [Int], bottom: [Int]) {
        let top = cache.roles.indices.filter { cache.roles[$0] == .menu || cache.roles[$0] == .button }
        return (top, cache.roles.indices.filter { [.label, .slider, .value].contains(cache.roles[$0]) })
    }

    private func gap(between previous: Int, and index: Int, _ cache: Cache) -> CGFloat {
        let inGroup = { [.label, .slider, .value].contains(cache.roles[$0]) }
        if inGroup(previous) != inGroup(index) { return 32 }
        return cache.roles[index] == .slider || cache.roles[index] == .value ? 8 : 16
    }

    private func width(of row: [Int], _ cache: Cache) -> CGFloat {
        zip(row, row.dropFirst()).reduce(row.map { cache.sizes[$0].width }.reduce(0, +)) { width, pair in
            width + gap(between: pair.0, and: pair.1, cache)
        }
    }

    private func height(of row: [Int], _ cache: Cache) -> CGFloat {
        row.map { cache.sizes[$0].height }.max() ?? 0
    }
}

private struct TesterText: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let face: FontFace
    let font: CTFont
    let size: Double
    let tracking: Double
    let alignment: SampleAlignment
    let caseChange: CaseChange?
    @Binding var ownScript: OwnScriptText?
    @Bindable private var store = TesterTextStore.shared

    private var text: String {
        get { store.text }
        nonmutating set { store.text = newValue }
    }

    var body: some View {
        let (text, glyphs, defaultText) = shownText
        let kerning = size * tracking / 100
        let lineHeightPoints = size * preview.lineSpacing / 100
        let room = Self.room(for: text.wrappedValue, glyphs: shownGlyphs(glyphs.wrappedValue), in: font, kerning: kerning,
                             lineHeight: lineHeightPoints)
        let lowered = Self.lowered(in: font, room: room)
        SampleEditor(text: text, glyphs: glyphs, defaultText: defaultText, family: family.id, face: face, font: font,
                     kerning: kerning, lineHeight: lineHeightPoints, alignment: alignment.paragraph, margin: 24,
                     roomAbove: room.above, roomBelow: room.below, caseChange: caseChange) {
            FamilyMenu(families: [family], model: model)
        }
            .frame(minHeight: 280)
            .padding(.top, Self.padding + lowered)
            .padding(.bottom, Self.padding - lowered)
            .padding(.horizontal, -24)
            .contentShape(.rect)
            .contextMenu { FamilyMenu(families: [family], model: model) }
            .onAppear {
                if self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.text = Self.defaultText
                    store.glyphs = []
                }
            }
    }

    private var shownText: (text: Binding<String>, glyphs: Binding<[SampleGlyphRun]>, defaultText: String) {
        let sample = model.scriptSamples.text(text, for: face, long: true)
        guard sample != text else { return ($store.text, $store.glyphs, Self.defaultText) }
        let family = family.id
        func own() -> OwnScriptText? { ownScript.flatMap { $0.family == family ? $0 : nil } }
        let text = Binding { own()?.text ?? sample } set: {
            ownScript = OwnScriptText(family: family, text: $0, glyphs: own()?.glyphs ?? [])
        }
        let glyphs = Binding { own()?.glyphs ?? [] } set: {
            ownScript = OwnScriptText(family: family, text: own()?.text ?? sample, glyphs: $0)
        }
        return (text, glyphs, sample)
    }

    private func shownGlyphs(_ runs: [SampleGlyphRun]) -> [CGGlyph] {
        runs.compactMap { $0.glyph.family == family.id ? $0.glyph.glyph(in: font, face: face) : nil }
    }

    static func room(for text: String, glyphs: [CGGlyph], in font: CTFont, kerning: Double,
                     lineHeight: Double) -> (above: CGFloat, below: CGFloat) {
        let line = TextLine(text, font: font, kerning: kerning)
        var ascent = line.ascent, descent = line.descent
        if !glyphs.isEmpty {
            let ink = CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, nil, glyphs.count)
            ascent = max(ascent, ink.maxY.rounded(.up))
            descent = max(descent, -ink.minY.rounded(.down))
        }
        let fontAscent = CTFontGetAscent(font).rounded(), fontDescent = CTFontGetDescent(font).rounded()
        let raise = (lineHeight - fontAscent - fontDescent) / 2
        return (max(0, ascent - fontAscent - raise).rounded(.up), max(0, descent - fontDescent - raise).rounded(.up))
    }

    static let padding: CGFloat = 20
    static let titleBelow: CGFloat = 12 + 6 + 3

    static func lowered(in font: CTFont, room: (above: CGFloat, below: CGFloat)) -> CGFloat {
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        let capHeight = CTFontGetCapHeight(font)
        let aboveCapitals = capHeight > 0 && capHeight <= ascent ? ascent - capHeight : descent
        let lowered = (descent - aboveCapitals + room.below - room.above + titleBelow) / 2
        return min(padding, max(-padding, lowered))
    }

    static let defaultText = "Sphinx of black quartz, judge my vow."
}

struct OwnScriptText {
    let family: String
    let text: String
    let glyphs: [SampleGlyphRun]
}

@Observable
private final class TesterTextStore {
    static let shared = TesterTextStore()
    private static let key = "typeTester.text"
    private static let glyphsKey = "typeTester.glyphs"

    var text: String {
        didSet { saveSoon() }
    }
    var glyphs: [SampleGlyphRun] {
        didSet { saveSoon() }
    }

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private init() {
        let text = (UserDefaults.standard.string(forKey: Self.key) ?? TesterText.defaultText) as NSString
        self.text = text as String
        let saved = UserDefaults.standard.data(forKey: Self.glyphsKey).flatMap { try? JSONDecoder().decode([SampleGlyphRun].self, from: $0) }
        glyphs = (saved ?? []).filter { NSMaxRange($0.range) <= text.length && text.substring(with: $0.range) == $0.glyph.characters }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TesterTextStore.shared.save() }
        }
    }

    // Not with each letter: SwiftUI draws every view with an @AppStorage again whenever anything is saved to the defaults, whatever the key.
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
        if glyphs.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.glyphsKey)
        } else if let data = try? JSONEncoder().encode(glyphs) {
            UserDefaults.standard.set(data, forKey: Self.glyphsKey)
        }
    }
}

private extension TypeTester {
    static var savedTracking: Double {
        UserDefaults.standard.object(forKey: "preview.tracking") as? Double ?? 0
    }

    static var savedAlignment: SampleAlignment {
        UserDefaults.standard.object(forKey: "typeTester.centered") as? Bool == false ? .leading : .center
    }
}

private struct GlyphColumnsReader: ViewModifier {
    @Binding var columns: Int?
    @Environment(\.infoPanelShown) private var infoShown
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        let isSliding = (infoShown > 0 && infoShown < 1) || SidebarRoom.shared.isSliding
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                self.width = width
                // Not while a panel slides: the room it takes is measured a frame apart from the page's width, and in between the count would flicker.
                if !isSliding || columns == nil { columns = resting(width) }
            }
            .onChange(of: isSliding) { _, sliding in
                if !sliding, let width { columns = resting(width) }
            }
    }

    private func resting(_ width: CGFloat) -> Int {
        GlyphsSection.columns(fitting: width + InfoPanelOverlay.room(shown: infoShown, scale: scale) - SidebarRoom.shared.hiddenWidth)
    }
}

private struct StyleRows: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        let model = self.model
        let headerFont = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        let axes = family.styleAxes.map { (tag: $0.tag, name: $0.name, width: Self.width(fitting: [$0.name], in: headerFont)) }
        let styleWidth = Self.width(fitting: family.faces.map(\.face.styleName), in: .preferredFont(forTextStyle: .body), minimum: 140, maximum: 240)
        let statuses = family.faces.flatMap { style in
            [style.state.label, "Active", "Inactive"] + (style.app.map { [FaceState.appOnly($0).label] } ?? [])
        }
        let statusWidth = 26 + 8 + Self.width(fitting: statuses, in: .preferredFont(forTextStyle: .body))
        let showsWeight = family.stylesDifferInWeight
        // Not lazy: a lazy stack guesses the height of rows it hasn't made from those it has, and as each row is as high as its own font's line, the page below moved by its guesses, and with it the glyph row `TopRowKeeper` keeps at the top.
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
                    FontText(text: model.scriptSamples.text(family.name, for: style.face), face: style.face, size: 20,
                             weight: style.face.styleWeight)
                        .foregroundStyle(Color.ink)
                } style: {
                    Text(style.face.styleName)
                } weight: {
                    Text(Int(style.face.styleWeight.rounded()).formatted(.number.grouping(.never))).monospacedDigit().foregroundStyle(.secondary)
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
