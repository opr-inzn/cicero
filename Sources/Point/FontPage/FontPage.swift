import PointCore
import SwiftUI

enum FontPageTab: String, CaseIterable {
    case text, styles, glyphs

    var title: String {
        switch self {
        case .text: "Text"
        case .styles: "Styles"
        case .glyphs: "Glyphs"
        }
    }
}

/// One family's page, pushed over the browser.
struct FontPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fontPage.tab") private var tab: FontPageTab = .text
    let familyID: String

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
        VStack(spacing: 0) {
            Header(family: family)
            Divider()
            switch shownTab(family) {
            case .text: TextTab(family: family)
            case .styles: StylesTab(family: family)
            case .glyphs: GlyphsTab(family: family)
            }
        }
        .background(Color.canvas)
        .navigationTitle(family.name)
        .toolbar {
            ToolbarItem {
                Picker("View", selection: Binding(get: { shownTab(family) }, set: { tab = $0 })) {
                    ForEach(tabs(family), id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarSpacer(.fixed)
            ToolbarItem { PreviewOptionsButton() }
            ToolbarSpacer(.fixed)
            ToolbarItem { InfoButton() }
        }
        .modifier(InfoPanelColumn())
        .onExitCommand { model.openFamilyID = nil }
    }

    /// Styles only has something to show when there's more than one.
    private func tabs(_ family: Family) -> [FontPageTab] {
        family.faces.count > 1 ? FontPageTab.allCases : [.text, .glyphs]
    }

    private func shownTab(_ family: Family) -> FontPageTab {
        tabs(family).contains(tab) ? tab : .text
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
            HStack(spacing: 8) {
                if family.hasActivatable {
                    Button("Activate" + (model.data.installMethod == .ask ? "…" : "")) { model.activate([family]) }
                        .buttonStyle(.borderedProminent)
                }
                if family.hasDeactivatable {
                    Button("Deactivate") { model.deactivate([family]) }
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
        default: "Managed outside Point"
        }
    }
}

/// A large, editable sample in one style.
private struct TextTab: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @AppStorage("typeTester.text") private var text = "Sphinx of black quartz, judge my vow."
    @AppStorage("typeTester.size") private var size = 72.0
    @AppStorage("typeTester.centered") private var centered = true
    /// nil follows the preview weight.
    @State private var styleID: FaceID?

    var body: some View {
        let chosen = family.faces.first { $0.id == styleID }
        let face = chosen ?? family.face(nearestWeight: preview.weight)
        let weight = chosen.map { Double($0.face.weight) } ?? preview.weight
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
                    Text("\(Int(size)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Picker("Alignment", selection: $centered) {
                    Image(systemName: "text.alignleft").tag(false)
                    Image(systemName: "text.aligncenter").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Align left or center")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            TextEditor(text: $text)
                .font(Font(FontLoader.shared.font(face.face, size: size, weight: weight, features: model.features(for: family))))
                .kerning(preview.kerning(at: size))
                .multilineTextAlignment(centered ? .center : .leading)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
    }
}

/// Every style with its own switch.
private struct StylesTab: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @State private var selection: Set<FaceID> = []

    var body: some View {
        let model = self.model
        let features = model.features(for: family)
        Table(family.faces, selection: $selection) {
            TableColumn("Preview") { style in
                FontText(text: preview.text(for: family), face: style.face, size: 20, weight: Double(style.face.weight), features: features)
            }
            .width(min: 200, ideal: 420)
            TableColumn("Style") { style in
                Text(style.face.styleName)
            }
            .width(min: 90, ideal: 140)
            TableColumn("Weight") { style in
                Text("\(style.face.weight)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            TableColumn("Status") { style in
                HStack(spacing: 8) {
                    MiniSwitch(isOn: style.state.isActive, isEnabled: style.canActivate || style.canDeactivate) {
                        style.state.isActive ? model.deactivate([style]) : model.activate([style], title: "\(family.name) \(style.face.styleName)")
                    }
                    Text(style.state.label).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 140, ideal: 210)
        }
        // A family has a handful of styles: stripes would mostly fill the empty space below them.
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: FaceID.self) { ids in
            if let id = ids.first, let style = family.faces.first(where: { $0.id == id }) {
                StyleMenu(family: family, face: style, model: model)
            }
        }
    }
}
