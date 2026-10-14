import CiceroCore
import SwiftUI

/// The sheet for a new or existing custom character set: a name and the characters, typed or pasted.
struct CharacterSetEditor: View {
    let original: CustomCharacterSet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomCharacterSet
    @State private var deleting: CustomCharacterSet?
    /// Whether the set was new when the sheet opened: saving or deleting it changes that while the sheet is still closing.
    @State private var openedAsNew: Bool?

    /// More than this and the preview stops being useful.
    private static let previewLimit = 600

    init(original: CustomCharacterSet) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { openedAsNew ?? !model.data.customCharacterSets.contains { $0.id == original.id } }
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
                    Button("Delete", role: .destructive) { deleting = original }
                        .foregroundStyle(.red)
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
        .onAppear { openedAsNew = isNew }
        .confirmsCoverageSetDeletion($deleting) { dismiss() }
    }

    private static func preview(_ scalars: [UInt32]) -> String {
        let shown = scalars.prefix(previewLimit).compactMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        return shown.joined(separator: " ") + (scalars.count > previewLimit ? " …" : "")
    }
}

extension View {
    /// Asks before deleting the coverage set, then calls `deleted`.
    func confirmsCoverageSetDeletion(_ set: Binding<CustomCharacterSet?>, deleted: @escaping () -> Void = {}) -> some View {
        modifier(CoverageSetDeletion(set: set, deleted: deleted))
    }
}

private struct CoverageSetDeletion: ViewModifier {
    @Binding var set: CustomCharacterSet?
    let deleted: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(
            set.map { "Delete the coverage set “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { set != nil }, set: { if !$0 { set = nil } }),
            presenting: set
        ) { set in
            Button("Delete", role: .destructive) {
                model.deleteCharacterSet(set.id)
                deleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can’t undo this.")
        }
    }
}
