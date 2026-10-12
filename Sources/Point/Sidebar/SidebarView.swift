import AppKit
import PointCore
import SwiftUI

/// The library sidebar. Edit puts a checkbox on every row and section to show or hide it; the same
/// choices are in Settings → Sidebar.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let editing = model.isEditingSidebar
        List(selection: $model.selection) {
            Section {
                ForEach(shown(model.libraryRows)) { row($0, section: nil) }
            } header: {
                header
            }
            ForEach(SidebarSection.allCases) { section in
                if editing || model.isVisible(section.key) {
                    let rows = model.rows(for: section)
                    Section(isExpanded: expansion(section)) {
                        if section == .characterSets {
                            characterSetGroups
                        } else {
                            ForEach(shown(rows)) { row($0, section: section) }
                        }
                        if editing && rows.isEmpty {
                            Text("Nothing here yet")
                                .foregroundStyle(.tertiary)
                                .selectionDisabled()
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.snappy, value: editing)
        .contextMenu {
            Button(editing ? "Done Editing Sidebar" : "Edit Sidebar") { model.isEditingSidebar.toggle() }
        }
    }

    /// Character sets in collapsible groups; a group whose sets are all hidden disappears.
    private var characterSetGroups: some View {
        ForEach(model.characterSetGroups, id: \.id) { group in
            let rows = shown(group.rows)
            if !rows.isEmpty {
                DisclosureGroup(isExpanded: Binding(
                    get: { model.isEditingSidebar || model.isGroupExpanded(group.id) },
                    set: { if !model.isEditingSidebar { model.setGroupExpanded(group.id, $0) } }
                )) {
                    ForEach(rows) { row($0, section: .characterSets) }
                } label: {
                    Text(group.title).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shown(_ rows: [SidebarRow]) -> [SidebarRow] {
        model.isEditingSidebar ? rows : rows.filter { model.isVisible($0.key) }
    }

    private func expansion(_ section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { model.isEditingSidebar || model.isExpanded(section) },
            set: { if !model.isEditingSidebar { model.setExpanded(section, $0) } }
        )
    }

    // MARK: Headers

    private var header: some View {
        HStack {
            Text("Fonts")
            Spacer()
            Button(model.isEditingSidebar ? "Done" : "Edit") {
                withAnimation(.snappy) { model.isEditingSidebar.toggle() }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(model.isEditingSidebar ? .semibold : .regular))
            .foregroundStyle(model.isEditingSidebar ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(model.isEditingSidebar ? "Finish editing the sidebar" : "Choose which items appear in the sidebar")
        }
        .padding(.trailing, 10)
    }

    private func sectionHeader(_ section: SidebarSection) -> some View {
        HStack(spacing: 6) {
            if model.isEditingSidebar {
                checkbox(section.key, section.title)
            }
            Text(section.title)
                .opacity(model.isEditingSidebar && !model.isVisible(section.key) ? 0.45 : 1)
            Spacer()
            if !model.isEditingSidebar { addButton(section) }
        }
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func addButton(_ section: SidebarSection) -> some View {
        switch section {
        case .folders:
            plus("Add a folder of fonts") { model.presentAddFolderPanel() }
        case .sets:
            Menu {
                Button("New Set…") { model.prompt("New Set", confirm: "Create") { model.addSet(named: $0) } }
                Button("New Smart Set…") { model.editingSmartSet = SmartSet(name: "") }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("New set or smart set")
        case .tags:
            plus("New tag") { model.prompt("New Tag", confirm: "Create") { model.addTag(named: $0) } }
        case .characterSets:
            plus("New character set") { model.editingCharacterSet = CustomCharacterSet(name: "", characters: "") }
        case .foundries, .classifications:
            EmptyView()
        }
    }

    private func plus(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
    }

    private func checkbox(_ key: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) }))
            .toggleStyle(.checkbox)
            .labelsHidden()
    }

    // MARK: Rows

    private func row(_ row: SidebarRow, section: SidebarSection?) -> some View {
        let hidden = !model.isVisible(row.key) || (section.map { !model.isVisible($0.key) } ?? false)
        return HStack(spacing: 6) {
            if model.isEditingSidebar { checkbox(row.key, row.title) }
            Label(row.title, systemImage: row.icon).lineLimit(1)
        }
        .badge(row.badge > 0 ? Text(row.badge, format: .number) : nil)
        .opacity(model.isEditingSidebar && hidden ? 0.45 : 1)
        .tag(row.item)
        .contextMenu { menu(for: row) }
        .dropDestination(for: String.self) { names, _ in _ = model.handleDrop(names, on: row.item) }
    }

    @ViewBuilder
    private func menu(for row: SidebarRow) -> some View {
        switch row.item {
        case .folder(let id):
            if let folder = model.folder(id) {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                if id != WatchedFolder.deactivatedID {
                    Divider()
                    Picker("Fonts in This Folder", selection: Binding(
                        get: { folder.appName ?? "" },
                        set: { model.setAppName($0, forFolder: id) }
                    )) {
                        Text("Not activated until you activate them").tag("")
                        Text("Active in Adobe apps").tag("Adobe")
                        if let custom = folder.appName, custom != "Adobe" {
                            Text("Active in \(FaceState.appDescription(custom))").tag(custom)
                        }
                    }
                    Button("Remove Folder from Library") { model.removeFolder(id) }
                }
            }
        case .set(let id):
            if let set = model.data.sets.first(where: { $0.id == id }) {
                Button("Rename Set…") { model.prompt("Rename Set", text: set.name, confirm: "Rename") { model.renameSet(id, to: $0) } }
                Button("Delete Set") { model.deleteSet(id) }
            }
        case .smartSet(let id):
            if let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                Button("Edit Smart Set…") { model.editingSmartSet = smartSet }
                Button("Delete Smart Set") { model.deleteSmartSet(id) }
            }
        case .tag(let tag):
            Button("Rename Tag…") { model.prompt("Rename Tag", text: tag, confirm: "Rename") { model.renameTag(tag, to: $0) } }
            Button("Delete Tag") { model.deleteTag(tag) }
        case .foundry(let name):
            Button("Rename Foundry…") { model.prompt("Rename Foundry", text: name, confirm: "Rename") { model.renameFoundry(name, to: $0) } }
        case .characterSet(let id):
            if let custom = model.data.customCharacterSets.first(where: { $0.setID == id }) {
                Button("Edit Character Set…") { model.editingCharacterSet = custom }
                Button("Delete Character Set") { model.deleteCharacterSet(custom.id) }
            }
        case .system:
            Toggle("Show in Other Lists", isOn: Binding(get: { model.data.showSystemFonts }, set: { model.data.showSystemFonts = $0 }))
        default:
            EmptyView()
        }
        Divider()
        if model.isVisible(row.key) {
            Button("Hide from Sidebar") { model.setVisible(row.key, false) }
        }
        Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") { model.isEditingSidebar.toggle() }
    }
}
