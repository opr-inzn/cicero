import AppKit
import CiceroCore
import SwiftUI

/// The library sidebar. Edit puts a checkbox on every row and section to show or hide it; the same
/// choices are in Settings → Sidebar. Rows drag to a new place within their section (or character set
/// group), several at once when they're selected together. Sections stay in their order.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// What the list shows selected while the browser hasn't taken it yet (see `select`).
    @State private var pendingSelection: Set<SidebarItem>?
    @State private var pace = SelectionPace()

    var body: some View {
        // The rows are a view of their own: a list's selection updates whatever makes the list, and this
        // way that's just this, not every section and row.
        List(selection: Binding(get: { pendingSelection ?? model.selectedItems }, set: select)) {
            SidebarContent()
        }
        .listStyle(.sidebar)
        .animation(.snappy, value: model.isEditingSidebar)
        .contextMenu {
            Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") { model.isEditingSidebar.toggle() }
        }
        .onChange(of: model.selectedItems) {
            // Selected some other way (a new set, say) while the browser was catching up: that wins.
            guard pendingSelection != nil else { return }
            pace.commit?.cancel()
            pendingSelection = nil
        }
    }

    /// The browser shows a new selection at once, unless the selection changes quickly, as while arrowing
    /// through a long section: the list then moves on at each step and the browser takes the last one when
    /// it rests, instead of making every list along the way.
    private func select(_ items: Set<SidebarItem>) {
        let now = ContinuousClock.now
        let resting = pace.last.map { now - $0 > .milliseconds(300) } ?? true
        pace.last = now
        pace.commit?.cancel()
        let items = model.sidebarSelection(items, from: pendingSelection ?? model.selectedItems)
        guard !resting else {
            pendingSelection = nil
            return model.selectSidebarItems(items)
        }
        pendingSelection = items
        pace.commit = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            pendingSelection = nil
            model.selectSidebarItems(items)
        }
    }
}

/// When the sidebar's selection last changed, and the change waiting for the browser.
private final class SelectionPace {
    var last: ContinuousClock.Instant?
    var commit: Task<Void, Never>?
}

/// The sidebar's sections and rows.
private struct SidebarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let editing = model.isEditingSidebar
        Section {
            movableRows(model.libraryRows, in: "library", section: nil)
        } header: {
            header
        }
        ForEach(model.sections) { section in
            if editing || model.isVisible(section.key) {
                let groups = section == .characterSets ? model.characterSetGroups : []
                let rows = section == .characterSets ? [] : model.rows(for: section)
                Section(isExpanded: expansion(section)) {
                    if section == .characterSets {
                        characterSetGroups(groups)
                    } else {
                        movableRows(rows, in: section.rawValue, section: section)
                    }
                    if editing && rows.isEmpty && groups.isEmpty {
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

    /// Rows that drag to a new place among themselves.
    private func movableRows(_ rows: [SidebarRow], in list: String, section: SidebarSection?) -> some View {
        let shownRows = shown(rows)
        return ForEach(shownRows) { row($0, section: section) }
            .onMove { model.moveSidebarItems($0, to: $1, shown: shownRows.map(\.key), all: rows.map(\.key), in: list) }
    }

    /// Character sets in collapsible groups; a group whose sets are all hidden disappears. Groups move
    /// among themselves, and sets within their group.
    private func characterSetGroups(_ groups: [(id: String, title: String, rows: [SidebarRow])]) -> some View {
        let shownGroups = groups.filter { !shown($0.rows).isEmpty }
        func key(_ id: String) -> String { "charsetgroup.\(id)" }
        return ForEach(shownGroups, id: \.id) { group in
            DisclosureGroup(isExpanded: Binding(
                get: { model.isEditingSidebar || model.isGroupExpanded(group.id) },
                set: { if !model.isEditingSidebar { model.setGroupExpanded(group.id, $0) } }
            )) {
                movableRows(group.rows, in: key(group.id), section: .characterSets)
            } label: {
                // Only the chevron toggles a group in a selectable list; make the title do it too. A tap
                // rather than a button, so the title doesn't dim while it's pressed.
                Text(group.title)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture {
                        guard !model.isEditingSidebar else { return }
                        withAnimation(.snappy) { model.setGroupExpanded(group.id, !model.isGroupExpanded(group.id)) }
                    }
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
        // Only the chevron toggles a section in a sidebar list; make the whole title row do it too.
        .contentShape(.rect)
        .onTapGesture {
            let isExpanded = expansion(section)
            withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
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
                Button("New Application Set…") { model.newApplicationSet() }
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

    @ViewBuilder
    private func row(_ row: SidebarRow, section: SidebarSection?) -> some View {
        let hidden = !model.isVisible(row.key) || (section.map { !model.isVisible($0.key) } ?? false)
        let content = HStack(spacing: 6) {
            if model.isEditingSidebar { checkbox(row.key, row.title) }
            Label(row.title, systemImage: row.icon).lineLimit(1)
        }
        .badge(row.badge > 0 ? Text(row.badge, format: .number) : nil)
        .opacity(model.isEditingSidebar && hidden ? 0.45 : 1)
        .tag(row.item)
        .contextMenu { menu(for: row) }
        // Only rows that take family names are drop targets: being one makes a row much slower to appear,
        // which shows when a section opens or a long one scrolls.
        if model.takesFamilies(row.item) {
            content.dropDestination(for: String.self) { names, _ in _ = model.handleDrop(names, on: row.item) }
        } else {
            content
        }
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
                Button(set.apps.isEmpty ? "Activate with Apps…" : "Edit Apps…") { model.editingAppsForSet = id }
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
