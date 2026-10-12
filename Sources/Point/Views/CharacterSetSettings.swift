import SwiftUI

/// Settings → Character Sets: which sets the sidebar lists, and the user's own sets.
struct CharacterSetSettings: View {
    @Environment(LibraryStore.self) private var library
    @State private var selection: UUID?
    @State private var editing: CustomCharacterSet?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A character set lists the characters a font needs for a group of languages. Checked sets appear in the sidebar, where they show the fonts that have every character. They also work in smart sets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(CharacterSetCatalog.groups) { group in
                    Section {
                        ForEach(group.sets) { row($0) }
                    } header: {
                        Text(group.name)
                    } footer: {
                        Link(group.credit, destination: URL(string: group.url)!)
                            .font(.caption)
                    }
                }
                Section("Your Character Sets") {
                    if library.data.customCharacterSets.isEmpty {
                        Text("Click + to make one from any characters you need.")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(library.customCharacterSetDefinitions) { set in
                        row(set)
                            .tag(UUID(uuidString: String(set.id.dropFirst("custom.".count))))
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let set = custom(id) {
                    Button("Edit…") { editing = set }
                    Button("Delete") { library.deleteCharacterSet(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let set = custom(id) { editing = set }
            }

            HStack(spacing: 0) {
                Button { editing = CustomCharacterSet(name: "", characters: "") } label: {
                    Image(systemName: "plus").frame(width: 22, height: 18)
                }
                Divider().frame(height: 16)
                Button {
                    if let selection { library.deleteCharacterSet(selection) }
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 22, height: 18)
                }
                .disabled(selection.flatMap(custom) == nil)
                Spacer()
                Button("Edit…") { editing = selection.flatMap(custom) }
                    .disabled(selection.flatMap(custom) == nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .sheet(item: $editing) { CharacterSetEditor(original: $0) }
    }

    private func custom(_ id: UUID) -> CustomCharacterSet? {
        library.data.customCharacterSets.first { $0.id == id }
    }

    private func row(_ set: CharacterSetDefinition) -> some View {
        Toggle(isOn: library.visibilityBinding(for: "charset.\(set.id)")) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(set.name)
                    Spacer()
                    Text(set.scalars.count == 1 ? "1 character" : "\(set.scalars.count.formatted()) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !set.summary.isEmpty {
                    Text(set.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

/// The Info pane's Character Sets row: the largest set of each series the face has, and how far
/// it is from the next Latin size up.
struct CharacterSetsRow: View {
    @Environment(LibraryStore.self) private var library
    let face: FontFace
    @State private var ranges: ScalarRanges?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Character Sets").font(.caption).foregroundStyle(.secondary)
            if let ranges {
                let has = supported(by: ranges)
                Text(has.isEmpty ? "None" : ListFormatter.localizedString(byJoining: has.map(\.name)))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = nextLatinSize(after: has, ranges: ranges) {
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: face.id) {
            ranges = nil
            let result = await CharacterCoverage.shared.coverage(computingFor: face)
            if !Task.isCancelled { ranges = result.scalars }
        }
    }

    /// Per series only the largest set counts; Google's sets are grouped by script.
    private func supported(by ranges: ScalarRanges) -> [CharacterSetDefinition] {
        var best: [String: CharacterSetDefinition] = [:]
        var order: [String] = []
        for set in library.characterSets where ranges.missingCount(sorted: set.scalars) == 0 {
            let series = set.isCustom ? set.id : CharacterSetCatalog.seriesIDs.contains(set.groupID) ? set.groupID : String(set.id.split(separator: "-").dropLast().joined(separator: "-"))
            if best[series] == nil { order.append(series) }
            best[series] = set
        }
        return order.compactMap { best[$0] }
    }

    private func nextLatinSize(after has: [CharacterSetDefinition], ranges: ScalarRanges) -> String? {
        let series = CharacterSetCatalog.groups.first { $0.id == "koeberlin" }?.sets ?? []
        let current = has.first { $0.groupID == "koeberlin" }
        guard let next = series.first(where: { $0.level == (current?.level ?? -1) + 1 }) else { return nil }
        let missing = ranges.missingCount(sorted: next.scalars)
        return missing == 1 ? "\(next.name) needs 1 more character" : "\(next.name) needs \(missing.formatted()) more characters"
    }
}
