import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

/// The library sidebar. Edit puts a checkbox on every row and section to show or hide it; the same
/// choices are in Settings → Sidebar. Rows drag to a new place within their section (or character set
/// group), several at once when they're selected together, and section titles drag onto each other.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// The section whose title is being dragged: its rows fold away under it until the drag ends.
    @State private var draggedSection: SidebarSection?
    /// The section whose title a dragged section is over.
    @State private var sectionDropTarget: SidebarSection?

    var body: some View {
        let editing = model.isEditingSidebar
        List(selection: Binding(get: { model.selectedItems }, set: { model.selectSidebarItems($0) })) {
            Section {
                movableRows(model.libraryRows, in: "library", section: nil)
            } header: {
                header
            }
            ForEach(model.sections) { section in
                if editing || model.isVisible(section.key) {
                    let rows = model.rows(for: section)
                    Section(isExpanded: expansion(section)) {
                        if section == .characterSets {
                            characterSetGroups
                        } else {
                            movableRows(rows, in: section.rawValue, section: section)
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

    /// Rows that drag to a new place among themselves.
    private func movableRows(_ rows: [SidebarRow], in list: String, section: SidebarSection?) -> some View {
        let shownRows = shown(rows)
        return ForEach(shownRows) { row($0, section: section) }
            .onMove { model.moveSidebarItems($0, to: $1, shown: shownRows.map(\.key), all: rows.map(\.key), in: list) }
    }

    /// Character sets in collapsible groups; a group whose sets are all hidden disappears. Groups move
    /// among themselves, and sets within their group.
    private var characterSetGroups: some View {
        let groups = model.characterSetGroups
        let shownGroups = groups.filter { !shown($0.rows).isEmpty }
        func key(_ id: String) -> String { "charsetgroup.\(id)" }
        return ForEach(shownGroups, id: \.id) { group in
            DisclosureGroup(isExpanded: Binding(
                get: { model.isEditingSidebar || model.isGroupExpanded(group.id) },
                set: { if !model.isEditingSidebar { model.setGroupExpanded(group.id, $0) } }
            )) {
                movableRows(group.rows, in: key(group.id), section: .characterSets)
            } label: {
                // Only the chevron toggles a group in a selectable list; make the title do it too.
                Button {
                    guard !model.isEditingSidebar else { return }
                    withAnimation(.snappy) { model.setGroupExpanded(group.id, !model.isGroupExpanded(group.id)) }
                } label: {
                    Text(group.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .onMove {
            model.moveSidebarItems($0, to: $1, shown: shownGroups.map { key($0.id) }, all: groups.map { key($0.id) },
                                   in: SidebarSection.characterSets.rawValue)
        }
    }

    private func shown(_ rows: [SidebarRow]) -> [SidebarRow] {
        model.isEditingSidebar ? rows : rows.filter { model.isVisible($0.key) }
    }

    private func expansion(_ section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { draggedSection != section && (model.isEditingSidebar || model.isExpanded(section)) },
            set: { if !model.isEditingSidebar && draggedSection == nil { model.setExpanded(section, $0) } }
        )
    }

    /// The payload of a section title's drag, made as the drag starts: the section's rows fold away
    /// under its title, so it moves as one, and come back when the mouse button goes up wherever it's dropped.
    private func beginDrag(of section: SidebarSection) -> SectionDrag {
        withAnimation(.snappy) { draggedSection = section }
        Task {
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            withAnimation(.snappy) { draggedSection = nil }
        }
        return SectionDrag(section: section.rawValue)
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
        .background {
            if sectionDropTarget == section {
                RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.2)).padding(.leading, -6)
            }
        }
        // A list drags a header as a picture of it and ignores drag previews, so the rows fold away instead.
        .draggable(beginDrag(of: section))
        .dropDestination(for: SectionDrag.self) { drags, _ in
            guard let dragged = drags.first.flatMap({ SidebarSection(rawValue: $0.section) }), dragged != section else { return false }
            withAnimation(.snappy) { model.moveSection(dragged, onto: section) }
            return true
        } isTargeted: { targeted in
            if targeted { sectionDropTarget = section } else if sectionDropTarget == section { sectionDropTarget = nil }
        }
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
        case .folder(WatchedFolder.adobeAppsID):
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(WatchedFolder.appFontFolders().map(\.url)) }
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
        case .foundry(let name):
            Button("Rename Foundry…") { model.prompt("Rename Foundry", text: name, confirm: "Rename") { model.renameFoundry(name, to: $0) } }
        case .characterSet(let id):
            if let custom = model.data.customCharacterSets.first(where: { $0.setID == id }) {
                Button("Edit Character Set…") { model.editingCharacterSet = custom }
                Button("Delete Character Set") { model.deleteCharacterSet(custom.id) }
            }
        default:
            EmptyView()
        }
        if model.canExport(row.item) {
            Divider()
            Button("Export Fonts…") { model.exportFonts(in: row.item, named: row.title) }
        }
        Divider()
        if model.isVisible(row.key) {
            Button("Hide from Sidebar") { model.setVisible(row.key, false) }
        }
        Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") { model.isEditingSidebar.toggle() }
    }
}

/// A section title being dragged onto another.
private nonisolated struct SectionDrag: Codable, Transferable {
    var section: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroSidebarSection)
    }
}

private extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroSidebarSection = UTType(exportedAs: "local.cicero.sidebar-section")
}
