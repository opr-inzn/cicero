import CiceroCore
import SwiftUI

/// Asks what to do with added fonts the library has already, from other files, family by family: leave them out, add
/// them as other copies, or put them in place of the library's copies, which go to the Trash. Each starts at replacing
/// when the added one is newer (adding it as another copy when that can't be done), else leaving it out. Files with no
/// such fonts are added either way.
struct DuplicatesSheet: View {
    let prompt: DuplicatePrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [String: DuplicateChoice]

    init(prompt: DuplicatePrompt) {
        self.prompt = prompt
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: prompt.duplicates.map { ($0.id, $0.suggestion) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.duplicates.count == 1 ? "\(prompt.duplicates[0].family) Is Already in Your Library" : "\(prompt.duplicates.count) Families Are Already in Your Library")
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(prompt.duplicates.count == 1
                    ? "Your library has this family from another file. Choose what to do with the one you added."
                    : "Your library has these families from other files. Choose what to do with each one you added.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(prompt.duplicates) { duplicate in
                        row(duplicate)
                        // Between rows only: the bar below has its own line.
                        if duplicate.id != prompt.duplicates.last?.id { Divider().padding(.leading, 20) }
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                if prompt.duplicates.count > 1 {
                    Menu("Choose for All") {
                        ForEach(DuplicateChoice.allCases, id: \.self) { choice in
                            Button(choice.title) {
                                for duplicate in prompt.duplicates where choice != .replace || duplicate.canReplace { choices[duplicate.id] = choice }
                            }
                        }
                    }
                    .fixedSize()
                }
                Text("Replace your copy moves your files to the Trash and puts the added ones in their place.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    model.addFontFiles(prompt.paths, resolving: prompt.duplicates, choices: choices, then: prompt.then)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: min(540, 146 + prompt.duplicates.map(Self.rowHeight).reduce(0, +)))
    }

    private func row(_ duplicate: AddedDuplicate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(duplicate.family).lineLimit(1)
                    Tag(text: duplicate.version.title, tint: duplicate.version == .newer ? .green : .secondary)
                }
                Text(detail(duplicate))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let block = duplicate.replaceBlock {
                    Text(block.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if choices[duplicate.id] ?? duplicate.suggestion == .replace, duplicate.replacesSeveralCopies {
                    Label("Replaces \(duplicate.replacements.count) files: \(model.replacedPlaces(duplicate))", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Picker("Choice", selection: Binding(get: { choices[duplicate.id] ?? duplicate.suggestion }, set: { choices[duplicate.id] = $0 })) {
                ForEach(DuplicateChoice.allCases.filter { $0 != .replace || duplicate.canReplace }, id: \.self) { choice in
                    // "Replace your copies" when it's more than one file.
                    Text(choice == .replace && duplicate.replacements.count > 1 ? "Replace your copies" : choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// A row's height: a line more for one that can't be replaced, or that warns it replaces more than one file. With
    /// the title and the bar below (146), the sheet is as tall as its rows, up to 540.
    private static func rowHeight(_ duplicate: AddedDuplicate) -> CGFloat {
        duplicate.replaceBlock != nil || duplicate.replacesSeveralCopies ? 73 : 54
    }

    /// "4 styles · In your library: 1.002, on in your Fonts folder · Added: 2.000".
    private func detail(_ duplicate: AddedDuplicate) -> String {
        let styles = duplicate.styles.count == 1 ? "1 style" : "\(duplicate.styles.count) styles"
        let places = duplicate.styles.map(place).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let library = "In your library: \(Self.versions(duplicate.libraryVersions)), \(places.joined(separator: "; "))"
        return [styles, library, "Added: \(Self.versions(duplicate.addedVersions))"].joined(separator: " · ")
    }

    private static func versions(_ versions: [String]) -> String {
        versions.isEmpty ? "no version" : versions.joined(separator: ", ")
    }

    /// Whether a style is on and where its copy is: "on in your Fonts folder", "off in Clients".
    private func place(_ style: LibraryFace) -> String {
        let path = style.face.path
        switch style.state {
        case .active(.macOS): return "on, with macOS"
        case .active(.allUsers): return "on for all users"
        case .active(.app): return "on, with an app"
        case .active(.adobeFonts): return "on from Adobe Fonts"
        case .appOnly(let app): return "on in \(FaceState.appDescription(app))"
        default: break
        }
        return (style.state.isActive ? "on " : "off ") + model.placeName(of: path)
    }
}

extension DuplicateChoice {
    var title: String {
        switch self {
        case .skip: "Skip it"
        case .addCopy: "Add as a copy"
        case .replace: "Replace your copy"
        }
    }
}

private extension ReplaceBlock {
    var explanation: String {
        switch self {
        case .differentFiles: "Can’t be replaced: your copy’s files and the added ones hold the fonts differently."
        case .unchangeable: "Can’t be replaced: your copy comes with macOS or an app, or from Adobe Fonts."
        }
    }
}

private extension DuplicateVersion {
    var title: String {
        switch self {
        case .newer: "Newer"
        case .older: "Older"
        case .sameVersion: "Same Version"
        case .sameFile: "Same File"
        }
    }
}
