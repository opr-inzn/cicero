import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

/// The library sidebar. Edit puts a checkbox on every row and section to show or hide it; the same
/// choices are in Settings → Sidebar. Sections and groups stay open or closed as they were, and open and close
/// the same way while editing, so a long one like Foundries can be closed to get past it. Edit and Done switch
/// at once: animated, hundreds of rows coming and going ran into each other. Rows drag to a new place within their section (or character set
/// group), several at once when they're selected together, and the rows they pass slide apart to open a
/// gap where they'll land. Group titles drag onto each other; sections stay in their order.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// What the list shows selected while the browser hasn't taken it yet (see `select`).
    @State private var pendingSelection: Set<SidebarItem>?
    @State private var pace = SelectionPace()
    @State private var highlight = SidebarHighlight()

    var body: some View {
        let shown = pendingSelection ?? model.selectedItems
        // The rows are a view of their own: a list's selection updates whatever makes the list, and this
        // way that's just this, not every section and row. Each row's title reads the selection it draws.
        List(selection: Binding(get: { shown }, set: select)) {
            SidebarContent(highlight: highlight)
        }
        .listStyle(.sidebar)
        .onChange(of: shown, initial: true) { highlight.selected = shown }
        .contextMenu {
            Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar",
                   systemImage: model.isEditingSidebar ? "checkmark" : "sidebar.left") { model.isEditingSidebar.toggle() }
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
    /// Passed in rather than through the environment, which a row's background doesn't get.
    let highlight: SidebarHighlight
    /// The character set group whose title is being dragged, and the one whose title it's over.
    @State private var draggedGroup: String?
    @State private var groupDropTarget: String?

    var body: some View {
        let editing = model.isEditingSidebar
        Section {
            movableRows(model.libraryRows, in: "library", section: nil)
        } header: {
            header
        }
        .notCollapsible()
        ForEach(model.sections) { section in
            if editing || model.isVisible(section.key) {
                let groups = section == .characterSets ? model.characterSetGroups : []
                let rows = section == .characterSets ? [] : model.rows(for: section)
                // Not `Section(isExpanded:)`: the list's chevron would push the header's + aside (see `SectionHeader`).
                Section {
                    if model.isExpanded(section) {
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
                    }
                } header: {
                    sectionHeader(section)
                }
                .notCollapsible()
            }
        }
    }

    /// Rows that drag to a new place among themselves.
    private func movableRows(_ rows: [SidebarRow], in list: String, section: SidebarSection?) -> some View {
        let shownRows = shown(rows)
        return ForEach(shownRows) { row($0, section: section) }
            .onMove { model.moveSidebarItems($0, to: $1, shown: shownRows.map(\.key), all: rows.map(\.key), in: list) }
    }

    /// Character sets in collapsible groups; a group whose sets are all hidden disappears. Sets move within
    /// their group. A click on a group's title opens or closes it, and a title that takes clicks can't
    /// hand drags to the list, so groups move by dropping one's title onto another's, which is
    /// highlighted: the dragged group takes its place, and the other moves towards where it was.
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
                movableRows(group.rows, in: key(group.id), section: .characterSets)
            } label: {
                // Only the chevron toggles a group in a selectable list; make the title do it too. A tap
                // rather than a button, so the title doesn't dim while it's pressed. An icon and full-strength
                // text like the rows around it, as a playlist folder has in Music's sidebar. Coloured here, as the
                // rows are (see `SidebarLabel`), or the list grays it while another window is in front.
                Label(group.title, systemImage: "character.book.closed")
                    .lineLimit(1)
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
                        editSidebarButton
                    }
            }
        }
    }

    /// The payload of a group title's drag, made as the drag starts. The group is remembered until the
    /// mouse button goes up, so its own title doesn't light up as a place to drop it.
    private func beginDrag(of group: String) -> GroupDrag {
        draggedGroup = group
        Task {
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            draggedGroup = nil
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
        .background(OutlineViewSetup())
    }

    private func sectionHeader(_ section: SidebarSection) -> some View {
        SectionHeader(title: section.title, isExpanded: expansion(section),
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
            plus("Add a folder of fonts") { model.presentAddFolderPanel() }
        case .sets:
            Menu {
                // The symbols the sidebar has for each kind.
                Button("New Set", systemImage: "square.stack") { model.prompt("New Set", confirm: "Create") { model.addSet(named: $0) } }
                Button("New Smart Set", systemImage: "gearshape") { model.editingSmartSet = SmartSet(name: "") }
                Button("New Application Set", systemImage: "app.badge.checkmark") { model.newApplicationSet() }
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
            plus("New tag") { model.newTag() }
        case .characterSets:
            plus("New coverage set") { model.editingCharacterSet = CustomCharacterSet(name: "", characters: "") }
        case .classifications:
            plus("New classification") { model.newClassification() }
        case .foundries:
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

    /// Activate, Activate Temporarily and Deactivate for every font in a set or smart set.
    @ViewBuilder
    private func activation(for row: SidebarRow, kind: String) -> some View {
        // The symbols of the sidebar's Active and Inactive.
        Button("Activate \(kind)", systemImage: "checkmark.circle") { model.activateFonts(in: row.item, named: row.title) }
        Button("Activate Temporarily", systemImage: "clock") { model.activateFontsTemporarily(in: row.item) }
        Button("Deactivate \(kind)", systemImage: "circle.dashed") { model.deactivateFonts(in: row.item) }
    }

    @ViewBuilder
    private func row(_ row: SidebarRow, section: SidebarSection?) -> some View {
        let hidden = !model.isVisible(row.key) || (section.map { !model.isVisible($0.key) } ?? false)
        let content = HStack(spacing: 6) {
            if model.isEditingSidebar { checkbox(row.key, row.title) }
            SidebarLabel(row: row, highlight: highlight)
        }
        .badge(row.badge > 0 ? Text(row.badge, format: .number) : nil)
        .opacity(model.isEditingSidebar && hidden ? 0.45 : 1)
        .listRowBackground(SidebarRowBackground(item: row.item, highlight: highlight))
        .tag(row.item)
        .contextMenu { menu(for: row) }
        // Only rows that take families, or styles of them, are drop targets: being one makes a row much slower to appear,
        // which shows when a section opens or a long one scrolls. The one families are over lights up.
        if model.takesFamilies(row.item) {
            content
                .background(FontDropTarget(isOver: { isOver in
                    if isOver {
                        if highlight.dropTarget != row.item { highlight.dropTarget = row.item }
                    } else if highlight.dropTarget == row.item {
                        highlight.dropTarget = nil
                    }
                }) { drags in
                    highlight.dropTarget = nil
                    _ = model.handleDrop(drags, on: row.item)
                })
        } else {
            content
        }
    }

    /// Shows the folder under another name in Cicero; the folder on disk keeps its own. Left empty, it goes back to that.
    private func renameFolder(_ id: UUID) -> some View {
        Button("Rename Folder", systemImage: "pencil") {
            model.prompt("Rename Folder", text: model.folderName(id), confirm: "Rename") { model.renameFolder(id, to: $0) }
        }
    }

    @ViewBuilder
    private func menu(for row: SidebarRow) -> some View {
        switch row.item {
        case .folder(WatchedFolder.adobeAppsID):
            renameFolder(WatchedFolder.adobeAppsID)
            Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting(WatchedFolder.appFontFolders().map(\.url)) }
        case .folder(WatchedFolder.adobeFontsID):
            renameFolder(WatchedFolder.adobeFontsID)
            Button("Manage in Creative Cloud", systemImage: "arrow.up.forward.app") { CreativeCloud.open() }
        case .folder(WatchedFolder.addedFilesID):
            renameFolder(WatchedFolder.addedFilesID)
            Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting(model.addedFileURLs) }
        case .folder(let id):
            if let folder = model.folder(id) {
                renameFolder(id)
                Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                if id != WatchedFolder.fontLibraryID {
                    Divider()
                    FolderActivationPicker(folder: folder) {
                        model.prompt("Active in Specific App", confirm: "OK") { model.setActivation(ofFolder: id, active: false, app: $0) }
                    }
                    Button("Remove Folder from Library", systemImage: "folder.badge.minus") { model.removeFolder(id) }
                }
            }
        case .set(let id):
            if let set = model.data.sets.first(where: { $0.id == id }) {
                activation(for: row, kind: "Set")
                Divider()
                Button("Rename Set", systemImage: "pencil") { model.prompt("Rename Set", text: set.name, confirm: "Rename") { model.renameSet(id, to: $0) } }
                Button(set.apps.isEmpty ? "Activate with Apps" : "Edit Apps", systemImage: "app.badge.checkmark") { model.editingAppsForSet = id }
                Button("Delete Set", systemImage: "trash") { model.deleteSet(id) }
            }
        case .smartSet(let id):
            if let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                activation(for: row, kind: "Smart Set")
                Divider()
                Button("Edit Smart Set", systemImage: "slider.horizontal.3") { model.editingSmartSet = smartSet }
                Button("Delete Smart Set", systemImage: "trash") { model.deleteSmartSet(id) }
            }
        case .tag(let name):
            Button("Rename Tag", systemImage: "pencil") { model.prompt("Rename Tag", text: name, confirm: "Rename") { model.renameTag(name, to: $0) } }
            Picker(selection: Binding(get: { model.data.tagColors[name] }, set: { model.setColor($0, forTag: name) })) {
                Text("None").tag(TagColor?.none)
                Divider()
                ForEach(TagColor.allCases, id: \.self) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: color.menuImage) }
                        .labelStyle(.titleAndIcon)
                        .tag(Optional(color))
                }
            } label: {
                Label("Color", systemImage: "paintpalette")
            }
            Button("Delete Tag", systemImage: "trash") { model.deleteTag(name) }
        case .foundry(let name):
            Button("Rename Foundry", systemImage: "pencil") { model.prompt("Rename Foundry", text: name, confirm: "Rename") { model.renameFoundry(name, to: $0) } }
        case .classification(let name):
            Button("Rename Classification", systemImage: "pencil") {
                model.prompt("Rename Classification", text: name, confirm: "Rename") { model.renameClassification(name, to: $0) }
            }
            if model.isUserClassification(name) {
                Button("Delete Classification", systemImage: "trash") { model.deleteClassification(name) }
            }
        case .characterSet(let id):
            if let custom = model.data.customCharacterSets.first(where: { $0.setID == id }) {
                Button("Edit Coverage Set", systemImage: "pencil") { model.editingCharacterSet = custom }
                Button("Delete Coverage Set", systemImage: "trash") { model.deletingCharacterSet = custom }
            }
        default:
            EmptyView()
        }
        if model.canExport(row.item) {
            Divider()
            Button("Export Fonts", systemImage: "square.and.arrow.up") { model.exportFonts(in: row.item, named: row.title) }
            Button("Export Font List", systemImage: "tablecells") { model.exportFontList(model.families(in: row.item), named: row.title) }
        }
        Divider()
        if model.isVisible(row.key) {
            Button("Hide from Sidebar", systemImage: "eye.slash") { model.setVisible(row.key, false) }
        }
        editSidebarButton
    }

    private var editSidebarButton: some View {
        Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar",
               systemImage: model.isEditingSidebar ? "checkmark" : "sidebar.left") { model.isEditingSidebar.toggle() }
    }
}

/// A section's title, with its checkbox while editing and its + at the end, and a chevron before the + while the pointer
/// is over the row. The list has a chevron that shows the same way, but after the +, narrowing the header as it comes
/// and goes, which moved the +; keeping its place empty left a gap. The whole row opens and closes the section. Its
/// own view, so the pointer coming and going doesn't redo the sidebar's rows.
private struct SectionHeader<Leading: View, Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let isDimmed: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(title)
                .opacity(isDimmed ? 0.45 : 1)
                .accessibilityAction(named: isExpanded ? "Collapse" : "Expand", toggle)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                // Turns at once, while the section's rows open and close.
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

/// What the sidebar shows selected, and the row families are being dragged over. The list draws neither (see
/// `OutlineViewSetup`): each row draws its own, from this.
@Observable
final class SidebarHighlight {
    var selected: Set<SidebarItem> = []
    var dropTarget: SidebarItem?
}

/// A row's title and symbol: in the accent colour while it's selected, white on it while families are over it.
private struct SidebarLabel: View {
    let row: SidebarRow
    let highlight: SidebarHighlight

    var body: some View {
        let style: AnyShapeStyle = highlight.dropTarget == row.item ? AnyShapeStyle(.white)
            : highlight.selected.contains(row.item) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)
        // On the symbol too: a sidebar styles symbols itself. A status's dot keeps its own colour.
        Label { Text(row.title).lineLimit(1).foregroundStyle(style) } icon: { SidebarIcon(row: row).foregroundStyle(style) }
    }
}

/// Behind a selected row, a light fill; behind the row families are over, the accent colour, as the list draws a
/// selected row while it has focus.
private struct SidebarRowBackground: View {
    let item: SidebarItem
    let highlight: SidebarHighlight

    var body: some View {
        let isTarget = highlight.dropTarget == item
        let isSelected = highlight.selected.contains(item)
        if isTarget || isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTarget ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                .padding(.horizontal, 10)
        }
    }
}

/// A row's symbol, or a status's colour as a dot. The dot is a picture rather than a symbol in the colour, which the
/// list darkened on the accent colour behind a row families are dragged over (and behind a selected row, when the
/// list drew those).
struct SidebarIcon: View {
    let row: SidebarRow

    var body: some View {
        if let color = row.color {
            Image(nsImage: color.menuImage)
                .accessibilityLabel(color.title)
        } else {
            Image(systemName: row.icon)
        }
    }
}

/// A character set group's title being dragged onto another's.
private nonisolated struct GroupDrag: Codable, Transferable {
    var group: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroSidebarGroup)
    }
}

private extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroSidebarGroup = UTType(exportedAs: "com.maximilianinzinger.cicero.sidebar-group")
}

/// Makes a group's title draggable. On macOS 15 a title dragged with `draggable` never left the list.
private struct GroupDragSource: ViewModifier {
    /// Made as the drag starts.
    let payload: () -> GroupDrag

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.draggable(payload())
        } else {
            content.onDrag {
                let provider = NSItemProvider()
                provider.register(payload())
                return provider
            }
        }
    }
}

/// Makes a group's title take another group's title dropped onto it, lit up while one is over it. A move, not the
/// default copy, so the pointer doesn't get a green plus, and forbidden onto the dragged group's own title.
private struct GroupDrop: ViewModifier {
    let group: String
    /// The group being dragged (see `beginDrag(of:)`).
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
            // macOS 15 has no drop configurations; a delegate proposes the operation instead.
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

/// Makes the list open a gap where dragged rows will land, the rows around it sliding apart as in Finder's
/// sidebar, instead of drawing an insertion line, and leaves drawing the selection to the rows (see
/// `SidebarHighlight`). SwiftUI has no setting for either: a List on macOS 26 is an NSOutlineView, whose
/// `draggingDestinationFeedbackStyle` is `.sourceList` in a sidebar, and SwiftUI leaves the styles alone once
/// they're set. This sits behind a header inside the list, so the outline view is among its superviews; it takes
/// no clicks and draws nothing.
private struct OutlineViewSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Marker() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSOutlineView) { view = current.superview }
            guard let outline = view as? NSOutlineView else { return }
            outline.draggingDestinationFeedbackStyle = .gap
            outline.selectionHighlightStyle = .none
        }
    }
}
