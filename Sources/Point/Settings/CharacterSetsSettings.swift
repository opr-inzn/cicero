import PointCore
import SwiftUI

/// The built-in character sets by group, with a checkbox each for the sidebar, and the user's own.
struct CharacterSetsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var editing: CustomCharacterSet?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Text("Checked sets appear in the sidebar, where you can see which fonts have every one of their characters. All of them are shown at first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(model.characterSetCatalog.groups) { group in
                    Section {
                        ForEach(group.sets) { row($0) }
                    } header: {
                        Text(group.name)
                    } footer: {
                        if let url = URL(string: group.url) {
                            Link(group.credit, destination: url)
                        } else {
                            Text(group.credit)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            custom
        }
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

    private var custom: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Character Sets").font(.headline)
            List(selection: $selection) {
                ForEach(model.data.customCharacterSets) { set in
                    HStack {
                        Toggle(set.name, isOn: visibility(set.setID))
                            .toggleStyle(.checkbox)
                        Spacer()
                        Text(count(CharacterSetCatalog.parse(set.characters).count))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(set.id)
                }
            }
            .listStyle(.bordered)
            // No stripes behind the empty-state note.
            .alternatingRowBackgrounds(model.data.customCharacterSets.isEmpty ? .disabled : .enabled)
            .frame(height: 110)
            .overlay {
                if model.data.customCharacterSets.isEmpty {
                    Text("Make a set from the characters you need, like a client’s name or a language’s alphabet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            HStack(spacing: 6) {
                Button("New Character Set", systemImage: "plus") { editing = CustomCharacterSet(name: "", characters: "") }
                    .labelStyle(.iconOnly)
                Button("Delete Character Set", systemImage: "minus") {
                    if let selection { model.deleteCharacterSet(selection) }
                    selection = nil
                }
                .labelStyle(.iconOnly)
                .disabled(selection == nil)
                Button("Edit…") { editing = selected }
                    .disabled(selected == nil)
            }
        }
        .padding(16)
    }

    private var selected: CustomCharacterSet? {
        model.data.customCharacterSets.first { $0.id == selection }
    }

    private func count(_ characters: Int) -> String {
        characters == 1 ? "1 character" : "\(characters.formatted()) characters"
    }

    private func visibility(_ setID: String) -> Binding<Bool> {
        let key = "charset.\(setID)"
        return Binding(get: { model.isVisible(key) }, set: { model.setVisible(key, $0) })
    }
}
