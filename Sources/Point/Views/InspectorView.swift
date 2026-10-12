import AppKit
import SwiftUI

enum InspectorTab: String, CaseIterable {
    case info = "Info"
    case features = "Features"
}

/// Window-level inspector: describes the open family, or the selected one in the browser.
struct InspectorPanel: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        @Bindable var library = library
        if let family = library.inspectorFamily {
            InspectorView(
                family: family,
                tab: $library.inspectorTab,
                features: $library.detailFeatures,
                previewFace: family.face(nearestWeight: Int(preview.weight)),
                allowsFeatures: library.detailFamily != nil
            )
            .id(family.id)
        } else {
            let count = library.selectedFamilyIDs.count
            ContentUnavailableView(
                count > 1 ? "\(count) Fonts Selected" : "No Selection",
                systemImage: "info.circle",
                description: Text("Select a single font to see its info.")
            )
        }
    }
}

struct InspectorView: View {
    let family: FontFamily
    @Binding var tab: InspectorTab
    @Binding var features: [FeatureSetting]
    let previewFace: LibraryFace
    /// Features only apply to the detail view's previews, so the browser shows Info alone.
    let allowsFeatures: Bool
    @State private var faceID: String?

    private var face: LibraryFace {
        family.faces.first { $0.id == faceID } ?? previewFace
    }

    var body: some View {
        let shownTab = allowsFeatures ? tab : .info
        VStack(spacing: 0) {
            if allowsFeatures {
                Picker("", selection: $tab) {
                    ForEach(InspectorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
            } else {
                Text(family.name)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            if family.faces.count > 1 {
                Picker("Style", selection: Binding(get: { face.id }, set: { faceID = $0 })) {
                    ForEach(family.faces) { Text($0.face.styleName).tag($0.id) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                switch shownTab {
                case .info: InfoPane(face: face)
                case .features: FeaturesPane(face: face.face, features: $features)
                }
            }
        }
        .onChange(of: previewFace.id) { faceID = nil }
    }
}

private struct InfoPane: View {
    @Environment(LibraryStore.self) private var library
    let face: LibraryFace

    var body: some View {
        let metadata = FontMetadata(face: face.face)
        VStack(alignment: .leading, spacing: 14) {
            row("Status", face.status.label)
            ForEach(Array(metadata.rows.enumerated()), id: \.offset) { _, pair in
                row(pair.0, pair.1)
            }
            LanguagesRow(face: face.face)
            CharacterSetsRow(face: face.face)
            VStack(alignment: .leading, spacing: 4) {
                label("Location")
                Text(face.face.path)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reveal in Finder") { library.reveal(face) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            if !face.otherPaths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    label("Other copies")
                    ForEach(face.otherPaths, id: \.self) { path in
                        Button(path) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            .buttonStyle(.link)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeaturesPane: View {
    let face: FontFace
    @Binding var features: [FeatureSetting]
    @State private var types: [FontFeatureType] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if types.isEmpty {
                ContentUnavailableView("No Features", systemImage: "textformat.abc",
                                       description: Text("This font has no optional OpenType features to switch on or off."))
                    .padding(.top, 40)
            }
            ForEach(types) { type in
                VStack(alignment: .leading, spacing: 6) {
                    Text(type.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if type.isExclusive {
                        Picker(type.name, selection: exclusiveBinding(type)) {
                            ForEach(type.selectors) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                    } else {
                        ForEach(type.selectors) { selector in
                            Toggle(selector.name, isOn: toggleBinding(type, selector))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            if !features.isEmpty {
                Button("Reset Features") { features = [] }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: face.id) { types = FontFeatureType.load(for: face) }
    }

    private func exclusiveBinding(_ type: FontFeatureType) -> Binding<Int> {
        Binding(
            get: { features.first { $0.type == type.id }?.selector ?? type.selectors.first(where: \.isDefault)?.id ?? type.selectors[0].id },
            set: { selector in
                features.removeAll { $0.type == type.id }
                features.append(FeatureSetting(type: type.id, selector: selector))
            }
        )
    }

    /// Non-exclusive AAT selectors come in on/off pairs: an even "on" selector is followed by its "off".
    private func toggleBinding(_ type: FontFeatureType, _ selector: FontFeatureType.Selector) -> Binding<Bool> {
        let on = FeatureSetting(type: type.id, selector: selector.id)
        let off = FeatureSetting(type: type.id, selector: selector.id + 1)
        return Binding(
            get: { features.contains(on) || (!features.contains(off) && selector.isDefault) },
            set: { enabled in
                features.removeAll { $0 == on || $0 == off }
                features.append(enabled ? on : off)
            }
        )
    }
}
