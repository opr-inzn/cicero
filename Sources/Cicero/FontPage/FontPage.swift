import CiceroCore
import SwiftUI

/// One family's page, pushed over the browser: a type tester, every style, the ligatures, then the glyphs, one
/// under the other.
struct FontPage: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let familyID: String
    @State private var glyphColumns: Int?
    @State private var glyphs: [GlyphSection]?
    @State private var ligatureColumns: Int?
    /// The style's ligatures; nil while loading.
    @State private var ligatures: [LigatureGroup]?

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
        ScrollView {
            // Lazy for the glyphs, which can run to thousands of cells; their block headers stay pinned.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Header(family: family)
                Divider()
                TypeTester(family: family)
                // With one style the tester already shows it.
                if family.faces.count > 1 {
                    StyleRows(family: family)
                }
                if let ligatures, !ligatures.isEmpty {
                    LigaturesSection(face: family.face(nearestWeight: preview.weight).face, columns: ligatureColumns, groups: ligatures)
                }
                GlyphsSection(family: family, columns: glyphColumns, sections: glyphs)
            }
            // The stack's width is the scroll view's less the Info panel's inset, never the rows', so this settles
            // at once; only a change in the count redraws the glyphs.
            .onGeometryChange(for: Int.self) { GlyphsSection.columns(fitting: $0.size.width) } action: { glyphColumns = $0 }
            .onGeometryChange(for: Int.self) { LigaturesSection.columns(fitting: $0.size.width) } action: { ligatureColumns = $0 }
        }
        // Here, not on a row of the lazy stack, which wouldn't see a change of style while scrolled out of view.
        .task(id: family.face(nearestWeight: preview.weight).face.id) {
            let face = family.face(nearestWeight: preview.weight).face
            glyphs = nil
            ligatures = nil
            ligatures = await Task.detached(priority: .userInitiated) { LigatureGroup.read(face) }.value
            let ranges = await model.coverage.coverage(computing: face).scalars
            glyphs = await Task.detached(priority: .userInitiated) { GlyphSection.sections(for: ranges) }.value
        }
        .background(Color.canvas)
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
                } else if !family.hasActivatable {
                    Button("Deactivate") {}
                        .disabled(true)
                        .help(lockedReason)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var summary: String {
        var parts: [String] = []
        if let foundry = model.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.format.rawValue)
        if family.isVariable { parts.append("Variable") }
        parts.append("\(family.stylesLabel) · \(family.activeCount) activated")
        return parts.joined(separator: " · ")
    }

    private var lockedReason: String {
        switch family.faces.first?.state.source {
        case .macOS: "Installed with macOS, so it can’t be turned off"
        case .allUsers: "Installed for all users; an administrator has to remove it"
        case .app: "Comes with an app, which manages it"
        case .adobeFonts: "Managed by Adobe Creative Cloud"
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

    var body: some View {
        let chosen = family.faces.first { $0.id == styleID }
        let face = chosen ?? family.face(nearestWeight: preview.weight)
        let weight = chosen.map(\.face.styleWeight) ?? preview.weight
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if family.faces.count > 1 {
                    Picker("Style", selection: $styleID) {
                        Text("Automatic").tag(FaceID?.none)
                        Divider()
                        ForEach(family.faces) { Text($0.face.styleName).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                    .help("Which style to show; Automatic follows the preview weight")
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("Size").foregroundStyle(.secondary)
                    ValueSlider(value: $size, range: 12...240).frame(width: 160)
                    ValueField("Size", value: $size, range: 12...240, unit: " pt")
                }
                Picker("Alignment", selection: $alignment) {
                    ForEach(SampleAlignment.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .labelsHidden()
                .fixedSize()
                .help("Align left, center or right")
            }
            .padding(.top, 12)
            let font = Font(FontLoader.shared.font(face.face, size: size, weight: weight, features: model.features(for: family)))
            let kerning = preview.kerning(at: size)
            let lineHeight = preview.lineHeight(at: size)
            // An invisible copy of the text sets the editor's height, so it grows with the page instead of
            // scrolling inside it. The 5 pt matches the editor's padding at each end of a line.
            Text(text.hasSuffix("\n") || text.isEmpty ? text + " " : text)
                .font(font)
                .kerning(kerning)
                .lineHeight(lineHeight)
                .multilineTextAlignment(alignment.text)
                .frame(maxWidth: .infinity, alignment: alignment.frame)
                .padding(.horizontal, 5)
                .hidden()
                .overlay {
                    TextEditor(text: $text)
                        .font(font)
                        .kerning(kerning)
                        .lineHeight(lineHeight)
                        .multilineTextAlignment(alignment.text)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                }
                .frame(minHeight: 280)
                .padding(.vertical, 20)
        }
        .padding(.horizontal, 24)
    }
}

private extension TypeTester {
    /// Centered, unless the left alignment was chosen when there were only those two.
    static var savedAlignment: SampleAlignment {
        UserDefaults.standard.object(forKey: "typeTester.centered") as? Bool == false ? .leading : .center
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
