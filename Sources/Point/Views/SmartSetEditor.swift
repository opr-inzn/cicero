import SwiftUI

/// Presents the smart set and character set editors for whichever window shows the library.
struct SetEditorSheets: ViewModifier {
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        @Bindable var library = library
        content
            .sheet(item: $library.editingSmartSet) { SmartSetEditor(original: $0) }
            .sheet(item: $library.editingCharacterSet) { CharacterSetEditor(original: $0) }
    }
}

/// Name, match mode and rules of a smart set, with a live count of matching families.
struct SmartSetEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let original: SmartSet
    @State private var draft: SmartSet

    init(original: SmartSet) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { library.smartSet(original.id) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Smart Set" : "Edit Smart Set")
                .font(.headline)
            TextField("Name", text: $draft.name, prompt: Text("Smart Set Name"))
            HStack(spacing: 6) {
                Text("Include fonts that match")
                Picker("Match", selection: $draft.matchAll) {
                    Text("all").tag(true)
                    Text("any").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                Text("of these rules:")
            }
            VStack(spacing: 8) {
                ForEach($draft.rules) { $rule in
                    SmartRuleRow(rule: $rule, canRemove: draft.rules.count > 1) {
                        draft.rules.removeAll { $0.id == rule.id }
                    } add: {
                        let index = draft.rules.firstIndex { $0.id == rule.id }.map { $0 + 1 } ?? draft.rules.endIndex
                        draft.rules.insert(SmartRule(), at: index)
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            HStack {
                Text(matchCount)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private var matchCount: String {
        let count = library.families.count { family in
            (library.data.showSystemFonts || family.status != .system) && library.matches(family, draft)
        }
        return count == 1 ? "1 family matches" : "\(count.formatted()) families match"
    }

    private func save() {
        var result = draft
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew { library.addSmartSet(result) } else { library.updateSmartSet(result) }
        dismiss()
    }
}

private struct SmartRuleRow: View {
    @Environment(LibraryStore.self) private var library
    @Binding var rule: SmartRule
    let canRemove: Bool
    let remove: () -> Void
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Field", selection: Binding(get: { rule.field }, set: { rule = SmartRule(field: $0, keeping: rule.id) })) {
                ForEach(SmartRule.Field.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 160, alignment: .leading)
            Picker("Comparison", selection: $rule.comparison) {
                ForEach(rule.field.comparisons, id: \.self) { Text(rule.label(for: $0)).tag($0) }
            }
            .frame(width: 140, alignment: .leading)
            valueControl
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Button(action: remove) { Image(systemName: "minus.circle.fill") }
                    .disabled(!canRemove)
                    .help("Remove this rule")
                Button(action: add) { Image(systemName: "plus.circle.fill") }
                    .help("Add a rule")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .labelsHidden()
        .onAppear { fillDefaultValue() }
        .onChange(of: rule.field) { fillDefaultValue() }
    }

    @ViewBuilder
    private var valueControl: some View {
        switch rule.field {
        case .name:
            TextField("Text", text: $rule.value)
        case .foundry:
            if rule.comparison == .contains {
                TextField("Text", text: $rule.value)
            } else {
                optionPicker(library.foundryNames.map { ($0, $0) })
            }
        case .classification:
            optionPicker(FontClassification.allCases.map { ($0.rawValue, $0.rawValue) })
        case .tag:
            optionPicker(library.data.tags.map { ($0, $0) })
        case .set:
            optionPicker(library.data.sets.map { ($0.id.uuidString, $0.name) })
        case .folder:
            optionPicker(library.data.watchedFolders.map { ($0.id.uuidString, $0.displayName) }
                + [(WatchedFolder.deactivatedID.uuidString, "Deactivated")])
        case .status:
            optionPicker(SmartRuleOption.statuses.map { ($0.id, $0.title) })
        case .kind:
            optionPicker(SmartRuleOption.kinds.map { ($0.id, $0.title) })
        case .format:
            optionPicker(SmartRuleOption.formats.map { ($0, $0) })
        case .styles:
            numberField(unit: "styles")
        case .added:
            numberField(unit: "days")
        case .language:
            LanguagePickerButton(iso: $rule.value)
        case .characterSet:
            Picker("Character Set", selection: $rule.value) {
                ForEach(CharacterSetCatalog.groups) { group in
                    Section(group.name) {
                        ForEach(group.sets) { Text($0.name).tag($0.id) }
                    }
                }
                if !library.data.customCharacterSets.isEmpty {
                    Section("Your Character Sets") {
                        ForEach(library.data.customCharacterSets) { Text($0.name).tag($0.definitionID) }
                    }
                }
            }
        }
    }

    private func optionPicker(_ options: [(id: String, title: String)]) -> some View {
        Picker("Value", selection: $rule.value) {
            if options.isEmpty { Text("None").tag("") }
            ForEach(options, id: \.id) { Text($0.title).tag($0.id) }
            // Keep a value whose option has gone (e.g. a deleted tag) selectable instead of blank.
            if !rule.value.isEmpty && !options.contains(where: { $0.id == rule.value }) {
                Text(rule.value).tag(rule.value)
            }
        }
    }

    private func numberField(unit: String) -> some View {
        HStack(spacing: 6) {
            TextField("Number", text: $rule.value)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func fillDefaultValue() {
        guard rule.value.isEmpty else { return }
        rule.value = switch rule.field {
        case .foundry where rule.comparison != .contains: library.foundryNames.first ?? ""
        case .classification: FontClassification.serif.rawValue
        case .tag: library.data.tags.first ?? ""
        case .set: library.data.sets.first?.id.uuidString ?? ""
        case .folder: library.data.watchedFolders.first?.id.uuidString ?? ""
        case .status: "active"
        case .kind: "variable"
        case .format: SmartRuleOption.formats[0]
        case .language: Self.defaultLanguage
        case .characterSet: CharacterSetCatalog.builtIn.first?.id ?? ""
        default: rule.value
        }
    }

    /// The user's own language when Hyperglot knows it, else English.
    private static var defaultLanguage: String {
        for identifier in Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier(.alpha3),
               Languages.language(code) != nil {
                return code
            }
        }
        return "eng"
    }
}

private extension SmartRule {
    init(field: Field, keeping id: UUID) {
        self.init(field: field)
        self.id = id
    }
}

/// Picks a Hyperglot language from a searchable list.
struct LanguagePickerButton: View {
    @Binding var iso: String
    @State private var isPresented = false
    @State private var query = ""

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(Languages.language(iso)?.name ?? "Choose…")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField("Search", text: $query, prompt: Text("Search languages"))
                    .textFieldStyle(.roundedBorder)
                List(results) { language in
                    Button {
                        iso = language.iso
                        isPresented = false
                    } label: {
                        HStack {
                            Text(language.name)
                            if let autonym = language.autonym, autonym != language.name {
                                Text(autonym).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if language.iso == iso { Image(systemName: "checkmark") }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(10)
            .frame(width: 300, height: 360)
        }
    }

    private var results: [Language] {
        let all = Languages.all.sorted { $0.speakers > $1.speakers }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.autonym?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || $0.iso == trimmed.lowercased()
        }
    }
}
