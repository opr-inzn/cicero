import AppKit
import PointCore
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
        if families.contains(where: \.hasActivatable) {
            let appOnly = families.allSatisfy { if case .appOnly = $0.state { true } else { false } }
            let temporary = families.allSatisfy { $0.temporaryScope != nil }
            let partial = families.contains { $0.hasActive && $0.temporaryScope == nil }
            let title = temporary ? "Activate Permanently" : appOnly ? "Activate in All Apps" : partial ? "Activate Remaining Styles" : "Activate"
            Button(title + (appOnly ? "" : ellipsis)) { model.activate(families) }
        }
        TemporaryMenu { model.activateTemporarily(families, scope: $0) }
        if families.contains(where: \.hasDeactivatable) {
            Button("Deactivate") { model.deactivate(families) }
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
        Menu("Tags") {
            ForEach(model.data.tags, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { families.allSatisfy { model.tags(of: $0).contains(tag) } },
                    set: { model.setTag(tag, $0, for: families) }
                ))
            }
            if !model.data.tags.isEmpty { Divider() }
            Button("New Tag…") {
                model.prompt("New Tag", confirm: "Add") { model.addTag(named: $0, to: families) }
            }
        }

        Divider()

        Button("Reveal in Finder") { model.reveal(families) }
        Button(families.count == 1 ? "Copy Family Name" : "Copy Family Names") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(families.map(\.name).joined(separator: "\n"), forType: .string)
        }
        if families.count > 1 {
            Button("Compare") {
                model.compare(families)
                openWindow(id: WindowID.compare)
            }
        }
        if families.count == 1 {
            Divider()
            Button("Open") { model.openFamilyID = families[0].id }
            Button("Show Info") { model.showInfo(for: families[0]) }
        }

        Divider()

        Button("Move to Trash…") { model.requestTrash(families) }
    }

    private var note: String? {
        switch families.first?.state {
        case .appOnly(let app): "Available in \(app) apps only"
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
        TemporaryMenu { model.activateTemporarily([face], scope: $0) }
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

/// "Activate Temporarily ▸ Until Point Quits / Until You Log Out".
struct TemporaryMenu: View {
    let action: (TemporaryScope) -> Void

    var body: some View {
        Menu("Activate Temporarily") {
            ForEach(TemporaryScope.allCases, id: \.self) { scope in
                Button(scope.menuTitle) { action(scope) }
            }
        }
    }
}
