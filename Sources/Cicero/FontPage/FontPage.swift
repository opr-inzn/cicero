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
        let face = family.face(nearestWeight: preview.weight).face
        // Usually ready before the page opens: the browser starts on a family when it's selected.
        let content = model.pageContents.content(of: face) ?? loaded.flatMap { $0.face == face.id ? $0.content : nil }
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
                    if let content {
                        if let glyphColumns {
                            GlyphsSection(family: family, columns: glyphColumns, sections: content.glyphs, characterCount: content.characterCount,
                                          ligatures: content.ligatures, ligatureCharacters: content.ligatureCharacters)
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
    /// nil follows the preview weight.
    @State private var styleID: FaceID?
    /// The axes moved on a variable style's sliders since it was chosen.
    @State private var adjusted: AdjustedAxes?

    var body: some View {
        let chosen = family.faces.first { $0.id == styleID }
        let face = chosen ?? family.face(nearestWeight: preview.weight)
        let weight = chosen.map(\.face.styleWeight) ?? preview.weight
        let variations = adjusted.flatMap { $0.face == face.id ? $0.values : nil } ?? [:]
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
                // Here rather than after the sliders, where it could start a line of its own and push the sample down.
                if !variations.isEmpty {
                    Button("Reset") { adjusted = nil }
                        .help("Back to the style’s own values")
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("Size").foregroundStyle(.secondary)
                    ValueSlider(value: $size, range: 12...240).frame(width: 160)
                    ValueField("Size", value: $size, range: 12...240, unit: " pt")
                }
                IconSegments(title: "Alignment", options: SampleAlignment.allCases.map { ($0.title, $0.icon, $0) }, selection: $alignment)
                    .help("Align left, center or right")
            }
            .padding(.top, 12)
            // A style on a server is read off the main thread first, in the room the editor takes at least.
            ReadingFonts(paths: [face.face.path]) {
                let ctFont = FontLoader.shared.font(face.face, size: size, weight: weight, variations: variations,
                                                    features: model.features(for: family))
                let axes = FontLoader.shared.axes(of: face.face)
                VStack(spacing: 0) {
                    if !axes.isEmpty {
                        AxisSliders(axes: axes, values: FontLoader.variation(of: ctFont)) { tag, value in
                            var values = variations
                            values[tag] = value
                            adjusted = AdjustedAxes(face: face.id, values: values)
                        }
                        .padding(.top, 10)
                    }
                    editor(ctFont)
                }
            }
            .frame(minHeight: 320)
        }
        .padding(.horizontal, 24)
    }

    /// The Style menu's choice: Custom once an axis has been moved, until a style is chosen again.
    private func choice(isAdjusted: Bool) -> Binding<StyleChoice> {
        Binding {
            isAdjusted ? .custom : styleID.map(StyleChoice.style) ?? .automatic
        } set: { choice in
            switch choice {
            case .automatic: styleID = nil
            case .style(let id): styleID = id
            case .custom: return
            }
            adjusted = nil
        }
    }
}

private enum StyleChoice: Hashable {
    case automatic
    case style(FaceID)
    case custom
}

/// Where a variable style's sliders put the axes they moved, for that style only.
private struct AdjustedAxes {
    let face: FaceID
    let values: [String: Double]
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

/// A slider for each axis of a variable style, at the place the sample is drawn: the style's own until one is moved,
/// and the optical size, which follows the sample's size until it's moved itself.
private struct AxisSliders: View {
    let axes: [AxisRange]
    let values: [String: Double]
    let set: (String, Double) -> Void

    var body: some View {
        // Every name as wide as the longest, up to a point, so the sliders line up when they run over several lines.
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let nameWidth = min(axes.map { ceil(($0.name as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0, 140)
        FlowLayout(spacing: 28, lineSpacing: 6) {
            ForEach(axes) { axis in
                let value = Binding { values[axis.tag] ?? axis.defaultValue } set: { set(axis.tag, $0) }
                let range = axis.minimum...axis.maximum
                HStack(spacing: 8) {
                    Text(axis.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: nameWidth, alignment: .leading)
                    ValueSlider(value: value, range: range, step: axis.step)
                        .frame(width: 160)
                        .accessibilityLabel(axis.name)
                    ValueField(axis.name, value: value, range: range, step: axis.step)
                }
                .help("\(axis.name) (\(axis.tag)), from \(axis.minimum.formatted()) to \(axis.maximum.formatted()), \(axis.defaultValue.formatted()) by default")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension AxisRange {
    /// Whole units, or tenths or hundredths on an axis that spans 20 or less, like a slant from −12 to 0.
    var step: Double {
        let span = maximum - minimum
        return span > 20 ? 1 : span > 2 ? 0.1 : 0.01
    }
}

/// Every style with its own switch, laid out like a table. Not a Table, which scrolls by itself
/// rather than with the page.
private struct StyleRows: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    var body: some View {
        let model = self.model
        let features = model.features(for: family)
        VStack(spacing: 0) {
            row {
                Text("Preview")
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
                    FontText(text: preview.text(for: family), face: style.face, size: 20, weight: style.face.styleWeight, features: features)
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
                    FontText(text: "\(family.name) \(style.face.styleName)", face: style.face, size: 20,
                             weight: style.face.styleWeight, features: features)
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
