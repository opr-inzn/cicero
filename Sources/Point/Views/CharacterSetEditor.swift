import SwiftUI

/// Creates or edits a character set of the user's own.
struct CharacterSetEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let original: CustomCharacterSet
    @State private var name: String
    @State private var characters: String

    init(original: CustomCharacterSet) {
        self.original = original
        _name = State(initialValue: original.name)
        _characters = State(initialValue: original.characters)
    }

    private var isNew: Bool { !library.data.customCharacterSets.contains { $0.id == original.id } }

    var body: some View {
        let scalars = CharacterSetCatalog.parse(characters)
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Character Set" : "Edit Character Set")
                .font(.headline)
            TextField("Name", text: $name, prompt: Text("Character Set Name"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Characters")
                TextEditor(text: $characters)
                    .font(.system(size: 15))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.canvas, in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                Text("Type or paste characters, Unicode values like U+00C1, or ranges like U+0100–U+017F. Spaces and line breaks are ignored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !scalars.isEmpty {
                ScrollView {
                    Text(String(String.UnicodeScalarView(scalars.prefix(2000).compactMap(Unicode.Scalar.init))))
                        .font(.system(size: 17))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 80)
            }
            HStack {
                Text(scalars.count == 1 ? "1 character" : "\(scalars.count.formatted()) characters")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    if isNew {
                        library.addCharacterSet(named: name, characters: characters)
                    } else {
                        library.updateCharacterSet(original.id, name: name, characters: characters)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || scalars.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
