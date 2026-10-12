import AppKit
import SwiftUI

/// Library sidebar. "Edit" switches every row to a checkbox so items can be shown or hidden in place;
/// the same visibility settings also live in Settings → Sidebar.
struct SidebarView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        let editing = library.isEditingSidebar
        List(selection: $library.sidebarSelection) {
            Section {
                ForEach(rowsToShow(library.libraryRows)) { row in
                    rowView(row)
                }
            } header: {
                libraryHeader(editing: editing)
            }

            ForEach(SidebarSection.allCases) { section in
                if editing || library.isVisible(section.key) {
                    Section(isExpanded: expansion(section)) {
                        ForEach(rowsToShow(library.rows(for: section))) { row in
                            rowView(row, section: section)
                        }
                        if editing && library.rows(for: section).isEmpty {
                            Text("Nothing here yet")
                                .foregroundStyle(.tertiary)
                                .selectionDisabled()
                        }
                    } header: {
                        sectionHeader(section, editing: editing)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.snappy, value: editing)
        .contextMenu {
            Button(editing ? "Done Editing Sidebar" : "Edit Sidebar") { library.isEditingSidebar.toggle() }
        }
    }

    private func rowsToShow(_ rows: [SidebarRow]) -> [SidebarRow] {
        library.isEditingSidebar ? rows : rows.filter { library.isVisible($0.key) }
    }

    // MARK: Headers

    private func libraryHeader(editing: Bool) -> some View {
        HStack {
            Text("Library")
            Spacer()
            Button(editing ? "Done" : "Edit") {
                withAnimation(.snappy) { library.isEditingSidebar.toggle() }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(editing ? .semibold : .regular))
            .foregroundStyle(editing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(editing ? "Finish editing the sidebar" : "Choose which items appear in the sidebar")
        }
        .padding(.trailing, 10)
    }

    private func sectionHeader(_ section: SidebarSection, editing: Bool) -> some View {
        HStack(spacing: 6) {
            if editing {
                Toggle(section.title, isOn: library.visibilityBinding(for: section.key))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            Text(section.title)
                .opacity(editing && !library.isVisible(section.key) ? 0.45 : 1)
            Spacer()
            if !editing, let action = addAction(for: section) {
                Button(action: action.perform) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(action.help)
            }
        }
        .padding(.trailing, 10)
    }

    private func addAction(for section: SidebarSection) -> (help: String, perform: () -> Void)? {
        switch section {
        case .folders:
            return ("Add a folder of fonts", { library.presentAddFolderPanel() })
        case .styles:
            return ("New style", { library.prompt("New Style", confirm: "Create") { library.addStyle(named: $0) } })
        case .collections:
            return ("New collection", { library.prompt("New Collection", confirm: "Create") { library.addCollection(named: $0) } })
        case .foundries:
            return nil
        }
    }

    private func expansion(_ section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { library.isEditingSidebar || library.isExpanded(section) },
            set: { expanded in
                guard !library.isEditingSidebar else { return }
                library.setExpanded(section, expanded)
            }
        )
    }


    // MARK: Rows

    private func rowView(_ row: SidebarRow, section: SidebarSection? = nil) -> some View {
        let editing = library.isEditingSidebar
        let hidden = !library.isVisible(row.key) || (section.map { !library.isVisible($0.key) } ?? false)
        return HStack(spacing: 6) {
            if editing {
                Toggle(row.title, isOn: library.visibilityBinding(for: row.key))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            Label(row.title, systemImage: row.icon)
                .lineLimit(1)
        }
        .opacity(editing && hidden ? 0.45 : 1)
        .tag(row.selection)
        .contextMenu { rowMenu(row) }
        .dropDestination(for: String.self) { names, _ in
            _ = library.handleDrop(names, on: row.selection)
        }
    }

    @ViewBuilder
    private func rowMenu(_ row: SidebarRow) -> some View {
        switch row.selection {
        case .folder(let id):
            if let folder = library.folder(id) {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                if id != WatchedFolder.deactivatedID {
                    Divider()
                    Picker("Fonts in This Folder", selection: Binding(
                        get: { folder.appOnlyName ?? "" },
                        set: { library.setAppOnlyName($0, forFolder: id) }
                    )) {
                        Text("Inactive until activated").tag("")
                        Text("Active in Adobe apps").tag("Adobe")
                        if let custom = folder.appOnlyName, custom != "Adobe" {
                            Text("Active in \(custom) apps").tag(custom)
                        }
                    }
                    Button("Remove Folder from Library") { library.removeFolder(id) }
                }
            }
        case .style(let id):
            if let style = library.data.styles.first(where: { $0.id == id }) {
                Button("Rename Style…") {
                    library.prompt("Rename Style", text: style.name, confirm: "Rename") { library.renameStyle(id, to: $0) }
                }
                if !style.isBuiltIn {
                    Button("Delete Style") { library.deleteStyle(id) }
                }
            }
        case .collection(let id):
            if let collection = library.data.collections.first(where: { $0.id == id }) {
                Button("Rename Collection…") {
                    library.prompt("Rename Collection", text: collection.name, confirm: "Rename") { library.renameCollection(id, to: $0) }
                }
                Button("Delete Collection") { library.deleteCollection(id) }
            }
        case .system:
            Toggle("Also Show in All, Active and Other Lists", isOn: Binding(
                get: { library.data.showSystemFonts },
                set: { library.data.showSystemFonts = $0; library.save() }
            ))
        case .foundry(let name):
            Button("Rename Foundry…") {
                library.prompt("Rename Foundry", text: name, confirm: "Rename") { library.renameFoundry(name, to: $0) }
            }
        default:
            EmptyView()
        }
        Divider()
        if library.isVisible(row.key) {
            Button("Hide from Sidebar") { library.setVisible(row.key, false) }
        }
        Button(library.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") { library.isEditingSidebar.toggle() }
    }
}
