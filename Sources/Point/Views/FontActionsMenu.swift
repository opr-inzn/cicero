import AppKit
import SwiftUI

/// Right-click menu for one or more font families.
struct FontActionsMenu: View {
    @Environment(LibraryStore.self) private var library
    let families: [FontFamily]

    var body: some View {
        if families.count > 1 {
            Text("\(families.count) Families")
        }
        if let note = statusNote {
            Text(note)
        }

        let ellipsis = library.data.installMethod == .ask ? "…" : ""
        if families.contains(where: \.hasActivatableFaces) {
            let partial = families.contains(where: \.hasActiveFaces)
            Button((partial ? "Activate Remaining Styles" : "Activate") + ellipsis) { library.requestActivate(families) }
        }
        if families.contains(where: \.hasDeactivatableFaces) {
            Button("Deactivate") { library.requestDeactivate(families) }
        }

        Divider()

        Menu("Add to Set") {
            ForEach(library.data.sets) { set in
                Toggle(set.name, isOn: Binding(
                    get: { families.allSatisfy { library.isMember($0, of: set.id) } },
                    set: { library.setMembership($0, for: families, in: set.id) }
                ))
            }
            if !library.data.sets.isEmpty { Divider() }
            Button("New Set from Selection…") {
                library.prompt("New Set", confirm: "Create") { library.addSet(named: $0, with: families) }
            }
        }

        Menu("Tags") {
            ForEach(library.data.tags, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { families.allSatisfy { library.tags(of: $0).contains(tag) } },
                    set: { library.setTag(tag, $0, for: families) }
                ))
            }
            if !library.data.tags.isEmpty { Divider() }
            Button("New Tag…") {
                library.prompt("New Tag", confirm: "Add") { library.addTag(named: $0, to: families) }
            }
        }

        Divider()

        Button("Reveal in Finder") { library.reveal(families) }
        Button(families.count == 1 ? "Copy Family Name" : "Copy Family Names") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(families.map(\.name).joined(separator: "\n"), forType: .string)
        }
        if families.count == 1 {
            Divider()
            Button("Open") { library.detailFamilyID = families[0].id }
            Button("Show Info") { library.showInfo(for: families[0]) }
        }
    }

    private var statusNote: String? {
        guard families.count == 1 else { return nil }
        switch families[0].status {
        case .appOnly(let app): return "Available in \(app) apps only"
        case .system: return "Installed with macOS"
        default: return nil
        }
    }
}

/// Right-click menu for a single style (face) in the detail view.
struct FaceActionsMenu: View {
    @Environment(LibraryStore.self) private var library
    let family: FontFamily
    let face: LibraryFace

    var body: some View {
        Text(face.status.label)
        if face.canActivate {
            Button("Activate Style" + (library.data.installMethod == .ask ? "…" : "")) {
                library.requestActivate(faces: [face], title: "\(family.name) \(face.face.styleName)")
            }
        }
        if face.canDeactivate {
            Button("Deactivate Style") { library.requestDeactivate(faces: [face]) }
        }
        Divider()
        Button("Reveal in Finder") { library.reveal(face) }
        Button("Copy PostScript Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(face.face.postScriptName, forType: .string)
        }
    }
}
