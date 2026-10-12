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
            Button((partial ? "Activate Inactive Styles" : "Activate") + ellipsis) { library.requestActivate(families) }
        }
        if families.contains(where: \.hasDeactivatableFaces) {
            Button("Deactivate") { library.requestDeactivate(families) }
        }

        Divider()

        Menu("Style") {
            ForEach(library.data.styles) { style in
                Toggle(style.name, isOn: Binding(
                    get: { families.allSatisfy { library.styleID(of: $0) == style.id } },
                    set: { library.setStyle($0 ? style.id : nil, for: families) }
                ))
            }
            Divider()
            Button("None") { library.setStyle(nil, for: families) }
            Button("New Style…") {
                library.prompt("New Style", confirm: "Create") { name in
                    library.addStyle(named: name)
                    if let style = library.data.styles.last { library.setStyle(style.id, for: families) }
                }
            }
        }

        Menu("Collections") {
            ForEach(library.data.collections) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { families.allSatisfy { library.isMember($0, of: collection.id) } },
                    set: { library.setMembership($0, for: families, in: collection.id) }
                ))
            }
            if !library.data.collections.isEmpty { Divider() }
            Button("New Collection…") {
                library.prompt("New Collection", confirm: "Create") { library.addCollection(named: $0, with: families) }
            }
        }

        Menu("Foundry") {
            let current = Set(families.compactMap { library.foundryName(of: $0) })
            ForEach(library.foundryNames, id: \.self) { foundry in
                Toggle(foundry, isOn: Binding(
                    get: { current == [foundry] },
                    set: { if $0 { library.setFoundry(foundry, for: families) } }
                ))
            }
            Divider()
            Button("Other Foundry…") {
                library.prompt("Set Foundry", text: current.count == 1 ? current.first! : "", confirm: "Set") {
                    library.setFoundry($0, for: families)
                }
            }
            if families.contains(where: { library.data.foundryOverrides[$0.name] != nil }) {
                Button("Use Font's Own Foundry") { library.setFoundry(nil, for: families) }
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
