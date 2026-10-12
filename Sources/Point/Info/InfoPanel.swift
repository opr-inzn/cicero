import AppKit
import PointCore
import SwiftUI

/// Adds the Info panel at the trailing edge of a page, below the toolbar. A plain column rather than
/// SwiftUI's inspector, which runs the full window height under the toolbar's search field.
struct InfoPanelColumn: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isInfoPresented {
                Divider()
                InfoPanel()
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .background(.background.secondary)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: model.isInfoPresented)
    }
}

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        if let family = model.inspectedFamily {
            FamilyInfo(family: family, previewFace: family.face(nearestWeight: preview.weight))
                .id(family.id)
        } else {
            let count = model.selectedIDs.count
            ContentUnavailableView(count > 1 ? "\(count) Fonts Selected" : "No Selection", systemImage: "info.circle",
                                   description: Text("Select a single font to see its info."))
        }
    }
}

private struct FamilyInfo: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let previewFace: LibraryFace
    @State private var faceID: FaceID?

    private var face: LibraryFace {
        family.faces.first { $0.id == faceID } ?? previewFace
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Text(family.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 12)
            Picker("Tab", selection: $model.infoTab) {
                ForEach(InfoTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            if family.faces.count > 1 {
                Picker("Style", selection: Binding(get: { face.id }, set: { faceID = $0 })) {
                    ForEach(family.faces) { Text($0.face.styleName).tag($0.id) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()
            ScrollView {
                switch model.infoTab {
                case .info: InfoRows(face: face)
                case .features: FeatureControls(family: family, face: face.face)
                }
            }
        }
        .onChange(of: previewFace.id) { faceID = nil }
    }
}

private struct InfoRows: View {
    @Environment(AppModel.self) private var model
    let face: LibraryFace
    @State private var info: PointCore.FontInfo?

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
            info = await Task.detached(priority: .userInitiated) { PointCore.FontInfo.read(face) }.value
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
        VStack(alignment: .leading, spacing: 18) {
            if let groups {
                if groups.isEmpty {
                    ContentUnavailableView("No Features", systemImage: "textformat.abc",
                                           description: Text("This font has no optional OpenType features to switch on or off."))
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name).font(.caption).foregroundStyle(.secondary)
                        if group.isExclusive {
                            Picker(group.name, selection: exclusive(group)) {
                                ForEach(group.options) { Text($0.name).tag($0.selector) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        } else {
                            ForEach(group.options) { option in
                                Toggle(option.name, isOn: toggle(group, option)).toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
