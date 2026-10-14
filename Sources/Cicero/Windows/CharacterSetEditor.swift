import CiceroCore
import SwiftUI

/// The sheet for a new or existing custom character set: a name and the characters, typed or pasted.
struct CharacterSetEditor: View {
    let original: CustomCharacterSet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomCharacterSet

    /// More than this and the preview stops being useful.
    private static let previewLimit = 600

    init(original: CustomCharacterSet) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { !model.data.customCharacterSets.contains { $0.id == original.id } }
    private var name: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let scalars = CharacterSetCatalog.parse(draft.characters)
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Coverage Set" : "Edit Coverage Set").font(.title2.bold())
            TextField("Name", text: $draft.name, prompt: Text("Name"))
            VStack(alignment: .leading, spacing: 6) {
                Text("Characters").font(.headline)
                TextEditor(text: $draft.characters)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                Text("Type or paste characters, codes like U+00C1 or 0x00C1, and ranges like U+0100–U+017F. Spaces and line breaks don’t count, so you can use them to lay things out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Preview").font(.headline)
                    Text(scalars.count == 1 ? "1 character" : "\(scalars.count.formatted()) characters")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ScrollView {
                    Text(Self.preview(scalars))
                        .font(.title3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 96)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        model.deleteCharacterSet(original.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Create" : "Save") {
                    model.saveCharacterSet(CustomCharacterSet(id: draft.id, name: name, characters: draft.characters))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || scalars.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }

    private static func preview(_ scalars: [UInt32]) -> String {
        let shown = scalars.prefix(previewLimit).compactMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        return shown.joined(separator: " ") + (scalars.count > previewLimit ? " …" : "")
    }
}
