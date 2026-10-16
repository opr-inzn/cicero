import AppKit
import CiceroCore
import SwiftUI

/// What activating and deactivating families are called, in their right-click menu and on a font page alike.
struct ActivationTitles {
    /// The app every family is one that loads from its own folder ("Adobe Apps"), where on and off mean in
    /// every app, that one's included.
    let app: String?
    let activate: String
    let deactivate: String

    init(_ families: [Family]) {
        app = families.allSatisfy { $0.app != nil } ? families.first?.app.map { $0 == "Adobe" ? "Adobe Apps" : $0 } : nil
        let temporary = families.allSatisfy { $0.temporaryScope != nil }
        let partial = families.contains { $0.hasActive && $0.temporaryScope == nil }
        activate = temporary ? "Activate Permanently" : app != nil ? "Activate in All Apps" : partial ? "Activate Remaining Styles" : "Activate"
        // On in the app only, nothing is on in other apps: turning it off there is all deactivating does.
        deactivate = app.map { families.contains(where: \.hasActive) ? "Deactivate in All Apps" : "Deactivate in \($0)" } ?? "Deactivate"
    }
}

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

        let titles = ActivationTitles(families)
        let app = titles.app
        // The symbols of the sidebar's Active and Inactive, and half for the switch's middle position.
        if families.contains(where: \.hasActivatable) {
            Button(titles.activate, systemImage: "checkmark.circle") { model.activate(families) }
        }
        if let app, families.contains(where: { $0.position != .app }) {
            Button("Use in \(app) Only", systemImage: "circle.lefthalf.filled") { model.useInAppOnly(families.flatMap(\.faces)) }
        }
        if families.contains(where: \.hasTemporarilyActivatable) {
            Button(app != nil ? "Activate Temporarily in All Apps" : "Activate Temporarily", systemImage: "clock") {
                model.activateTemporarily(families)
            }
        }
        if families.contains(where: \.hasDeactivatable) {
            Button(titles.deactivate, systemImage: "circle.dashed") { model.deactivate(families) }
        }
        if families.contains(where: { $0.faces.contains(where: \.isAdobeFonts) }) {
            Button("Manage in Creative Cloud", systemImage: "arrow.up.forward.app") { CreativeCloud.open() }
        }
        if families.count == 1 {
            CopySourcesMenu(styles: families[0].faces, title: families[0].name, model: model)
        }

        Divider()

        // The symbols of the sidebar's sections.
        Menu {
            ForEach(model.data.sets) { set in
                Toggle(set.name, isOn: Binding(
                    get: { families.allSatisfy { model.isMember($0, of: set.id) } },
                    set: { model.setMembership($0, for: families, in: set.id) }
                ))
            }
            if !model.data.sets.isEmpty { Divider() }
            Button("New Set from Selection", systemImage: "plus") {
                model.prompt("New Set", confirm: "Create") { model.addSet(named: $0, with: families) }
            }
        } label: {
            Label("Add to Set", systemImage: SidebarSection.sets.icon)
        }
        Menu { TagMenuItems(families: families, model: model) } label: { Label("Tags", systemImage: SidebarSection.tags.icon) }
        Menu { ClassificationMenuItems(families: families, model: model) } label: {
            Label("Classification", systemImage: SidebarSection.classifications.icon)
        }

        Divider()

        Button("Reveal in Finder", systemImage: "finder") { model.reveal(families) }
        Button(families.count == 1 ? "Copy Family Name" : "Copy Family Names", systemImage: "doc.on.clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(families.map(\.name).joined(separator: "\n"), forType: .string)
        }
        Button("Export", systemImage: "square.and.arrow.up") { model.exportFonts(families, named: nil) }
        if families.count > 1 {
            Button("Compare", systemImage: "rectangle.split.1x2") {
                model.compare(families)
                openWindow(id: WindowID.compare)
            }
        }
        Divider()

        // Added one at a time, they can leave the library and stay where they are.
        if model.canRemoveFromLibrary(families) {
            Button("Remove from Library", systemImage: "minus.circle") { model.removeFromLibrary(families) }
        }
        Button("Move to Trash", systemImage: "trash") { model.requestTrash(families) }
    }

    private var note: String? {
        // One only Adobe apps use says so, like the fonts in Adobe's folders.
        if families.first?.isAdobeFonts == true, families.first?.state == .active { return "From Adobe Fonts" }
        return switch families.first?.state {
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
            Button("Activate Style", systemImage: "checkmark.circle") {
                model.activate([face], title: "\(family.name) \(face.face.styleName)")
            }
        }
        if face.canActivateTemporarily {
            Button("Activate Temporarily", systemImage: "clock") { model.activateTemporarily([face]) }
        }
        if face.canDeactivate {
            Button("Deactivate Style", systemImage: "circle.dashed") { model.deactivate([face]) }
        }
        CopySourcesMenu(styles: [face], title: "\(family.name) \(face.face.styleName)", model: model)
        Divider()
        Button("Reveal in Finder", systemImage: "finder") { model.reveal(path: face.face.path) }
        Button("Copy PostScript Name", systemImage: "doc.on.clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(face.face.postScriptName, forType: .string)
        }
        Divider()
        Button("Move Style to Trash", systemImage: "trash") {
            model.requestTrash([face], removing: family.faces.count == 1 ? [family.id] : [], title: "“\(family.name) \(face.face.styleName)”")
        }
    }
}

/// Use Copy From, for styles that are in more than one place, like each client's folder: the places, the one
/// in use checked. Picking one turns its copies on and the others Cicero turned on off.
struct CopySourcesMenu: View {
    let styles: [LibraryFace]
    /// What the styles are called: "Helvetica", "Helvetica Bold".
    let title: String
    let model: AppModel

    var body: some View {
        let sources = model.copySources(of: styles)
        if sources.count > 1 {
            Menu {
                ForEach(sources) { source in
                    Toggle(label(source), isOn: Binding(
                        get: { source.isInUse },
                        set: { _ in model.useCopies(from: source, title: "\(title) from \(source.name)") }
                    ))
                }
            } label: {
                Label("Use Copy From", systemImage: "doc.on.doc")
            }
        }
    }

    /// "Acme — version 1.002, 2 styles": the version, and how many styles when it hasn't them all.
    private func label(_ source: CopySource) -> String {
        var details: [String] = []
        if let version = source.version { details.append("version \(version)") }
        if styles.count > 1 && source.choices.count < styles.count {
            details.append(source.choices.count == 1 ? "1 style" : "\(source.choices.count) styles")
        }
        return details.isEmpty ? source.name : "\(source.name) — " + details.joined(separator: ", ")
    }
}

/// Which classification families are in: Automatic, the one their fonts suggest, or one the user puts them in, the
/// one Automatic suggests too, which keeps them there whatever Cicero suggests later; and a new one.
struct ClassificationMenuItems: View {
    let families: [Family]
    let model: AppModel

    var body: some View {
        let overrides = model.data.classificationOverrides
        let automatic = families.allSatisfy { overrides[$0.id] == nil }
        // One family says which classification Automatic is.
        let suggested = families.count == 1 ? model.suggestedClassification(of: families[0]) : nil
        Toggle(suggested.map { "Automatic (\(model.name(of: $0)))" } ?? "Automatic", isOn: Binding(
            get: { automatic },
            set: { if $0 { model.setClassification(nil, for: families) } }
        ))
        Divider()
        ForEach(model.classificationNames, id: \.self) { name in
            Toggle(name, isOn: Binding(
                get: { families.allSatisfy { overrides[$0.id] == name } },
                set: { if $0 { model.setClassification(name, for: families) } }
            ))
        }
        Divider()
        Button("New Classification", systemImage: "plus") { model.newClassification(for: families) }
    }
}
