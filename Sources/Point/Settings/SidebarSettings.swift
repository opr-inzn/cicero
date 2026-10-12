import PointCore
import SwiftUI

/// Finder-style checkboxes for every sidebar row and section.
struct SidebarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Library") {
                    ForEach(model.libraryRows) { checkbox($0) }
                }
                ForEach(SidebarSection.allCases) { section in
                    Section {
                        if section == .characterSets {
                            ForEach(model.characterSetGroups, id: \.id) { group in
                                DisclosureGroup(group.title) {
                                    ForEach(group.rows) { checkbox($0) }
                                }
                            }
                        } else {
                            ForEach(model.rows(for: section)) { checkbox($0) }
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
                Text("Unchecked items stay out of the sidebar. Edit in the sidebar itself does the same.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All") { model.showAllSidebarItems() }
            }
            .padding()
        }
    }

    private func checkbox(_ row: SidebarRow) -> some View {
        Toggle(isOn: visibility(row.key)) {
            Label(row.title, systemImage: row.icon)
        }
        .toggleStyle(.checkbox)
    }

    private func visibility(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) })
    }
}
