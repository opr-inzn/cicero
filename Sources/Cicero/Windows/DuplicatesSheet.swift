import CiceroCore
import SwiftUI

/// Asks what to do with added fonts the library has already, from other files, family by family: leave them out, add
/// them as other copies, or use them in place of the library's copies. Each starts at using the added one when it's
/// newer, else leaving it out. Files with no such fonts are added either way.
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
                        Divider().padding(.leading, 20)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                if prompt.duplicates.count > 1 {
                    Menu("Choose for All") {
                        ForEach(DuplicateChoice.allCases, id: \.self) { choice in
                            Button(choice.title) { for duplicate in prompt.duplicates { choices[duplicate.id] = choice } }
                        }
                    }
                    .fixedSize()
                }
                Text("Using the added one turns the library’s copy off as deactivating does, so no font is lost.")
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
        .frame(width: 720, height: min(540, 190 + CGFloat(prompt.duplicates.count) * 58))
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
            }
            Spacer(minLength: 12)
            Picker("Choice", selection: Binding(get: { choices[duplicate.id] ?? duplicate.suggestion }, set: { choices[duplicate.id] = $0 })) {
                ForEach(DuplicateChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
        let state = style.state.isActive ? "on" : "off"
        if path.hasPrefix(model.locations.userFonts.path + "/") { return "\(state) in your Fonts folder" }
        if path.hasPrefix(model.locations.deactivated.path + "/") { return "\(state) in the Deactivated folder" }
        if let library = model.data.fontLibrary, path.hasPrefix(library.path + "/") { return "\(state) in \(model.folderName(WatchedFolder.fontLibraryID))" }
        if model.data.fontFiles.contains(path) { return "\(state) in \(model.folderName(WatchedFolder.addedFilesID))" }
        if let folder = model.data.namedFolders.filter({ path.hasPrefix($0.path + "/") }).max(by: { $0.path.count < $1.path.count }) {
            return "\(state) in \(folder.displayName)"
        }
        return "\(state) in “\(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)”"
    }
}

extension DuplicateChoice {
    var title: String {
        switch self {
        case .skip: "Skip It"
        case .addCopy: "Add as Another Copy"
        case .useAdded: "Use the Added One"
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
