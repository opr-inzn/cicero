import CiceroCore
import SwiftUI

enum ToolboxTab: String, CaseIterable {
    case text, languages

    var title: String {
        switch self {
        case .text: "Text"
        case .languages: "Languages"
        }
    }
}

/// Which fonts have every character of a text, and which support a language.
struct ToolboxWindow: View {
    @AppStorage("toolbox.tab") private var tab: ToolboxTab = .text

    var body: some View {
        Group {
            switch tab {
            case .text: TextTab()
            case .languages: LanguagesTab()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(ToolboxTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

extension LanguageCatalog {
    /// The user's language when the catalog knows it, else English.
    var preferredLanguageID: String {
        let code = Locale.current.language.languageCode?.identifier(.alpha3) ?? "eng"
        return language(code) != nil ? code : "eng"
    }
}

// MARK: - Text

private struct TextTab: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.openWindow) private var openWindow
    @AppStorage("toolbox.text") private var text = ""
    @AppStorage("toolbox.maxMissing") private var maxMissing = 0
    @AppStorage("toolbox.activatedOnly") private var activatedOnly = false
    @State private var matches: [TextMatch] = []
    @State private var unindexed = 0
    @State private var isSearching = false
    @State private var selection: Set<String> = []

    private struct Query: Equatable {
        var text: String
        var maxMissing: Int
        var activatedOnly: Bool
        var showSystem: Bool
        var fingerprint: Int
        var coverageRevision: Int
    }

    private var query: Query {
        Query(text: text.trimmingCharacters(in: .whitespacesAndNewlines), maxMissing: maxMissing, activatedOnly: activatedOnly,
              showSystem: model.data.showSystemFonts, fingerprint: model.library.fingerprint, coverageRevision: model.coverageRevision)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if query.text.isEmpty {
                ContentUnavailableView("Find Fonts for a Text", systemImage: "character.cursor.ibeam",
                                       description: Text("Type or paste text, and Cicero lists the fonts that have every character in it."))
                    .frame(maxHeight: .infinity)
            } else if matches.isEmpty && !isSearching {
                ContentUnavailableView("No Fonts Have Every Character", systemImage: "character.textbox",
                                       description: Text(unindexed > 0 ? "Some fonts are still being checked." : "Allow a few missing characters to see the closest fonts."))
                    .frame(maxHeight: .infinity)
            } else {
                table
            }
        }
        // Keeps the controls at the top while the empty states fill the space below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: query) { await search(query) }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            TextField("Text", text: $text, prompt: Text("Type or paste text"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            Stepper(value: $maxMissing, in: 0...20) {
                Text("Include fonts missing up to \(maxMissing) \(maxMissing == 1 ? "character" : "characters")")
            }
            Toggle("Activated only", isOn: $activatedOnly)
            Spacer()
            Text(summary).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(12)
    }

    private var summary: String {
        guard !query.text.isEmpty else { return "" }
        let count = matches.count == 1 ? "1 family" : "\(matches.count.formatted()) families"
        if let progress = model.coverageProgress {
            return "\(count) · checking characters, \(progress.done.formatted()) of \(progress.total.formatted())"
        }
        return count
    }

    private var table: some View {
        let model = self.model
        let preview = self.preview
        let sample = query.text
        return Table(matches, selection: $selection) {
            TableColumn("Name") { match in
                HStack(spacing: 6) {
                    Text(match.family.name).lineLimit(1)
                    StatusTag(family: match.family)
                }
                .draggable(match.family.name)
            }
            .width(min: 140, ideal: 220)

            TableColumn("Sample") { match in
                FontText(
                    text: sample, face: match.family.face(nearestWeight: preview.weight).face, size: 17, weight: preview.weight,
                    features: model.features(for: match.family), kerning: preview.kerning(at: 17)
                )
                .frame(height: 22)
            }
            .width(min: 200, ideal: 460)

            TableColumn("Missing") { match in
                Text(Self.characters(match.missing)).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 160)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            FamilyMenu(families: ids.compactMap(model.family), model: model)
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { open(id) }
        }
        .onKeyPress(.return) {
            guard selection.count == 1, let id = selection.first else { return .ignored }
            open(id)
            return .handled
        }
    }

    private static func characters(_ scalars: [UInt32]) -> String {
        scalars.compactMap { Unicode.Scalar($0) }.map { String(Character($0)) }.joined(separator: " ")
    }

    private func open(_ id: String) {
        model.openFamilyID = id
        openWindow(id: WindowID.main)
    }

    private func search(_ query: Query) async {
        guard !query.text.isEmpty else {
            matches = []
            unindexed = 0
            return
        }
        isSearching = true
        // Wait for a pause in typing before walking a big library.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let families = model.library.families.filter { family in
            (query.showSystem || family.state != .system) && (!query.activatedOnly || family.hasActive)
        }
        let index = model.coverage
        let text = query.text
        let maxMissing = query.maxMissing
        let result = await Task.detached(priority: .userInitiated) {
            CoverageSearch.families(having: text, in: families, maxMissing: maxMissing, index: index)
        }.value
        guard !Task.isCancelled else { return }
        matches = result.matches
        unindexed = result.unindexed
        isSearching = false
    }
}

// MARK: - Languages

private struct LanguagesTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("toolbox.languageSort") private var sortByName = false
    @AppStorage("toolbox.language") private var languageID = ""
    @State private var search = ""
    @State private var support = LanguageSupport()
    @State private var selection: Set<String> = []

    private struct LanguageSupport {
        var full: [Family] = []
        var base: [Family] = []
        var unindexed = 0
    }

    private struct Query: Equatable {
        var id: String
        var showSystem: Bool
        var fingerprint: Int
        var coverageRevision: Int
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
            detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if languageID.isEmpty { languageID = model.languages.preferredLanguageID }
        }
    }

    // MARK: List

    private var languages: [Language] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = model.languages.languages
        let found = query.isEmpty ? all : all.filter { language in
            language.name.localizedCaseInsensitiveContains(query)
                || (language.autonym?.localizedCaseInsensitiveContains(query) ?? false)
                || language.scripts.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return found.sorted { a, b in
            if sortByName || a.speakers == b.speakers { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return a.speakers > b.speakers
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search", text: $search, prompt: Text("Language, autonym or script"))
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $sortByName) {
                    Text("Speakers").tag(false)
                    Text("Name").tag(true)
                }
                .labelsHidden()
                .fixedSize()
                .help("Sort by speakers or by name")
            }
            .padding(10)
            List(languages, selection: Binding(get: { languageID.isEmpty ? nil : languageID }, set: { languageID = $0 ?? "" })) { language in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(language.name)
                        Text(Self.subtitle(language)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(language.speakers, format: .number.notation(.compactName))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private static func subtitle(_ language: Language) -> String {
        var parts: [String] = []
        if let autonym = language.autonym, autonym != language.name { parts.append(autonym) }
        parts.append(language.scripts.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let language = model.languages.language(languageID) {
            let query = Query(id: language.id, showSystem: model.data.showSystemFonts, fingerprint: model.library.fingerprint, coverageRevision: model.coverageRevision)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(language.name).font(.title2.bold())
                        if let autonym = language.autonym, autonym != language.name {
                            Text(autonym).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    Text(facts(language)).foregroundStyle(.secondary)
                    Text(language.sampleCharacters)
                        .font(.title3)
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                List(selection: $selection) {
                    section("Fully Supported", support.full, language)
                    section("Base Characters Only", support.base, language)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    FamilyMenu(families: ids.compactMap(model.family), model: model)
                } primaryAction: { ids in
                    if ids.count == 1, let id = ids.first { open(id) }
                }
                .onKeyPress(.return) {
                    guard selection.count == 1, let id = selection.first else { return .ignored }
                    open(id)
                    return .handled
                }
            }
            .task(id: query) { await load(query) }
        } else {
            ContentUnavailableView("No Language Selected", systemImage: "globe",
                                   description: Text("Choose a language to see which fonts support it."))
        }
    }

    private func facts(_ language: Language) -> String {
        var parts = ["\(language.scripts.joined(separator: ", ")) · \(language.speakers.formatted(.number.notation(.compactName))) speakers"]
        if let progress = model.coverageProgress, support.unindexed > 0 {
            parts.append("checking characters, \(progress.done.formatted()) of \(progress.total.formatted())")
        }
        return parts.joined(separator: " · ")
    }

    private func section(_ title: String, _ families: [Family], _ language: Language) -> some View {
        Section("\(title) (\(families.count.formatted()))") {
            if families.isEmpty {
                Text("None").foregroundStyle(.tertiary).selectionDisabled()
            }
            ForEach(families) { family in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(family.name).lineLimit(1)
                        StatusTag(family: family)
                    }
                    .frame(width: 220, alignment: .leading)
                    FontText(text: language.sampleCharacters, face: family.regular.face, size: 17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .draggable(family.name)
            }
        }
    }

    private func open(_ id: String) {
        model.openFamilyID = id
        openWindow(id: WindowID.main)
    }

    private func load(_ query: Query) async {
        let families = model.library.families.filter { query.showSystem || $0.state != .system }
        let index = model.coverage
        let id = query.id
        let result = await Task.detached(priority: .userInitiated) {
            CoverageSearch.families(supporting: id, in: families, index: index)
        }.value
        guard !Task.isCancelled else { return }
        support = LanguageSupport(full: result.full, base: result.base, unindexed: result.unindexed)
    }
}
