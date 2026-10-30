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
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
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
                ToolbarPicker("View", values: ToolboxTab.allCases, selection: $tab, title: \.title)
            }
        }
        // Turning fonts on or off from a font's menu here can ask first, which the Library window does: it comes forward.
        .onChange(of: model.manyActivationPrompt?.id) { _, id in if id != nil { openWindow(id: WindowID.main) } }
        .onChange(of: model.movingOutPrompt?.id) { _, id in if id != nil { openWindow(id: WindowID.main) } }
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
        var showCreativeCloud: Bool
        var fingerprint: Int
        var coverageRevision: Int
    }

    private var query: Query {
        Query(text: text.trimmingCharacters(in: .whitespacesAndNewlines), maxMissing: maxMissing, activatedOnly: activatedOnly,
              showSystem: model.data.showSystemFonts, showCreativeCloud: model.data.showCreativeCloudFonts, fingerprint: model.library.fingerprint,
              coverageRevision: model.coverageRevision)
    }

    var body: some View {
        // The rows stay, empty, under the messages rather than make way for them: the bar is rebuilt when the
        // scroll view under it comes or goes, and the text field in it lost focus with the first letter typed.
        ZStack {
            table
            if query.text.isEmpty {
                EmptyState("Find Fonts for a Text", systemImage: "character.cursor.ibeam",
                           description: Text("Type or paste text, and Cicero lists the fonts that have every character in it."))
            } else if matches.isEmpty && !isSearching {
                EmptyState("No Fonts Have Every Character", systemImage: "character.textbox",
                           description: Text(unindexed > 0 ? "Some fonts are still being checked." : "Allow a few missing characters to see the closest fonts."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The fonts scroll under the controls and column titles.
        .fadingTopBar {
            VStack(spacing: 0) {
                controls
                if !query.text.isEmpty && !(matches.isEmpty && !isSearching) { columnTitles }
            }
        }
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
            Toggle("Active only", isOn: $activatedOnly)
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
        // Clearing the text leaves the last matches until the search catches up.
        let matches = sample.isEmpty ? [] : self.matches
        let missing = Dictionary(matches.map { ($0.family.id, $0.missing) }) { first, _ in first }
        return FamilyRowList(sections: [FamilyRowSection(id: "matches", families: matches.map(\.family))], selection: $selection, open: open) { family in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(family.name).lineLimit(1)
                        StatusTag(family: family)
                    }
                    .frame(width: 220, alignment: .leading)
                    FontText(
                        text: sample, face: family.face(nearestWeight: preview.weight).face, size: 17, weight: preview.weight,
                        variations: model.variations(for: family)
                    )
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Glyphs taller than the row run over its edges rather than be cut off.
                    .frame(height: 22)
                    Text(Self.characters(missing[family.id] ?? [])).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 160, alignment: .leading)
                }
            }
    }

    private var columnTitles: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: 220, alignment: .leading)
            Text("Sample").frame(maxWidth: .infinity, alignment: .leading)
            Text("Missing").frame(width: 160, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
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
        let data = model.data
        let families = model.library.families.filter { family in
            data.lists(family) && (!query.activatedOnly || family.hasActive)
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
        var showCreativeCloud: Bool
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
        // The languages scroll under the search field.
        .fadingTopBar {
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
            let query = Query(id: language.id, showSystem: model.data.showSystemFonts, showCreativeCloud: model.data.showCreativeCloudFonts,
                              fingerprint: model.library.fingerprint, coverageRevision: model.coverageRevision)
            FamilyRowList(sections: [
                FamilyRowSection(id: "full", title: "Fully Supported (\(support.full.count.formatted()))", families: support.full, emptyText: "None"),
                FamilyRowSection(id: "base", title: "Base Characters Only (\(support.base.count.formatted()))", families: support.base, emptyText: "None"),
            ], selection: $selection, open: open) { family in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(family.name).lineLimit(1)
                        StatusTag(family: family)
                    }
                    .frame(width: 220, alignment: .leading)
                    FontText(text: language.sampleCharacters, face: family.regular.face, size: 17)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22)
                }
            }
            // The fonts scroll under the language.
            .fadingTopBar {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .task(id: query) { await load(query) }
        } else {
            EmptyState("No Language Selected", systemImage: "globe",
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

    private func open(_ id: String) {
        model.openFamilyID = id
        openWindow(id: WindowID.main)
    }

    private func load(_ query: Query) async {
        let data = model.data
        let families = model.library.families.filter { data.lists($0) }
        let index = model.coverage
        let id = query.id
        let result = await Task.detached(priority: .userInitiated) {
            CoverageSearch.families(supporting: id, in: families, index: index)
        }.value
        guard !Task.isCancelled else { return }
        support = LanguageSupport(full: result.full, base: result.base, unindexed: result.unindexed)
    }
}
