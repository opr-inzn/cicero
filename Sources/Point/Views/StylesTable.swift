import SwiftUI

/// Every style in the family as a table, with a switch to turn each one on or off.
struct StylesTable: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    @State private var selection: Set<LibraryFace.ID> = []
    @State private var sortOrder: [KeyPathComparator<LibraryFace>] = []

    var body: some View {
        let text = preview.text(for: family)
        let features = library.detailFeatures
        let rows = sortOrder.isEmpty ? family.faces : family.faces.sorted(using: sortOrder)
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Preview") { style in
                Text(text)
                    .font(Font(FontCache.shared.font(style.face, size: 20, weight: Double(style.face.weightClass), features: features)))
                    .kerning(preview.kerning(atSize: 20))
                    .lineLimit(1)
                    .padding(.vertical, 2)
            }
            .width(min: 200, ideal: 360)
            TableColumn("Style", value: \.face.styleName)
                .width(min: 100, ideal: 160)
            TableColumn("Weight", value: \.face.weightClass) { style in
                Text(String(style.face.weightClass)).monospacedDigit()
            }
            .width(60)
            TableColumn("Status", value: \.status.label)
                .width(min: 90, ideal: 150)
            TableColumn("On") { style in
                Toggle("On", isOn: isOn(style))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!style.canActivate && !style.canDeactivate)
                    .help(help(for: style))
            }
            .width(44)
        }
        .contextMenu(forSelectionType: LibraryFace.ID.self) { ids in
            contextMenu(for: family.faces.filter { ids.contains($0.id) })
        }
    }

    /// Reads the real status, so the switch settles once the rescan after activating lands.
    private func isOn(_ style: LibraryFace) -> Binding<Bool> {
        Binding(
            get: { style.status.isActive },
            set: { on in
                if on {
                    library.requestActivate(faces: [style], title: "\(family.name) \(style.face.styleName)")
                } else {
                    library.requestDeactivate(faces: [style])
                }
            }
        )
    }

    private func help(for style: LibraryFace) -> String {
        if style.canActivate { return "Turn this style on" }
        if style.canDeactivate { return "Turn this style off" }
        return style.status.label
    }

    @ViewBuilder
    private func contextMenu(for faces: [LibraryFace]) -> some View {
        if faces.count == 1 {
            FaceActionsMenu(family: family, face: faces[0])
        } else if faces.count > 1 {
            Text("\(faces.count) Styles")
            let ellipsis = library.data.installMethod == .ask ? "…" : ""
            if faces.contains(where: \.canActivate) {
                Button("Activate" + ellipsis) {
                    library.requestActivate(faces: faces, title: "\(faces.count) styles of \(family.name)")
                }
                TemporaryActivationMenu { library.requestActivateTemporarily(faces: faces, scope: $0) }
            } else if faces.contains(where: \.isTemporary) {
                Button("Activate Permanently" + ellipsis) {
                    library.requestActivate(faces: faces, title: "\(faces.count) styles of \(family.name)")
                }
            }
            if faces.contains(where: \.canDeactivate) {
                Button("Deactivate") { library.requestDeactivate(faces: faces) }
            }
        }
    }
}
