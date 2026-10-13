import AppKit
import CiceroCore
import SwiftUI

/// The right-click menu for one or more families.
struct FamilyMenu: View {
    let families: [Family]
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if families.count > 1 {
            Text("\(families.count) Families")
        } else if let note {
            Text(note)
        }

        let ellipsis = model.data.installMethod == .ask ? "…" : ""
        // Every family is one an app loads from its own folder: on and off mean in every app, Adobe's included.
        let app = families.allSatisfy { $0.app != nil } ? families.first?.app.map { $0 == "Adobe" ? "Adobe Apps" : $0 } : nil
        if families.contains(where: \.hasActivatable) {
            let temporary = families.allSatisfy { $0.temporaryScope != nil }
            let partial = families.contains { $0.hasActive && $0.temporaryScope == nil }
            let title = temporary ? "Activate Permanently" : app != nil ? "Activate in All Apps" : partial ? "Activate Remaining Styles" : "Activate"
            Button(title + (app != nil ? "" : ellipsis)) { model.activate(families) }
        }
        if let app, families.contains(where: { $0.position != .app }) {
            Button("Use in \(app) Only") { model.useInAppOnly(families.flatMap(\.faces)) }
        }
        if families.contains(where: \.hasTemporarilyActivatable) {
            Button("Activate Temporarily") { model.activateTemporarily(families) }
        }
        if families.contains(where: \.hasDeactivatable) {
            // On in the app only, nothing is on in other apps: turning it off there is all deactivating does.
            let title = app.map { families.contains(where: \.hasActive) ? "Deactivate in All Apps" : "Deactivate in \($0)" } ?? "Deactivate"
            Button(title) { model.deactivate(families) }
        }

        Divider()

        Menu("Add to Set") {
            ForEach(model.data.sets) { set in
                Toggle(set.name, isOn: Binding(
                    get: { families.allSatisfy { model.isMember($0, of: set.id) } },
                    set: { model.setMembership($0, for: families, in: set.id) }
                ))
            }
            if !model.data.sets.isEmpty { Divider() }
            Button("New Set from Selection…") {
                model.prompt("New Set", confirm: "Create") { model.addSet(named: $0, with: families) }
            }
        }
        Menu("Tags") { TagMenuItems(families: families, model: model) }

        Divider()

        Button("Reveal in Finder") { model.reveal(families) }
        Button(families.count == 1 ? "Copy Family Name" : "Copy Family Names") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(families.map(\.name).joined(separator: "\n"), forType: .string)
        }
        Button("Export…") { model.exportFonts(families, named: nil) }
        if families.count > 1 {
            Button("Compare") {
                model.compare(families)
                openWindow(id: WindowID.compare)
            }
        }
        Divider()

        // Added one at a time, they can leave the library and stay where they are.
        if model.canRemoveFromLibrary(families) {
            Button("Remove from Library") { model.removeFromLibrary(families) }
        }
        Button("Move to Trash…") { model.requestTrash(families) }
    }

    private var note: String? {
        switch families.first?.state {
        case .appOnly(let app): "Available in \(FaceState.appDescription(app)) only"
        case .system: "Installed with macOS"
        default: nil
        }
    }
}

/// The right-click menu for one style of a family.
struct StyleMenu: View {
    let family: Family
    let face: LibraryFace
    let model: AppModel

    var body: some View {
        Text(face.state.label)
        if face.canActivate {
            Button("Activate Style" + (model.data.installMethod == .ask ? "…" : "")) {
                model.activate([face], title: "\(family.name) \(face.face.styleName)")
            }
        }
        if face.canActivateTemporarily {
            Button("Activate Temporarily") { model.activateTemporarily([face]) }
        }
        if face.canDeactivate {
            Button("Deactivate Style") { model.deactivate([face]) }
        }
        Divider()
        Button("Reveal in Finder") { model.reveal(path: face.face.path) }
        Button("Copy PostScript Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(face.face.postScriptName, forType: .string)
        }
        Divider()
        Button("Move Style to Trash…") {
            model.requestTrash([face], removing: family.faces.count == 1 ? [family.id] : [], title: "“\(family.name) \(face.face.styleName)”")
        }
    }
}
