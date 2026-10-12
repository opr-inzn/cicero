import CiceroCore
import SwiftUI

/// Finder-style checkboxes for every sidebar row and section, in the sidebar's order.
struct SidebarSettings: View {
    @Environment(AppModel.self) private var model

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
                            ForEach(model.characterSetGroups, id: \.id) { group in
                                DisclosureGroup(group.title) {
                                    // A grouped form centres what's inside a disclosure group.
                                    ForEach(group.rows) {
                                        checkbox($0, in: section).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        // A library can have hundreds: just the section's checkbox here.
                        case .foundries:
                            note("Hide single foundries with Edit in the sidebar.")
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
                Text("Unchecked items stay out of the sidebar; Edit there does the same. Drag items and section titles in the sidebar to reorder them.")
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

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    /// Off while its section is: the row can't show then either way.
    private func checkbox(_ row: SidebarRow, in section: SidebarSection? = nil) -> some View {
        Toggle(isOn: visibility(row.key)) {
            HStack(spacing: 6) {
                // A fixed width keeps the titles lined up however wide each symbol is.
                Image(systemName: row.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(row.title)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(section.map { !model.isVisible($0.key) } ?? false)
    }

    private func visibility(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) })
    }
}
