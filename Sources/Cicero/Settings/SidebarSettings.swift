import SwiftUI

struct SidebarSettings: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Library") {
                    ForEach(model.libraryRows) { checkbox($0) }
                }
                ForEach(model.sections) { section in
                    Section {
                        switch section {
                        case .characterSets:
                            // Each set is a row of the form: a DisclosureGroup's content is one row, its checkboxes packed together without lines between them.
                            ForEach(model.characterSetGroups, id: \.id) { group in
                                groupRow(group.id, title: group.title)
                                if expanded.contains(group.id) {
                                    ForEach(group.rows) { checkbox($0, in: section).padding(.leading, 26) }
                                }
                            }
                        case .foundries:
                            note("Hide individual foundries with Edit in the sidebar.")
                        default:
                            // A section without rows still gets a card, or its header runs into the next one.
                            let rows = model.rows(for: section)
                            if rows.isEmpty {
                                note("No \(section.title.lowercased()) yet.")
                            } else {
                                ForEach(rows) { checkbox($0, in: section) }
                            }
                        }
                    } header: {
                        Toggle(section.title, isOn: visibility(section.key))
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Drag items in the sidebar to reorder them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Order") { model.resetSidebarOrder() }
                    .disabled(!model.hasSidebarOrder)
                Button("Show All") { model.showAllSidebarItems() }
            }
            .padding()
        }
    }

    private func groupRow(_ id: String, title: String) -> some View {
        let isExpanded = expanded.contains(id)
        return Button {
            if isExpanded { expanded.remove(id) } else { expanded.insert(id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func checkbox(_ row: SidebarRow, in section: SidebarSection? = nil) -> some View {
        Toggle(isOn: visibility(row.key)) {
            HStack(spacing: 6) {
                SidebarIcon(row: row)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(row.title)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!row.canHide || (section.map { !model.isVisible($0.key) } ?? false))
    }

    private func visibility(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) })
    }
}
