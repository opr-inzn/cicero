import AppKit
import CiceroCore
import SwiftUI

/// Adds the Info panel at the trailing edge of the window: a pane floating below the toolbar like the
/// sidebar. Not SwiftUI's inspector, which runs the full window height under the search field.
struct InfoPanelColumn: ViewModifier {
    @Environment(AppModel.self) private var model
    private static let width: CGFloat = 300
    private static let gap: CGFloat = 8

    func body(content: Content) -> some View {
        let isPresented = model.isInfoPresented
        ZStack(alignment: .trailing) {
            // Makes room in one step, so a grid reflows once rather than on every frame of the slide. An inset
            // rather than padding, so the page still runs under the toolbar from edge to edge and the search
            // field keeps the look it has over the page instead of turning flat above the panel.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.trailing, isPresented ? Self.width + Self.gap * 2 : 0)
            ZStack {
                if isPresented {
                    let shape = RoundedRectangle(cornerRadius: 20)
                    InfoPanel()
                        .frame(width: Self.width)
                        .frame(maxHeight: .infinity)
                        .background {
                            // Opaque, as it slides out over the page; the tint matches the sidebar.
                            shape.fill(Color.canvas)
                            shape.fill(.quaternary.opacity(0.5))
                        }
                        .clipShape(shape)
                        .padding([.horizontal, .bottom], Self.gap)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy, value: isPresented)
        }
        // The toolbar and the gap around the panel show the page's colour from edge to edge.
        .background(Color.canvas)
    }
}

/// Keeps the family at the top of a grid or list there when its width changes, as when the Info panel
/// opens or closes; otherwise the same scroll offset lands on other families once rows hold fewer or more.
/// Needs `.scrollTargetLayout()`.
struct KeepsTopOnResize: ViewModifier {
    // Applied by the scroll view as it lays out, so after the rows have reflowed (a proxy can jump too early).
    @State private var position = ScrollPosition(idType: String.self)
    @State private var topID: String?
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .scrollPosition($position, anchor: .top)
            .onScrollTargetVisibilityChange(idType: String.self) { if let first = $0.first { topID = first } }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: { isAtTop = $1 }
            // Reported before the visible families update, so `topID` is still the one from before.
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width } action: { _, _ in
                if !isAtTop, let topID { position.scrollTo(id: topID, anchor: .top) }
            }
    }
}

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        if let family = model.inspectedFamily {
            FamilyInfo(family: family, face: family.face(nearestWeight: preview.weight))
                .id(family.id)
        } else {
            let count = model.selectedIDs.count
            ContentUnavailableView(count > 1 ? "\(count) Fonts Selected" : "No Selection", systemImage: "info.circle",
                                   description: Text("Select a single font to see its info."))
        }
    }
}

/// Describes the style being previewed (the regular one at the default weight).
private struct FamilyInfo: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let face: LibraryFace

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Text(family.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 16)
            Picker("Tab", selection: $model.infoTab) {
                ForEach(InfoTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            switch model.infoTab {
            case .info: ScrollView { InfoRows(face: face) }
            case .features: FeatureControls(family: family, face: face.face)
            }
        }
    }
}

private struct InfoRows: View {
    @Environment(AppModel.self) private var model
    let face: LibraryFace
    @State private var info: CiceroCore.FontInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Status", face.state.label)
            if let info {
                ForEach(Array(info.rows.enumerated()), id: \.offset) { _, row in
                    self.row(row.label, row.value)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            LanguagesRow(face: face.face)
            CharacterSetsRow(face: face.face)
            UnicodeBlocksRow(face: face.face)
            VStack(alignment: .leading, spacing: 4) {
                label("Location")
                Text(face.face.path).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Reveal in Finder") { model.reveal(path: face.face.path) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            if !face.otherCopies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    label("Other copies")
                    ForEach(face.otherCopies, id: \.self) { path in
                        Button(path) { model.reveal(path: path) }
                            .buttonStyle(.link)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: face.id) {
            info = nil
            let face = face.face
            info = await Task.detached(priority: .userInitiated) { CiceroCore.FontInfo.read(face) }.value
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Features

private struct FeatureControls: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let face: FontFace
    @State private var groups: [FontFeatureGroup]?

    var body: some View {
        Group {
            if let groups, groups.isEmpty {
                ContentUnavailableView("No Features", systemImage: "textformat.abc",
                                       description: Text("This font has no optional OpenType features to switch on or off."))
            } else if let groups {
                // A box of switches per feature, like the system Typography panel.
                Form {
                    ForEach(groups) { group in
                        Section(group.name) {
                            ForEach(group.options) { option in
                                Toggle(option.name, isOn: group.isExclusive ? choice(group, option) : toggle(group, option))
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: face.id) {
            let face = face
            groups = await Task.detached(priority: .userInitiated) { FontFeatureGroup.load(for: face) }.value
        }
    }

    private var settings: [FeatureSetting] { model.familyFeatures[family.id] ?? [] }

    private func set(_ settings: [FeatureSetting]) {
        model.familyFeatures[family.id] = settings.isEmpty ? nil : settings
    }

    private func exclusive(_ group: FontFeatureGroup) -> Binding<Int> {
        Binding(
            get: { settings.first { $0.type == group.type }?.selector ?? group.options.first(where: \.isDefault)?.selector ?? group.options[0].selector },
            set: { selector in
                var list = settings.filter { $0.type != group.type }
                if selector != group.options.first(where: \.isDefault)?.selector { list.append(FeatureSetting(type: group.type, selector: selector)) }
                set(list)
            }
        )
    }

    /// Exclusive features: switching an option on picks it; switching the picked one off goes back to the default.
    private func choice(_ group: FontFeatureGroup, _ option: FontFeatureGroup.Option) -> Binding<Bool> {
        let picked = exclusive(group)
        let fallback = group.options.first(where: \.isDefault)?.selector ?? group.options[0].selector
        return Binding(
            get: { picked.wrappedValue == option.selector },
            set: { on in
                if on { picked.wrappedValue = option.selector } else if picked.wrappedValue == option.selector { picked.wrappedValue = fallback }
            }
        )
    }

    /// Independent features: the option's selector turns it on, the next one (CoreText's convention) turns it off.
    private func toggle(_ group: FontFeatureGroup, _ option: FontFeatureGroup.Option) -> Binding<Bool> {
        let off = option.selector + 1
        return Binding(
            get: {
                if let chosen = settings.first(where: { $0.type == group.type && ($0.selector == option.selector || $0.selector == off) }) {
                    return chosen.selector == option.selector
                }
                return option.isDefault
            },
            set: { on in
                var list = settings.filter { !($0.type == group.type && ($0.selector == option.selector || $0.selector == off)) }
                if on != option.isDefault { list.append(FeatureSetting(type: group.type, selector: on ? option.selector : off)) }
                set(list)
            }
        )
    }
}
