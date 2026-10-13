import CiceroCore
import SwiftUI

/// One family's page, pushed over the browser: a type tester, every style, then the glyphs, one under the other.
struct FontPage: View {
    @Environment(AppModel.self) private var model
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
                GlyphsSection(family: family)
            }
        }
        .background(Color.canvas)
        .navigationTitle(family.name)
        .toolbar {
            ToolbarItem { PreviewOptionsButton() }
            ToolbarSpacer(.fixed)
            ToolbarItem { InfoButton() }
        }
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
            HStack(spacing: 8) {
                if family.hasActivatable {
                    Button("Activate" + (model.data.installMethod == .ask && family.app == nil ? "…" : "")) { model.activate([family]) }
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
            .padding(.top, 12)
            let font = Font(FontLoader.shared.font(face.face, size: size, weight: weight, features: model.features(for: family)))
            let kerning = preview.kerning(at: size)
            let alignment: TextAlignment = centered ? .center : .leading
            // An invisible copy of the text sets the editor's height, so it grows with the page instead of
            // scrolling inside it. The 5 pt matches the editor's padding at each end of a line.
            Text(text.hasSuffix("\n") || text.isEmpty ? text + " " : text)
                .font(font)
                .kerning(kerning)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, 5)
                .hidden()
                .overlay {
                    TextEditor(text: $text)
                        .font(font)
                        .kerning(kerning)
                        .multilineTextAlignment(alignment)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                }
                .frame(minHeight: 280)
                .padding(.vertical, 20)
        }
        .padding(.horizontal, 24)
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
                    FontText(text: preview.text(for: family), face: style.face, size: 20, weight: Double(style.face.weight), features: features)
                } style: {
                    Text(style.face.styleName)
                } weight: {
                    Text("\(style.face.weight)").monospacedDigit().foregroundStyle(.secondary)
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
