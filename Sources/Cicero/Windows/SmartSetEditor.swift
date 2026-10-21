import CiceroCore
import SwiftUI

/// The sheet for a new or existing smart set: name, match all or any, and a row per rule.
struct SmartSetEditor: View {
    let original: SmartSet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SmartSet
    /// Whether the set was new when the sheet opened: saving or deleting it changes that while the sheet is still closing.
    @State private var openedAsNew: Bool?

    init(original: SmartSet) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { openedAsNew ?? !model.data.smartSets.contains { $0.id == original.id } }
    private var name: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.name, prompt: Text("Smart Set"))
                Picker("Match", selection: $draft.matchAll) {
                    Text("All of the rules").tag(true)
                    Text("Any of the rules").tag(false)
                }
                Section("Rules") {
                    ForEach($draft.rules) { $rule in
                        RuleRow(rule: $rule, canRemove: draft.rules.count > 1) {
                            draft.rules.removeAll { $0.id == rule.id }
                        } add: {
                            let position = draft.rules.firstIndex { $0.id == rule.id } ?? draft.rules.count - 1
                            draft.rules.insert(SmartRule(), at: position + 1)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text(matchSummary).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Create" : "Save") {
                    var saved = draft
                    saved.name = name
                    model.saveSmartSet(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 700, height: 480)
        .onAppear { openedAsNew = isNew }
    }

    private var matchSummary: String {
        let test = model.matcher(for: draft)
        let data = model.data
        let count = model.library.families.count { data.lists($0) && test($0) }
        return count == 1 ? "1 family matches" : "\(count.formatted()) families match"
    }
}

/// Field · comparison · value, with the value control the field needs.
private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    @Binding var rule: SmartRule
    let canRemove: Bool
    let remove: () -> Void
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Field", selection: field) {
                ForEach(fields, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Picker("Comparison", selection: $rule.comparison) {
                ForEach(rule.field.comparisons, id: \.self) { Text($0.title(for: rule.field)).tag($0) }
            }
            .fixedSize()
            value
            Spacer(minLength: 0)
            rowButton("Remove Rule", icon: "minus.circle", action: remove)
                .disabled(!canRemove)
            rowButton("Add Rule", icon: "plus.circle", action: add)
        }
        .labelsHidden()
    }

    private func rowButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
    }

    /// The user's folders, then Testing when its fonts are shown, Adobe Fonts when there are some and they're shown,
    /// Added Fonts when there are some, and the Font Library when it has fonts.
    private var folderOptions: [(id: String, title: String)] {
        let own = (model.data.showAdobeAppFolders ? [WatchedFolder.adobeAppsID] : [])
            + (model.ownFoldersWithFonts.contains(WatchedFolder.adobeFontsID) ? [WatchedFolder.adobeFontsID] : [])
            + (model.data.fontFiles.isEmpty ? [] : [WatchedFolder.addedFilesID])
            + (model.ownFoldersWithFonts.contains(WatchedFolder.fontLibraryID) ? [WatchedFolder.fontLibraryID] : [])
        return model.data.namedFolders.map { ($0.id.uuidString, $0.displayName) } + own.map { ($0.uuidString, model.folderName($0)) }
    }

    /// The fields a new rule offers, and the rule's own when it's one no longer offered.
    private var fields: [SmartRule.Field] {
        SmartRule.Field.offered.contains(rule.field) ? SmartRule.Field.offered : SmartRule.Field.offered + [rule.field]
    }

    /// Changing the field resets the comparison and value to ones that make sense for it.
    private var field: Binding<SmartRule.Field> {
        Binding(get: { rule.field }, set: { new in
            guard new != rule.field else { return }
            rule = SmartRule(id: rule.id, field: new, value: defaultValue(for: new))
        })
    }

    private func defaultValue(for field: SmartRule.Field) -> String {
        switch field {
        case .name: ""
        case .foundry: model.foundryNames.first ?? ""
        case .designer: ""
        case .classification: model.classificationNames[0]
        case .tag: model.data.tags.first ?? ""
        case .rating: "5"
        case .note, .hasNote: ""
        case .set: model.data.sets.first?.id.uuidString ?? ""
        case .folder: folderOptions.first?.id ?? ""
        case .status: SmartRuleValue.statuses[0]
        case .kind: SmartRuleValue.kinds[0]
        case .format: FontFormat.openTypePostScript.rawValue
        case .styles: "2"
        case .feature: OpenTypeFeature.smallCaps.rawValue
        case .embedding: Embedding.installable.rawValue
        case .added, .lastActivated: "30"
        case .timesActivated: "0"
        case .language: model.languages.preferredLanguageID
        case .characterSet: model.characterSetCatalog.builtIn.first?.id ?? ""
        }
    }

    @ViewBuilder
    private var value: some View {
        switch rule.field {
        case .name:
            text
        case .foundry:
            if rule.comparison == .contains {
                text
            } else {
                options(model.foundryNames.map { ($0, $0) }, empty: "No foundries yet")
            }
        case .designer:
            text
        case .note:
            text
        case .hasNote:
            EmptyView()
        case .classification:
            options(model.classificationNames.map { ($0, $0) })
        case .tag:
            options(model.data.tags.map { ($0, $0) }, empty: "No tags yet", colors: model.data.tagColors)
        case .rating:
            // The most stars first, as in the family's Rating menu.
            options([("0", "No Rating")] + (1...5).reversed().map { (String($0), Rating.stars($0)) })
        case .set:
            options(model.data.sets.map { ($0.id.uuidString, $0.name) }, empty: "No sets yet")
        case .folder:
            options(folderOptions, empty: "No folders yet")
        case .status:
            options(SmartRuleValue.statuses.map { ($0, Self.statusTitle($0)) })
        case .kind:
            options(SmartRuleValue.kinds.map { ($0, Self.kindTitle($0)) })
        case .format:
            options(FontFormat.allCases.map { ($0.rawValue, $0.rawValue) })
        case .styles:
            number(in: 0...999)
        case .feature:
            options(OpenTypeFeature.allCases.map { ($0.rawValue, $0.title) })
        case .embedding:
            options(Embedding.allCases.map { ($0.rawValue, $0.title) })
        case .added, .lastActivated:
            number(unit: "days", in: 1...3650)
        case .timesActivated:
            number(in: 0...99_999)
        case .language:
            LanguagePicker(selection: $rule.value, catalog: model.languages)
        case .characterSet:
            characterSets
        }
    }

    private var text: some View {
        TextField("Text", text: $rule.value, prompt: Text("Text"))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 140, maxWidth: 260)
    }

    /// A pop-up of the options, each with the dot of its colour, if it has one, like a tag's.
    @ViewBuilder
    private func options(_ options: [(id: String, title: String)], empty: String = "", colors: [String: TagColor] = [:]) -> some View {
        if options.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            Picker("Value", selection: $rule.value) {
                ForEach(options, id: \.id) { option in
                    if let color = colors[option.id] {
                        Label { Text(option.title) } icon: { Image(nsImage: color.menuImage) }
                            .labelStyle(.titleAndIcon)
                            .tag(option.id)
                    } else {
                        Text(option.title).tag(option.id)
                    }
                }
            }
            .fixedSize()
        }
    }

    /// A field for the number, with its unit after it where the field's name doesn't say it, like days.
    private func number(unit: String? = nil, in range: ClosedRange<Int>) -> some View {
        let number = Binding<Int>(
            get: { Int(rule.value) ?? range.lowerBound },
            set: { rule.value = String(min(max($0, range.lowerBound), range.upperBound)) }
        )
        return HStack(spacing: 6) {
            TextField("Number", value: number, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            if let unit {
                Text(unit)
            }
        }
    }

    private var characterSets: some View {
        Picker("Coverage Set", selection: $rule.value) {
            ForEach(model.characterSetCatalog.groups) { group in
                Section(group.name) {
                    ForEach(group.sets) { Text($0.name).tag($0.id) }
                }
            }
            let custom = model.customCharacterSets
            if !custom.isEmpty {
                Section("Your Coverage Sets") {
                    ForEach(custom) { Text($0.name).tag($0.id) }
                }
            }
        }
        .fixedSize()
    }

    private static func statusTitle(_ value: String) -> String {
        switch value {
        case "active": "Active"
        case "partial": "Partly Active"
        case "inactive": "Inactive"
        case "appOnly": "Active in Apps Only"
        default: "Installed with macOS"
        }
    }

    private static func kindTitle(_ value: String) -> String {
        switch value {
        case "variable": "Variable"
        case "monospaced": "Monospaced"
        default: "Italic"
        }
    }
}

/// A pop-up of Hyperglot's languages: searchable, sorted by speakers.
private struct LanguagePicker: View {
    @Binding var selection: String
    let catalog: LanguageCatalog
    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(catalog.language(selection)?.name ?? "Choose Language")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField("Search", text: $search, prompt: Text("Search"))
                    .textFieldStyle(.roundedBorder)
                List(languages, selection: Binding<String?>(
                    get: { selection },
                    set: { id in
                        guard let id else { return }
                        selection = id
                        isPresented = false
                    }
                )) { language in
                    HStack {
                        Text(language.name)
                        if let autonym = language.autonym, autonym != language.name {
                            Text(autonym).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(language.speakers, format: .number.notation(.compactName))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(10)
            .frame(width: 340, height: 380)
        }
    }

    private var languages: [Language] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = catalog.languages
        let found = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.autonym?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return found.sorted { a, b in
            a.speakers == b.speakers ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.speakers > b.speakers
        }
    }
}

private extension SmartRule.Field {
    var title: String {
        switch self {
        case .name: "Name"
        case .foundry: "Foundry"
        case .designer: "Designer"
        case .classification: "Classification"
        case .tag: "Tag"
        case .rating: "Rating"
        case .note: "Note"
        case .hasNote: "Has Note"
        case .set: "Set"
        case .folder: "Folder"
        case .status: "Status"
        case .kind: "Kind"
        case .format: "Format"
        case .styles: "Number of Styles"
        case .feature: "OpenType Feature"
        case .embedding: "Embedding"
        case .language: "Language"
        case .characterSet: "Coverage"
        case .added: "Date Added"
        case .timesActivated: "Times Activated"
        case .lastActivated: "Last Activated"
        }
    }
}

private extension SmartRule.Comparison {
    /// The wording depends on the field: a set "is in", a language or an OpenType feature "is supported", coverage
    /// "includes", Has Note is Yes or No. A tag "is" any of the family's.
    func title(for field: SmartRule.Field) -> String {
        switch (field, self) {
        case (.set, .is), (.folder, .is): "is in"
        case (.set, .isNot), (.folder, .isNot): "isn’t in"
        case (.language, .is), (.feature, .is): "is supported"
        case (.language, .isNot), (.feature, .isNot): "isn’t supported"
        case (.characterSet, .is): "includes"
        case (.characterSet, .isNot): "doesn’t include"
        case (.hasNote, .is): "Yes"
        case (.hasNote, .isNot): "No"
        case (_, .contains): "contains"
        case (_, .doesNotContain): "doesn’t contain"
        case (_, .beginsWith): "begins with"
        case (_, .is): "is"
        case (_, .isNot): "is not"
        case (_, .greaterThan): "is more than"
        case (_, .lessThan): "is less than"
        case (_, .inLast): "is in the last"
        case (_, .notInLast): "isn’t in the last"
        }
    }
}
