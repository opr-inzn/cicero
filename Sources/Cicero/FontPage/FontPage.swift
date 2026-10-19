import CiceroCore
import SwiftUI

/// One family's page, pushed over the browser: a type tester, every style, then the glyphs, the ligatures among them,
/// one under the other.
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
                FontText(text: family.name, face: family.regular.face, size: 34)
                    .truncationMode(.tail)
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
                // Creative Cloud turns Adobe Fonts on and off, not Cicero.
                if hasAdobeFonts {
                    Button("Manage in Creative Cloud") { CreativeCloud.open() }
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

/// A large, editable sample in one style.
private struct TypeTester: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @AppStorage("typeTester.text") private var text = "Sphinx of black quartz, judge my vow."
    @AppStorage("typeTester.size") private var size = 72.0
    @AppStorage("typeTester.alignment") private var alignment = Self.savedAlignment

    var body: some View {
        let (face, weight) = model.previewStyle(of: family, weight: preview.weight)
        let variations = model.variations(for: family, face: face.id)
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if family.faces.count > 1 {
                    Picker("Style", selection: choice(isAdjusted: !variations.isEmpty)) {
                        Text("Automatic").tag(StyleChoice.automatic)
                        Divider()
                        ForEach(family.faces) { Text($0.face.styleName).tag(StyleChoice.style($0.id)) }
                        if !variations.isEmpty {
                            Divider()
                            Text("Custom").tag(StyleChoice.custom)
                        }
                    }
                    .fixedSize()
                    .help("Which style to show; Automatic follows the preview weight")
                }
                Spacer()
                // Where the row is short of room, the slider narrows; squeezed, the label would wrap and the row grow.
                HStack(spacing: 8) {
                    Text("Size").foregroundStyle(.secondary).fixedSize()
                    ValueSlider(value: $size, range: 12...240).frame(minWidth: 80, maxWidth: 160)
                    ValueField("Size", value: $size, range: 12...240, unit: " pt")
                }
                .layoutPriority(1)
                IconSegments(title: "Alignment", options: SampleAlignment.allCases.map { ($0.title, $0.icon, $0) }, selection: $alignment)
                    .help("Align left, center or right")
                if !face.face.axes.isEmpty {
                    AxesButton()
                }
            }
            .padding(.top, 12)
            // A style on a server is read off the main thread first, in the room the editor takes at least.
            ReadingFonts(paths: [face.face.path]) {
                editor(FontLoader.shared.font(face.face, size: size, weight: weight, variations: variations,
                                              features: model.features(for: family)))
            }
            .frame(minHeight: 320)
        }
        .padding(.horizontal, 24)
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

private extension TypeTester {
    @ViewBuilder
    func editor(_ ctFont: CTFont) -> some View {
        let font = Font(ctFont)
        let kerning = preview.kerning(at: size)
        let lineHeight = preview.lineHeight(at: size)
        let lineHeightPoints = size * preview.lineSpacing / 100
        let overhang = Self.overhang(of: text, in: ctFont, kerning: kerning, lineHeight: lineHeightPoints)
        // An invisible copy of the text sets the editor's height, so it grows with the page instead of
        // scrolling inside it. The 5 pt matches the editor's padding at each end of a line.
        Text(text.hasSuffix("\n") || text.isEmpty ? text + " " : text)
            .font(font)
            .kerning(kerning)
            .lineHeight(lineHeight)
            .multilineTextAlignment(alignment.text)
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            .padding(.horizontal, 5)
            .padding(.vertical, overhang)
            .hidden()
            .overlay {
                SampleEditor(text: $text, font: ctFont, kerning: kerning, lineHeight: lineHeightPoints,
                             alignment: alignment.paragraph, overhang: overhang) {
                    FamilyMenu(families: [family], model: model)
                }
            }
            .frame(minHeight: 280)
            .padding(.vertical, 20)
            // Around the text too, which has it in its own menu (see `SampleEditor`).
            .contentShape(.rect)
            .contextMenu { FamilyMenu(families: [family], model: model) }
    }

    /// Room above and below the lines for glyphs that reach past them, which the editor would cut off at its
    /// edges: as much of the text's height as the line spacing leaves out, at either end, as the editor may
    /// put it either side, and a quarter of the size more, as it sets its lines a few points lower than the
    /// copy that sizes it.
    static func overhang(of text: String, in font: CTFont, kerning: Double, lineHeight: Double) -> CGFloat {
        let line = TextLine(text, font: font, kerning: kerning)
        return max(0, line.ascent + line.descent - lineHeight) + CTFontGetSize(font) / 4
    }

    /// Centered, unless the left alignment was chosen when there were only those two.
    static var savedAlignment: SampleAlignment {
        UserDefaults.standard.object(forKey: "typeTester.centered") as? Bool == false ? .leading : .center
    }
}

/// Every style with its own switch, laid out like a table. Not a Table, which scrolls by itself
/// rather than with the page. Each style is set as it is: the features chosen in the Info panel are for the text above.
private struct StyleRows: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    var body: some View {
        let model = self.model
        VStack(spacing: 0) {
            row {
                Text("Styles")
            } style: {
                Text("Style")
            } weight: {
                Text("Weight")
            } status: {
                Text("Status")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            ForEach(family.faces) { style in
                Divider()
                row {
                    FontText(text: preview.text(for: family), face: style.face, size: 20, weight: style.face.styleWeight)
                } style: {
                    Text(style.face.styleName)
                } weight: {
                    Text("\(Int(style.face.styleWeight.rounded()))").monospacedDigit().foregroundStyle(.secondary)
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
                .draggable(FontDrag(family: family.id, style: style.face.postScriptName)) {
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

    private func row(@ViewBuilder preview: () -> some View, @ViewBuilder style: () -> some View,
                     @ViewBuilder weight: () -> some View, @ViewBuilder status: () -> some View) -> some View {
        HStack(spacing: 12) {
            preview().frame(maxWidth: .infinity, alignment: .leading)
            style().lineLimit(1).frame(width: 140, alignment: .leading)
            weight().frame(width: 56, alignment: .leading)
            status().frame(width: 210, alignment: .leading)
        }
    }
}
