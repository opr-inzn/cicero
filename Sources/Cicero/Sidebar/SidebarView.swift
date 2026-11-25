import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingSelection: Set<SidebarItem>?
    @State private var pace = SelectionPace()
    @State private var highlight = SidebarHighlight()
    @State private var drag = SidebarDrag()
    @State private var fit = SidebarFit()

    var body: some View {
        let shown = pendingSelection ?? model.selectedItems
        // The rows are a view of their own: a list's selection updates whatever makes the list, and this way that's just this, not every section and row.
        List(selection: Binding(get: { shown }, set: select)) {
            SidebarContent(highlight: highlight, drag: drag, fit: fit)
        }
        .listStyle(.sidebar)
        .outsideFileDrops(isOver: { if highlight.filesOver != $0 { highlight.filesOver = $0 } }) { urls in
            highlight.filesOver = false
            model.openOnSidebar(urls)
        }
        .overlay {
            if highlight.filesOver {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .background { SidebarSnapReader(fit: fit) }
        .onChange(of: shown, initial: true) { highlight.selected = shown }
        .contextMenu { EditSidebarButton(model: model) }
        .onChange(of: model.selectedItems) {
            guard pendingSelection != nil else { return }
            pace.commit?.cancel()
            pendingSelection = nil
        }
    }

    private func select(_ items: Set<SidebarItem>) {
        let now = ContinuousClock.now
        let resting = pace.last.map { now - $0 > .milliseconds(300) } ?? true
        pace.last = now
        pace.commit?.cancel()
        let items = model.sidebarSelection(items, from: pendingSelection ?? model.selectedItems)
        highlight.selected = items
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

private final class SelectionPace {
    var last: ContinuousClock.Instant?
    var commit: Task<Void, Never>?
}

private struct SidebarContent: View {
    @Environment(AppModel.self) private var model
    // Passed in, not through the environment, which a row's background doesn't get.
    let highlight: SidebarHighlight
    let drag: SidebarDrag
    let fit: SidebarFit
    @State private var draggedGroup: String?
    @State private var groupDropTarget: String?

    var body: some View {
        let editing = model.isEditingSidebar
        let coverageGroups = model.characterSetGroups
        let indent = chevronRoom(coverageGroups, editing: editing)
        Section {
            movableRows(model.libraryRows, in: "library", section: nil, indent: indent)
        } header: {
            header
        }
        .notCollapsible()
        ForEach(model.sections) { section in
            if editing || model.isVisible(section.key) {
                let groups = section == .characterSets ? coverageGroups : []
                let rows = section == .characterSets ? [] : model.rows(for: section)
                Section(isExpanded: expansion(section)) {
                    if section == .classifications && model.asksAboutGuessing && !editing {
                        OrganizeRow().padding(.leading, -indent)
                    }
                    if section == .characterSets {
                        characterSetGroups(groups)
                    } else {
                        movableRows(rows, in: section.rawValue, section: section, indent: indent)
                    }
                    if editing && rows.isEmpty && groups.isEmpty {
                        Text("Nothing here yet")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, -indent)
                            .selectionDisabled()
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
    }

    private func movableRows(_ rows: [SidebarRow], in list: String, section: SidebarSection?, indent: CGFloat) -> some View {
        let shownRows = shown(rows)
        let items = shownRows.map(\.item)
        let index = Dictionary(shownRows.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        return ForEach(shownRows) { shownRow in
            let i = index[shownRow.key] ?? 0
            row(shownRow, section: section, previous: i > 0 ? items[i - 1] : nil, next: i + 1 < items.count ? items[i + 1] : nil, indent: indent)
        }
            .onMove { source, destination in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model.moveSidebarItems(source, to: destination, shown: shownRows.map(\.key), all: rows.map(\.key), in: list)
                }
            }
    }

    private func characterSetGroups(_ groups: [(id: String, title: String, rows: [SidebarRow])]) -> some View {
        let shownGroups = groups.filter { !shown($0.rows).isEmpty }
        func key(_ id: String) -> String { "charsetgroup.\(id)" }
        func move(_ dragged: String, onto target: String) {
            let keys = shownGroups.map { key($0.id) }
            guard let from = keys.firstIndex(of: key(dragged)), let to = keys.firstIndex(of: key(target)), from != to else { return }
            model.moveSidebarItems([from], to: from < to ? to + 1 : to, shown: keys, all: groups.map { key($0.id) },
                                   in: SidebarSection.characterSets.rawValue)
        }
        return ForEach(shownGroups, id: \.id) { group in
            DisclosureGroup(isExpanded: Binding(
                get: { model.isGroupExpanded(group.id) },
                set: { model.setGroupExpanded(group.id, $0) }
            )) {
                movableRows(group.rows, in: key(group.id), section: .characterSets, indent: 0)
            } label: {
                // In a selectable list only the chevron toggles a group: a tap, not a button, so the title doesn't dim while pressed. Coloured here, or the list greys it while another window is in front.
                Label {
                    Text(group.title).lineLimit(1).sidebarTitle(group.title, key: key(group.id), fit: fit)
                } icon: {
                    Image(systemName: "character.book.closed")
                }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy) { model.setGroupExpanded(group.id, !model.isGroupExpanded(group.id)) }
                    }
                    .background {
                        if groupDropTarget == group.id {
                            RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.2)).padding(.horizontal, -6)
                        }
                    }
                    .modifier(GroupDragSource { beginDrag(of: group.id) })
                    .modifier(GroupDrop(group: group.id, dragged: draggedGroup, target: $groupDropTarget) { dragged in
                        withAnimation(.snappy) { move(dragged, onto: group.id) }
                    })
                    .contextMenu {
                        if group.rows.contains(where: { model.isVisible($0.key) }) {
                            Button("Hide from Sidebar", systemImage: "eye.slash") { model.hideGroup(group.id) }
                        }
                    }
            }
        }
    }

    private func beginDrag(of group: String) -> GroupDrag {
        draggedGroup = group
        Task {
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(250))
            if draggedGroup == group { draggedGroup = nil }
            groupDropTarget = nil
        }
        return GroupDrag(group: group)
    }

    private func shown(_ rows: [SidebarRow]) -> [SidebarRow] {
        model.isEditingSidebar ? rows : rows.filter { model.isVisible($0.key) }
    }

    private func expansion(_ section: SidebarSection) -> Binding<Bool> {
        Binding(get: { model.isExpanded(section) }, set: { model.setExpanded(section, $0) })
    }

    // MARK: Headers

    private var header: some View {
        HStack {
            Text("Library")
            Spacer()
            Button(model.isEditingSidebar ? "Done" : "Edit") { model.isEditingSidebar.toggle() }
            .buttonStyle(StillButtonStyle())
            .font(.subheadline.weight(model.isEditingSidebar ? .semibold : .regular))
            .foregroundStyle(model.isEditingSidebar ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(model.isEditingSidebar ? "Finish editing the sidebar" : "Choose which items appear in the sidebar")
        }
        .padding(.trailing, 10)
        // Behind a header inside the list, so the outline view is among its superviews.
        .background(OutlineViewSetup(drag: drag, highlight: highlight, isPageOpen: { [model] in model.openFamilyID != nil }, isEditing: { [model] in model.isEditingSidebar }, reselect: { [model] in if model.openFamilyID != nil { model.openFamilyID = nil } else { model.scrollsToTop += 1 } }) { [model] in model.dragOutOfSidebar($0) })
    }

    private func sectionHeader(_ section: SidebarSection) -> some View {
        SectionHeader(title: section.title, key: section.key, fit: fit, isExpanded: expansion(section),
                      isDimmed: model.isEditingSidebar && !model.isVisible(section.key)) {
            if model.isEditingSidebar {
                checkbox(section.key, section.title)
            }
        } trailing: {
            if !model.isEditingSidebar { addButton(section) }
        }
    }

    @ViewBuilder
    private func addButton(_ section: SidebarSection) -> some View {
        switch section {
        case .folders:
            plus("Add a location") { model.presentAddFolderPanel() }
        case .sets:
            Menu {
                Button("New Folder", systemImage: "folder") { model.prompt("New Folder", confirm: "Create") { model.addSet(named: $0) } }
                Button("New Smart Folder", systemImage: "gearshape") { model.ask { $0.editingSmartSet = SmartSet(name: "") } }
                Button("New App Folder", systemImage: "app.badge.checkmark") { model.newApplicationSet() }
            } label: {
                Label("New folder, smart folder or app folder", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("New folder, smart folder or app folder")
        case .tags:
            plus("New tag") { model.newTag() }
        case .characterSets:
            plus("New coverage set") { model.ask { $0.editingCharacterSet = CustomCharacterSet(name: "", characters: "") } }
        case .classifications:
            plus("New classification") { model.newClassification() }
        case .foundries:
            EmptyView()
        }
    }

    private func plus(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(help, systemImage: "plus")
                .labelStyle(.iconOnly)
        }
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

    // The list indents every row as far as a disclosure chevron only while a row with a chevron, a coverage group, is in it, not inside a closed section.
    private func chevronRoom(_ coverageGroups: [(id: String, title: String, rows: [SidebarRow])], editing: Bool) -> CGFloat {
        let coverage = SidebarSection.characterSets
        let hasGroup = (editing || model.isVisible(coverage.key)) && model.isExpanded(coverage)
            && coverageGroups.contains { !shown($0.rows).isEmpty }
        return hasGroup ? 14 : 0
    }

    @ViewBuilder
    private func row(_ row: SidebarRow, section: SidebarSection?, previous: SidebarItem?, next: SidebarItem?, indent: CGFloat) -> some View {
        let hidden = !model.isVisible(row.key) || (section.map { !model.isVisible($0.key) } ?? false)
        let content = HStack(spacing: 6) {
            if model.isEditingSidebar { checkbox(row.key, row.title).disabled(!row.canHide) }
            SidebarLabel(row: row, highlight: highlight, fit: fit)
            if row.badge > 0 {
                Spacer(minLength: 4)
                Text(row.badge.plain).foregroundStyle(.secondary).monospacedDigit().padding(.trailing, 4)
            }
        }
        .opacity(model.isEditingSidebar && hidden ? 0.45 : 1)
        .padding(.leading, -indent)
        .listRowBackground(SidebarRowBackground(item: row.item, previous: previous, next: next, highlight: highlight))
        .tag(row.item)
        .contextMenu { SidebarRowMenu(row: row, model: model, highlight: highlight) }
        // Asked for as the list starts dragging the row, which tells which rows a drag has.
        .itemProvider { drag.provider(for: row) }
        // Only rows that take families, or styles of them, are drop targets: being one makes a row much slower to appear.
        if model.takesFamilies(row.item) {
            content
                .background(FontDropTarget(isOver: { isOver in
                    if isOver {
                        if highlight.dropTarget != row.item { highlight.dropTarget = row.item }
                    } else if highlight.dropTarget == row.item {
                        highlight.dropTarget = nil
                    }
                }, files: .init(isOver: { if highlight.filesOver != $0 { highlight.filesOver = $0 } }) { urls in
                    highlight.filesOver = false
                    model.openOnSidebar(urls)
                }) { drags in
                    highlight.dropTarget = nil
                    _ = model.handleDrop(drags, on: row.item)
                })
        } else {
            content
        }
    }
}

private struct SidebarRowMenu: View {
    let row: SidebarRow
    let model: AppModel
    let highlight: SidebarHighlight

    var body: some View {
        let rows = model.menuTargets(of: row, selected: highlight.selected)
        if rows.count > 1 {
            Text("\(rows.count.plain) \(noun)")
        }
        switch row.item {
        case .temporary:
            if rows.count == 1 {
                Button("Activate Permanently", systemImage: "checkmark.seal") { model.activateFonts(in: rows) }
                Button("Deactivate", systemImage: "xmark.seal") { model.deactivateFonts(in: [row.item]) }
            }
        case .folder:
            locationItems(rows.compactMap { if case .folder(let id) = $0.item { id } else { nil } })
        case .set, .smartSet:
            folderItems(rows)
        case .tag:
            tagItems(rows.compactMap { if case .tag(let name) = $0.item { name } else { nil } })
        case .foundry(let name):
            if rows.count == 1 {
                Button("Rename", systemImage: "pencil") {
                    model.prompt("Rename Foundry", text: name, confirm: "Rename") { model.renameFoundry(name, to: $0) }
                }
            }
        case .classification(let name):
            if rows.count == 1 {
                Button("Rename", systemImage: "pencil") {
                    model.prompt("Rename Classification", text: name, confirm: "Rename") { model.renameClassification(name, to: $0) }
                }
            }
            let own = rows.compactMap { if case .classification(let name) = $0.item { name } else { nil } }.filter(model.isUserClassification)
            if !own.isEmpty {
                Button(own.count == 1 ? "Delete Classification" : "Delete Classifications", systemImage: "trash") {
                    model.deleteClassifications(Set(own))
                }
            }
        case .characterSet:
            let ids = Set(rows.compactMap { if case .characterSet(let id) = $0.item { id } else { nil } })
            let custom = model.data.customCharacterSets.filter { ids.contains($0.setID) }
            if rows.count == 1, let set = custom.first {
                Button("Edit Coverage Set", systemImage: "pencil") { model.ask { $0.editingCharacterSet = set } }
            }
            if !custom.isEmpty {
                Button(custom.count == 1 ? "Delete Coverage Set" : "Delete Coverage Sets", systemImage: "trash") {
                    model.ask { $0.deletingCharacterSets = custom }
                }
            }
        default:
            EmptyView()
        }
        let exported = rows.filter { model.canExport($0.item) }
        if !exported.isEmpty {
            Divider()
            Button("Export Fonts", systemImage: "square.and.arrow.up") { model.exportFonts(in: exported) }
        }
        let shown = rows.filter { $0.canHide && model.isVisible($0.key) }
        if !shown.isEmpty {
            Divider()
            Button("Hide from Sidebar", systemImage: "eye.slash") { model.hide(shown.map(\.key)) }
        }
    }

    private var noun: String {
        switch row.item {
        case .folder: "Locations"
        case .set, .smartSet: "Folders"
        case .tag: "Tags"
        case .foundry: "Foundries"
        case .classification: "Classifications"
        case .characterSet: "Coverage Sets"
        case .all, .active, .inactive, .temporary, .system, .recent, .problems: "Items"
        }
    }

    @ViewBuilder
    private func locationItems(_ ids: [UUID]) -> some View {
        if ids.count == 1, let id = ids.first {
            Button("Rename", systemImage: "pencil") { highlight.renaming = .folder(id) }
            switch id {
            case WatchedFolder.adobeFontsID:
                Button("Manage in Creative Cloud", systemImage: "arrow.up.forward.app") { CreativeCloud.open() }
            case WatchedFolder.adobeAppsID, WatchedFolder.addedFilesID:
                revealButton(ids)
            default:
                if let folder = model.folder(id) {
                    revealButton(ids)
                    Divider()
                    FolderActivationPicker(folder: folder) {
                        model.prompt("Active in Specific App", confirm: "OK", requiresText: true) { model.setActivation(ofFolder: id, active: false, app: $0) }
                    }
                }
            }
        } else {
            revealButton(ids.filter { $0 != WatchedFolder.adobeFontsID })
        }
        let removable = ids.filter(model.isRemovableFolder)
        if !removable.isEmpty {
            if ids.count > 1 { Divider() }
            Button(removable.count == 1 ? "Remove Location" : "Remove Locations", systemImage: "folder.badge.minus") {
                model.removeFolders(Set(removable))
            }
        }
    }

    @ViewBuilder
    private func revealButton(_ ids: [UUID]) -> some View {
        if !ids.isEmpty {
            Button("Reveal in Finder", systemImage: "finder") {
                NSWorkspace.shared.activateFileViewerSelecting(ids.flatMap(model.finderURLs))
            }
        }
    }

    @ViewBuilder
    private func folderItems(_ rows: [SidebarRow]) -> some View {
        let sets = Set(rows.compactMap { if case .set(let id) = $0.item { id } else { nil } })
        let smartSets = Set(rows.compactMap { if case .smartSet(let id) = $0.item { id } else { nil } })
        let kind = sets.isEmpty ? "Smart Folder" : "Folder"
        let kinds = rows.count == 1 ? kind : kind + "s"
        let single = rows.count == 1 ? sets.first.flatMap { id in model.data.sets.first { $0.id == id } } : nil
        Button("Activate", systemImage: "checkmark.seal") { model.activateFonts(in: rows) }
        Button("Activate Temporarily", systemImage: "clock") { model.activateFontsTemporarily(in: rows.map(\.item)) }
        if let single {
            Button(single.apps.isEmpty ? "Activate with Apps" : "Edit Apps", systemImage: "app.badge.checkmark") { model.ask { $0.editingAppsForSet = single.id } }
        }
        Button("Deactivate", systemImage: "xmark.seal") { model.deactivateFonts(in: rows.map(\.item)) }
        Divider()
        if rows.count == 1 {
            if let single {
                Button("Rename", systemImage: "pencil") { highlight.renaming = .set(single.id) }
            } else if let id = smartSets.first, let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                Button("Edit Smart Folder", systemImage: "slider.horizontal.3") { model.ask { $0.editingSmartSet = smartSet } }
            }
        }
        Button("Delete \(kinds)", systemImage: "trash") {
            if !sets.isEmpty { model.deleteSets(sets) }
            if !smartSets.isEmpty { model.deleteSmartSets(smartSets) }
        }
    }

    @ViewBuilder
    private func tagItems(_ names: [String]) -> some View {
        if names.count == 1, let name = names.first {
            Button("Rename", systemImage: "pencil") { highlight.renaming = .tag(name) }
        }
        Menu {
            Toggle("None", isOn: Binding(
                get: { names.allSatisfy { model.data.tagColors[$0] == nil } },
                set: { if $0 { model.setColor(nil, forTags: names) } }
            ))
            Divider()
            ForEach(TagColor.allCases, id: \.self) { color in
                Toggle(isOn: Binding(
                    get: { names.allSatisfy { model.data.tagColors[$0] == color } },
                    set: { if $0 { model.setColor(color, forTags: names) } }
                )) {
                    Label { Text(color.title) } icon: { Image(nsImage: color.menuImage) }
                        .labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        Button(names.count == 1 ? "Delete Tag" : "Delete Tags", systemImage: "trash") { model.deleteTags(Set(names)) }
    }
}

private struct EditSidebarButton: View {
    let model: AppModel

    var body: some View {
        Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar",
               systemImage: model.isEditingSidebar ? "checkmark" : "sidebar.left") { model.isEditingSidebar.toggle() }
    }
}

private struct SectionHeader<Leading: View, Trailing: View>: View {
    let title: String
    let key: String
    let fit: SidebarFit
    @Binding var isExpanded: Bool
    let isDimmed: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(title)
                .sidebarTitle(title, key: key, fit: fit)
                .opacity(isDimmed ? 0.45 : 1)
                .accessibilityAction(named: isExpanded ? "Collapse" : "Expand", toggle)
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .transaction { $0.animation = nil }
                .frame(width: 14)
                .padding(.trailing, 4)
                .opacity(isHovered ? 1 : 0)
                .accessibilityHidden(true)
            trailing
        }
        .padding(.trailing, 10)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: toggle)
    }

    private func toggle() {
        withAnimation(.snappy) { isExpanded.toggle() }
    }
}

@Observable
final class SidebarHighlight {
    var selected: Set<SidebarItem> = []
    var dropTarget: SidebarItem?
    var filesOver = false
    var renaming: SidebarItem?
}

private struct OrganizeRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.ask { $0.showsGuessingQuestion = true } } label: {
            Label { Text("Classify Fonts").fontWeight(.semibold).foregroundStyle(Color.solar) } icon: {
                Image(systemName: "character.magnify").foregroundStyle(Color.solar)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .help("Let Cicero classify fonts without a classification")
    }
}

private struct SidebarLabel: View {
    @Environment(\.appearsActive) private var appearsActive
    let row: SidebarRow
    let highlight: SidebarHighlight
    let fit: SidebarFit

    var body: some View {
        let style: AnyShapeStyle = highlight.dropTarget == row.item ? AnyShapeStyle(.white)
            : highlight.selected.contains(row.item) ? AnyShapeStyle(Color.accentColor.opacity(appearsActive ? 1 : 0.45))
            : appearsActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        // On the symbol too: a sidebar styles symbols itself. A tag's dot keeps its own colour.
        Label {
            if highlight.renaming == row.item {
                SidebarRenameField(row: row, highlight: highlight)
            } else {
                Text(row.title).lineLimit(1).foregroundStyle(style).sidebarTitle(row.title, key: row.key, fit: fit)
            }
        } icon: { SidebarIcon(row: row).foregroundStyle(style).opacity(row.color != nil && !appearsActive ? 0.45 : 1) }
    }
}

private struct SidebarRenameField: View {
    @Environment(AppModel.self) private var model
    let row: SidebarRow
    let highlight: SidebarHighlight
    @State private var name: String

    init(row: SidebarRow, highlight: SidebarHighlight) {
        self.row = row
        self.highlight = highlight
        _name = State(initialValue: row.title)
    }

    var body: some View {
        RenameTextField(text: $name, onCommit: commit, onCancel: { highlight.renaming = nil })
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        guard highlight.renaming == row.item else { return }
        highlight.renaming = nil
        switch row.item {
        case .set(let id): model.renameSet(id, to: name)
        case .folder(let id): model.renameFolder(id, to: name)
        case .tag(let old): model.renameTag(old, to: name)
        default: break
        }
    }
}

private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> FittingTextField {
        let field = FittingTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FittingTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: FittingTextField, context: Context) -> CGSize? {
        let size = field.fittingSize(for: text)
        return CGSize(width: min(size.width, proposal.width ?? size.width), height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField

        init(parent: RenameTextField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ note: Notification) {
            parent.onCommit()
        }
    }
}

private final class FittingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    func fittingSize(for text: String) -> CGSize {
        let measure = NSTextFieldCell(textCell: text.isEmpty ? " " : text)
        measure.font = font
        let size = measure.cellSize
        return CGSize(width: ceil(size.width) + 6, height: ceil(size.height))
    }
}

private extension SidebarItem {
    var isLibrary: Bool {
        switch self {
        case .all, .active, .inactive, .temporary, .recent, .system, .problems: true
        default: false
        }
    }

    var isRenamable: Bool {
        switch self {
        case .set, .tag, .folder: true
        default: false
        }
    }
}

private struct SidebarRowBackground: View {
    let item: SidebarItem
    let previous: SidebarItem?
    let next: SidebarItem?
    let highlight: SidebarHighlight

    var body: some View {
        let isTarget = highlight.dropTarget == item
        let isSelected = highlight.selected.contains(item)
        if isTarget {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor)
                .padding(.horizontal, 10)
        } else if isSelected {
            let joinsAbove = joins(previous)
            let joinsBelow = joins(next)
            UnevenRoundedRectangle(topLeadingRadius: joinsAbove ? 0 : 8, bottomLeadingRadius: joinsBelow ? 0 : 8,
                                   bottomTrailingRadius: joinsBelow ? 0 : 8, topTrailingRadius: joinsAbove ? 0 : 8,
                                   style: .continuous)
                // Not .quaternary, which turns white on a selected row once a text field inside the sidebar takes focus.
                .fill(Color.sidebarSelection)
                .overlay(alignment: .top) {
                    if joinsAbove {
                        Rectangle().fill(Color.selectionSeparator).frame(height: 1).padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 10)
        }
    }

    private func joins(_ neighbour: SidebarItem?) -> Bool {
        guard let neighbour else { return false }
        return highlight.selected.contains(neighbour) && highlight.dropTarget != neighbour
    }
}

struct SidebarIcon: View {
    let row: SidebarRow

    var body: some View {
        if let color = row.color {
            // A picture, not a symbol in the colour, which the list darkens on the accent colour behind a row families are over.
            Image(nsImage: color.menuImage)
                .accessibilityLabel(color.title)
        } else {
            Image(systemName: row.icon)
        }
    }
}

private nonisolated struct GroupDrag: Codable, Transferable {
    var group: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroSidebarGroup)
    }
}

private extension UTType {
    nonisolated static let ciceroSidebarGroup = UTType(exportedAs: "com.maximilianinzinger.cicero.sidebar-group")
}

private struct GroupDragSource: ViewModifier {
    let payload: @MainActor () -> GroupDrag

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.draggable(payload())
        } else {
            let make = payload
            // On macOS 15 a title dragged with `draggable` never leaves the list.
            content.onDrag {
                let provider = NSItemProvider()
                provider.register(MainActor.assumeIsolated { make() })
                return provider
            }
        }
    }
}

private struct GroupDrop: ViewModifier {
    let group: String
    let dragged: String?
    @Binding var target: String?
    let move: (String) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: false, allowMove: true),
                                                     operationsOutsideApp: .init(allowCopy: false)))
                .dropDestination(for: GroupDrag.self) { drags, _ in
                    guard let dragged = drags.first?.group, dragged != group else { return }
                    move(dragged)
                }
                .dropConfiguration { _ in DropConfiguration(operation: dragged == group ? .forbidden : .move) }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active:
                        if dragged != group { target = group }
                    default:
                        if target == group { target = nil }
                    }
                }
        } else {
            content.onDrop(of: [.ciceroSidebarGroup], delegate: Delegate(group: group, dragged: dragged, target: $target, move: move))
        }
    }

    private struct Delegate: DropDelegate {
        let group: String
        let dragged: String?
        @Binding var target: String?
        let move: (String) -> Void

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: dragged == group ? .forbidden : .move)
        }

        func dropEntered(info: DropInfo) {
            if dragged != group { target = group }
        }

        func dropExited(info: DropInfo) {
            if target == group { target = nil }
        }

        func performDrop(info: DropInfo) -> Bool {
            if target == group { target = nil }
            guard let dragged, dragged != group else { return false }
            move(dragged)
            return true
        }
    }
}

private struct OutlineViewSetup: NSViewRepresentable {
    let drag: SidebarDrag
    let highlight: SidebarHighlight
    let isPageOpen: () -> Bool
    let isEditing: () -> Bool
    let reselect: () -> Void
    let hide: ([SidebarRow]) -> Void

    func makeNSView(context: Context) -> NSView {
        drag.hide = hide
        return Marker(drag: drag, highlight: highlight, isPageOpen: isPageOpen, isEditing: isEditing, reselect: reselect)
    }

    func updateNSView(_ nsView: NSView, context: Context) { drag.hide = hide }

    private final class Marker: NSView {
        let drag: SidebarDrag
        let highlight: SidebarHighlight
        let isPageOpen: () -> Bool
        let isEditing: () -> Bool
        let reselect: () -> Void

        init(drag: SidebarDrag, highlight: SidebarHighlight, isPageOpen: @escaping () -> Bool, isEditing: @escaping () -> Bool, reselect: @escaping () -> Void) {
            self.drag = drag
            self.highlight = highlight
            self.isPageOpen = isPageOpen
            self.isEditing = isEditing
            self.reselect = reselect
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSOutlineView) { view = current.superview }
            guard let outline = view as? NSOutlineView else { return }
            outline.selectionHighlightStyle = .none
            outline.refusesFirstResponder = true
            // Without the answers, a row dragged out of the list stops Cicero.
            if SidebarDataSource.answer(for: outline, drag: drag) { outline.draggingDestinationFeedbackStyle = .gap }
            SidebarDoubleClick.install(on: outline, highlight: highlight, isEditing: isEditing)
            // A click on the row already selected doesn't reach the list's selection at all.
            if !outline.gestureRecognizers.contains(where: { $0 is ReselectClick }) {
                let click = ReselectClick()
                click.delaysPrimaryMouseButtonEvents = false
                click.onReselect = reselect
                click.isReselectable = { [highlight, isPageOpen] in highlight.selected.count == 1 && (isPageOpen() || highlight.selected.allSatisfy(\.isLibrary)) }
                outline.addGestureRecognizer(click)
            }
            SidebarDrag.prepare(in: outline)
        }
    }
}

private final class SidebarDoubleClick {
    private static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private weak var outline: NSOutlineView?
    private nonisolated(unsafe) var monitor: Any?
    var highlight: SidebarHighlight?
    var isEditing: () -> Bool = { false }

    static func install(on outline: NSOutlineView, highlight: SidebarHighlight, isEditing: @escaping () -> Bool) {
        let handler = (objc_getAssociatedObject(outline, key) as? SidebarDoubleClick) ?? {
            let created = SidebarDoubleClick(outline: outline)
            objc_setAssociatedObject(outline, key, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return created
        }()
        handler.highlight = highlight
        handler.isEditing = isEditing
    }

    private init(outline: NSOutlineView) {
        self.outline = outline
        // Local monitor instead of NSClickGestureRecognizer: NSOutlineView keeps mouseUp in its tracking loop, and trackpads follow mouseUp with pressure events.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) {
        guard event.clickCount == 2, !isEditing(),
              let outline, let window = outline.window, event.window === window, window.isKeyWindow,
              event.modifierFlags.isDisjoint(with: [.command, .shift, .control, .option]) else { return }
        let point = outline.convert(event.locationInWindow, from: nil)
        guard outline.visibleRect.contains(point) else { return }
        if let superview = outline.superview,
           let hit = outline.hitTest(superview.convert(event.locationInWindow, from: nil)),
           hit is NSButton || hit is NSTextView {
            return
        }
        let row = outline.row(at: point)
        guard row >= 0, let item = outline.item(atRow: row),
              outline.delegate?.outlineView?(outline, isGroupItem: item) != true else { return }
        let start = NSEvent.mouseLocation
        RunLoop.main.perform(inModes: [.default]) { [weak self, weak outline] in
            MainActor.assumeIsolated {
                guard let self, let outline, !self.isEditing(), outline.window?.isKeyWindow == true,
                      hypot(NSEvent.mouseLocation.x - start.x, NSEvent.mouseLocation.y - start.y) < 6,
                      outline.selectedRowIndexes == IndexSet(integer: row),
                      let highlight = self.highlight, highlight.renaming == nil,
                      highlight.selected.count == 1, let selected = highlight.selected.first, selected.isRenamable
                else { return }
                highlight.renaming = selected
            }
        }
    }
}

private final class ReselectClick: NSClickGestureRecognizer {
    var onReselect: () -> Void = {}
    var isReselectable: () -> Bool = { false }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Never recognized, so it can't hold back the double click that renames.
        state = .failed
        guard event.clickCount == 1, let outline = view as? NSOutlineView, outline.window?.isKeyWindow == true, isReselectable(),
              event.modifierFlags.isDisjoint(with: [.command, .shift, .control, .option]) else { return }
        let row = outline.row(at: outline.convert(event.locationInWindow, from: nil))
        guard row >= 0, outline.selectedRowIndexes == IndexSet(integer: row) else { return }
        let start = event.locationInWindow
        // The outline view tracks the mouse until it goes up and keeps that event, so this recognizer never ends: look once the press is over.
        RunLoop.main.perform(inModes: [.default]) { [onReselect] in
            guard let up = NSApp.currentEvent, up.type == .leftMouseUp, hypot(up.locationInWindow.x - start.x, up.locationInWindow.y - start.y) < 4 else { return }
            onReselect()
        }
    }
}

final class SidebarDrag {
    var hide: ([SidebarRow]) -> Void = { _ in }
    private var rows: [SidebarRow] = []
    private var lastAsked: ContinuousClock.Instant?
    private var session: NSDraggingSession?
    private var listFrame = NSRect.zero
    private var pictures: [NSImage?] = []

    func provider(for row: SidebarRow) -> NSItemProvider {
        let now = ContinuousClock.now
        // The list asks each row it drags for an item, and on macOS 26 also as the mouse goes down on one, so a drag's rows are the last ones asked for.
        if lastAsked.map({ now - $0 > .milliseconds(500) }) ?? true { rows = [] }
        lastAsked = now
        rows.append(row)
        return NSItemProvider()
    }

    func began(_ session: NSDraggingSession, count: Int, in outline: NSOutlineView) {
        guard count <= rows.count, let frame = Self.frame(of: outline) else { return rows = [] }
        rows = Array(rows.suffix(count))
        self.session = session
        listFrame = frame
        // Let go where nothing changes, the rows are there again at once: AppKit slid the picture back there and faded it out first, with the place empty.
        session.animatesToStartingPositionsOnCancelOrFail = false
        pictures = []
        session.enumerateDraggingItems(options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            self.dress(item, at: index, in: outline)
        }
    }

    func redraw(_ info: NSDraggingInfo, in outline: NSOutlineView) {
        guard session != nil, info.draggingSource as AnyObject? === outline else { return }
        info.enumerateDraggingItems(options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            self.dress(item, at: index, in: outline)
        }
    }

    private func dress(_ item: NSDraggingItem, at index: Int, in outline: NSOutlineView) {
        guard rows.indices.contains(index) else { return }
        let size = item.draggingFrame.size
        while pictures.count <= index { pictures.append(nil) }
        if pictures[index]?.size != size { pictures[index] = Self.picture(of: rows[index], size: size, in: outline) }
        guard let picture = pictures[index] else { return }
        item.imageComponentsProvider = {
            let component = NSDraggingImageComponent(key: .icon)
            component.contents = picture
            component.frame = NSRect(origin: .zero, size: size)
            return [component]
        }
    }

    static func prepare(in outline: NSOutlineView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak outline] in
            guard let outline else { return }
            _ = picture(of: SidebarRow(key: "", title: "Aa", icon: "folder", item: .all), size: NSSize(width: 120, height: 28), in: outline)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    private static func picture(of row: SidebarRow, size: NSSize, in outline: NSOutlineView) -> NSImage? {
        let (fontSize, leading): (CGFloat, CGFloat) = switch outline.effectiveRowSizeStyle {
        case .small: (11, 3.5)
        case .large: (15, 3.5)
        default: (13, 4.5)
        }
        let isDark = outline.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(content: Label { Text(row.title).lineLimit(1) } icon: { SidebarIcon(row: row) }
            .font(.system(size: fontSize))
            .foregroundStyle(.primary)
            .padding(.leading, leading)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .opacity(0.88)
            .environment(\.colorScheme, isDark ? .dark : .light))
        renderer.scale = outline.window?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    func moved(to point: NSPoint) {
        guard session != nil, rows.contains(where: \.canHide) else { return }
        let isOutside = !listFrame.contains(point)
        if isOutside {
            if NSCursor.current != NSCursor.disappearingItem { NSCursor.disappearingItem.set() }
        } else if NSCursor.current == NSCursor.disappearingItem {
            NSCursor.arrow.set()
        }
    }

    func ended(at point: NSPoint, operation: NSDragOperation) {
        let rows = session == nil ? [] : rows.filter(\.canHide)
        session = nil
        self.rows = []
        pictures = []
        lastAsked = nil
        if NSCursor.current == NSCursor.disappearingItem { NSCursor.arrow.set() }
        // With the button still down, Escape ended the drag.
        guard !rows.isEmpty, operation.isEmpty, NSEvent.pressedMouseButtons & 1 == 0, !listFrame.contains(point) else { return }
        hide(rows)
    }

    private static func frame(of outline: NSOutlineView) -> NSRect? {
        let list = outline.enclosingScrollView ?? outline
        return list.window?.convertToScreen(list.convert(list.bounds, to: nil))
    }
}

private enum SidebarDataSource {
    private typealias Validate = @convention(c) (AnyObject, Selector, NSOutlineView, AnyObject, AnyObject?, Int) -> NSDragOperation
    private typealias Began = @convention(c) (AnyObject, Selector, NSOutlineView, NSDraggingSession, NSPoint, NSArray) -> Void
    private typealias Ended = @convention(c) (AnyObject, Selector, NSOutlineView, NSDraggingSession, NSPoint, NSDragOperation) -> Void
    private typealias Moved = @convention(c) (NSOutlineView, Selector, AnyObject?, NSPoint) -> Void
    private typealias SessionEnded = @convention(c) (NSOutlineView, Selector, NSDraggingSession, NSPoint, NSDragOperation) -> Void
    private typealias Update = @convention(c) (AnyObject, Selector, NSOutlineView, AnyObject) -> Void
    private typealias SessionMoved = @convention(c) (NSOutlineView, Selector, NSDraggingSession, NSPoint) -> Void
    private typealias OutlineCellFrame = @convention(c) (NSOutlineView, Selector, Int) -> NSRect
    private static var answering: Set<ObjectIdentifier> = []
    private static var hidingDisclosure: Set<ObjectIdentifier> = []
    private static let dragKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func answer(for outline: NSOutlineView, drag: SidebarDrag) -> Bool {
        objc_setAssociatedObject(outline, dragKey, drag, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        followMoves(of: outline)
        hideGroupDisclosure(in: outline)
        guard let source = outline.dataSource, let type = object_getClass(source) else { return false }
        if answering.contains(ObjectIdentifier(type)) { return true }

        let validate = #selector(NSOutlineViewDataSource.outlineView(_:validateDrop:proposedItem:proposedChildIndex:))
        guard let validateMethod = class_getInstanceMethod(type, validate) else { return false }
        let swiftUIValidate = unsafeBitCast(method_getImplementation(validateMethod), to: Validate.self)
        let validateAnswer: @convention(block) (AnyObject, NSOutlineView, AnyObject, AnyObject?, Int) -> NSDragOperation = { source, outline, info, item, index in
            // As a drag leaves, AppKit asks about a drop at child index -2, its nowhere, which SwiftUI's data source looks up as a row and stops Cicero.
            index == -2 ? [] : swiftUIValidate(source, validate, outline, info, item, index)
        }
        replace(type, validate, method: validateMethod, with: imp_implementationWithBlock(validateAnswer))

        let update = #selector(NSOutlineViewDataSource.outlineView(_:updateDraggingItemsForDrag:))
        if let updateMethod = class_getInstanceMethod(type, update) {
            let swiftUIUpdate = unsafeBitCast(method_getImplementation(updateMethod), to: Update.self)
            let updateAnswer: @convention(block) (AnyObject, NSOutlineView, AnyObject) -> Void = { source, outline, info in
                swiftUIUpdate(source, update, outline, info)
                // SwiftUI draws the dragged rows again as the drag comes over the list, with a white symbol.
                if let info = info as? NSDraggingInfo { sidebarDrag(of: outline)?.redraw(info, in: outline) }
            }
            replace(type, update, method: updateMethod, with: imp_implementationWithBlock(updateAnswer))
        }

        let begin = #selector(NSOutlineViewDataSource.outlineView(_:draggingSession:willBeginAt:forItems:))
        let end = #selector(NSOutlineViewDataSource.outlineView(_:draggingSession:endedAt:operation:))
        if let beginMethod = class_getInstanceMethod(type, begin), let endMethod = class_getInstanceMethod(type, end) {
            let swiftUIBegin = unsafeBitCast(method_getImplementation(beginMethod), to: Began.self)
            let beginAnswer: @convention(block) (AnyObject, NSOutlineView, NSDraggingSession, NSPoint, NSArray) -> Void = { source, outline, session, point, items in
                swiftUIBegin(source, begin, outline, session, point, items)
                sidebarDrag(of: outline)?.began(session, count: items.count, in: outline)
            }
            replace(type, begin, method: beginMethod, with: imp_implementationWithBlock(beginAnswer))
            let swiftUIEnd = unsafeBitCast(method_getImplementation(endMethod), to: Ended.self)
            let endAnswer: @convention(block) (AnyObject, NSOutlineView, NSDraggingSession, NSPoint, NSDragOperation) -> Void = { source, outline, session, point, operation in
                swiftUIEnd(source, end, outline, session, point, operation)
                sidebarDrag(of: outline)?.ended(at: point, operation: operation)
            }
            replace(type, end, method: endMethod, with: imp_implementationWithBlock(endAnswer))
        }
        answering.insert(ObjectIdentifier(type))
        return true
    }

    private static func replace(_ type: AnyClass, _ selector: Selector, method: Method, with implementation: IMP) {
        if !class_addMethod(type, selector, implementation, method_getTypeEncoding(method)) {
            method_setImplementation(method, implementation)
        }
    }

    private static func followMoves(of outline: NSOutlineView) {
        guard let type = object_getClass(outline), !answering.contains(ObjectIdentifier(type)) else { return }
        let move = NSSelectorFromString("draggedImage:movedTo:")
        guard let inherited = class_getInstanceMethod(type, move) else { return }
        let appKit = unsafeBitCast(method_getImplementation(inherited), to: Moved.self)
        let moved: @convention(block) (NSOutlineView, AnyObject?, NSPoint) -> Void = { outline, image, point in
            appKit(outline, move, image, point)
            sidebarDrag(of: outline)?.moved(to: point)
        }
        replace(type, move, method: inherited, with: imp_implementationWithBlock(moved))
        // macOS 26 tells a drag's source of its moves this way, and there SwiftUI's outline view has the method itself.
        let movedTo = #selector(NSDraggingSource.draggingSession(_:movedTo:))
        if let own = class_getInstanceMethod(type, movedTo) {
            let swiftUIMoved = unsafeBitCast(method_getImplementation(own), to: SessionMoved.self)
            let sessionMoved: @convention(block) (NSOutlineView, NSDraggingSession, NSPoint) -> Void = { outline, session, point in
                swiftUIMoved(outline, movedTo, session, point)
                sidebarDrag(of: outline)?.moved(to: point)
            }
            replace(type, movedTo, method: own, with: imp_implementationWithBlock(sessionMoved))
        } else {
            let sessionMoved: @convention(block) (NSOutlineView, NSDraggingSession, NSPoint) -> Void = { outline, session, point in
                sidebarDrag(of: outline)?.moved(to: point)
            }
            class_addMethod(type, movedTo, imp_implementationWithBlock(sessionMoved), "v@:@{CGPoint=dd}")
        }
        let end = #selector(NSDraggingSource.draggingSession(_:endedAt:operation:))
        if let inheritedEnd = class_getInstanceMethod(type, end) {
            let appKitEnd = unsafeBitCast(method_getImplementation(inheritedEnd), to: SessionEnded.self)
            let ended: @convention(block) (NSOutlineView, NSDraggingSession, NSPoint, NSDragOperation) -> Void = { outline, session, point, operation in
                // AppKit closes its gap after SwiftUI has put the dropped rows in place, which, animated, opens another gap the rows below slide into.
                guard !operation.isEmpty else { return appKitEnd(outline, end, session, point, operation) }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    CATransaction.setDisableActions(true)
                    appKitEnd(outline, end, session, point, operation)
                }
            }
            replace(type, end, method: inheritedEnd, with: imp_implementationWithBlock(ended))
        }
        answering.insert(ObjectIdentifier(type))
    }

    private static func hideGroupDisclosure(in outline: NSOutlineView) {
        if let type = object_getClass(outline), !hidingDisclosure.contains(ObjectIdentifier(type)),
           let inherited = class_getInstanceMethod(type, #selector(NSOutlineView.frameOfOutlineCell(atRow:))) {
            let selector = #selector(NSOutlineView.frameOfOutlineCell(atRow:))
            let appKit = unsafeBitCast(method_getImplementation(inherited), to: OutlineCellFrame.self)
            let frame: @convention(block) (NSOutlineView, Int) -> NSRect = { outline, row in
                // An empty frame keeps AppKit from making the section header's hover chevron, which would cover the header's +.
                if sidebarDrag(of: outline) != nil, let item = outline.item(atRow: row), outline.delegate?.outlineView?(outline, isGroupItem: item) == true { return .zero }
                return appKit(outline, selector, row)
            }
            replace(type, selector, method: inherited, with: imp_implementationWithBlock(frame))
            hidingDisclosure.insert(ObjectIdentifier(type))
        }
        // AppKit made the chevron before this ran and keeps a pointer to it: removing it ourselves crashes when AppKit recycles it, so let AppKit drop it on a layout pass.
        DispatchQueue.main.async { [weak outline] in
            guard let outline else { return }
            var rows = IndexSet()
            outline.enumerateAvailableRowViews { rowView, row in
                if rowView.subviews.contains(where: { $0.identifier == NSOutlineView.showHideButtonIdentifier }) { rows.insert(row) }
            }
            guard !rows.isEmpty else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                outline.noteHeightOfRows(withIndexesChanged: rows)
            }
        }
    }

    private static func sidebarDrag(of outline: NSOutlineView) -> SidebarDrag? {
        objc_getAssociatedObject(outline, dragKey) as? SidebarDrag
    }
}
