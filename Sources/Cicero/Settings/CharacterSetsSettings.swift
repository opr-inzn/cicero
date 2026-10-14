import CiceroCore
import SwiftUI

/// The user's own character sets, then the built-in ones by group, with a checkbox each for the sidebar.
struct CharacterSetsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CustomCharacterSet?

    var body: some View {
        Form {
            custom
            ForEach(model.characterSetCatalog.groups) { group in
                Section {
                    ForEach(group.sets) { row($0) }
                } header: {
                    Text(group.name)
                } footer: {
                    Group {
                        if let url = URL(string: group.url) {
                            Link(group.credit, destination: url)
                        } else {
                            Text(group.credit)
                        }
                    }
                    .formFooter()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { CharacterSetEditor(original: $0) }
    }

    private func row(_ set: CharacterSetDefinition) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: visibility(set.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name)
                    if !set.summary.isEmpty {
                        Text(set.summary).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(count(set.scalars.count))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Rows of the form rather than a list of their own, so they scroll with the built-in sets.
    private var custom: some View {
        Section {
            ForEach(model.data.customCharacterSets) { set in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(set.name, isOn: visibility(set.setID))
                        .toggleStyle(.checkbox)
                    Spacer()
                    Text(count(CharacterSetCatalog.parse(set.characters).count))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Edit") { editing = set }
                }
                .contextMenu {
                    Button("Edit Coverage Set") { editing = set }
                    Button("Delete Coverage Set") { model.deleteCharacterSet(set.id) }
                }
            }
            if model.data.customCharacterSets.isEmpty {
                Text("Make a set from the characters you need, like a client’s name or a language’s alphabet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Your Coverage Sets")
                Spacer()
                ListEditButton("New Coverage Set", systemImage: "plus") { editing = CustomCharacterSet(name: "", characters: "") }
                    .help("Make a coverage set")
            }
        }
    }

    private func count(_ characters: Int) -> String {
        characters == 1 ? "1 character" : "\(characters.formatted()) characters"
    }

    private func visibility(_ setID: String) -> Binding<Bool> {
        let key = "charset.\(setID)"
        return Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) })
    }
}
