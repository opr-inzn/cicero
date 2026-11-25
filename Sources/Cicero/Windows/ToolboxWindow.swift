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

struct ToolboxWindow: View {
    @AppStorage("toolbox.tab") private var tab: ToolboxTab = .text
    @State private var opened: Set<ToolboxTab> = []

    var body: some View {
        ZStack {
            if opened.contains(.text) || tab == .text { shown(TextTab(), for: .text) }
            if opened.contains(.languages) || tab == .languages { shown(LanguagesTab(), for: .languages) }
        }
        .onChange(of: tab, initial: true) { opened.insert(tab) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarPicker("View", values: ToolboxTab.allCases, selection: $tab, title: \.title)
            }
        }
    }

    private func shown(_ content: some View, for tab: ToolboxTab) -> some View {
        let isShown = self.tab == tab
        return content
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .disabled(!isShown)
            .accessibilityHidden(!isShown)
    }
}

extension LanguageCatalog {
    var preferredLanguageID: String {
        let code = Locale.current.language.languageCode?.identifier(.alpha3) ?? "eng"
        return language(code) != nil ? code : "eng"
    }
}

// MARK: - Text

private struct TextTab: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Bindable private var savedText = SavedSoon.toolboxText
    private var text: String { savedText.value }
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
        // The rows stay, empty, under the messages: the bar is rebuilt when the scroll view under it comes or goes, and the text field in it lost focus with the first letter typed.
        ZStack {
            table
            if query.text.isEmpty {
                EmptyState("Find Fonts for Text", systemImage: "character.cursor.ibeam",
                           description: Text("Type or paste text, and Cicero lists the fonts that have every character in it."))
            } else if matches.isEmpty && !isSearching {
                EmptyState(maxMissing == 0 ? "No Fonts Have Every Character" : "No Matching Fonts", systemImage: "character.textbox",
                           description: Text(unindexed > 0 ? "Some fonts are still being checked."
                               : maxMissing == 0 ? "Allow a few missing characters to see the closest fonts."
                               : maxMissing < 20 ? "Allow more missing characters to see closer matches."
                               : "No fonts in your library match this text."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .topBar {
            VStack(spacing: 0) {
                controls
                if !query.text.isEmpty && !(matches.isEmpty && !isSearching) { columnTitles }
            }
        }
        .hardTopScrollEdge()
        .task(id: query) { await search(query) }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            TextField("Text", text: $savedText.value, prompt: Text("Type or paste text"))
                .textFieldStyle(.roundedBorder)
                .noAutoFill()
                .frame(minWidth: 160, maxWidth: 400)
            Stepper(value: $maxMissing, in: 0...20) {
                Text("Missing characters allowed: \(maxMissing.plain)")
            }
            .fixedSize()
            Toggle("Active only", isOn: $activatedOnly)
                .fixedSize()
            Spacer(minLength: 0)
            Text(summary).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .padding([.horizontal, .top], 12)
        .padding(.bottom, 6)
    }

    private var summary: String {
        guard !query.text.isEmpty else { return "" }
        let count = matches.count == 1 ? "1 Family" : "\(matches.count.plain) Families"
        if let progress = model.coverageProgress {
            return "\(count) · checking characters, \(progress.done.plain) of \(progress.total.plain)…"
        }
        return count
    }

    private var table: some View {
        let model = self.model
        let sample = query.text
        let matches = sample.isEmpty ? [] : self.matches
        let missing = Dictionary(matches.map { ($0.family.id, $0.missing) }) { first, _ in first }
        return FamilyRowList(sections: [FamilyRowSection(id: "matches", families: matches.map(\.family))], selection: $selection) { family in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(family.name).lineLimit(1).truncationMode(.middle)
                        StatusTag(family: family)
                    }
                    .frame(width: 220, alignment: .leading)
                    FontText(
                        text: sample, face: family.regular.face, size: 17,
                        variations: model.variations(for: family)
                    )
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22)
                    Text(Self.characters(missing[family.id] ?? [])).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 160, alignment: .leading)
                }
            }
    }

    private var columnTitles: some View {
        let divider = Rectangle().fill(.separator).frame(width: 1, height: 16).frame(width: 12)
        return HStack(spacing: 0) {
            Text("Name").frame(width: 220, alignment: .leading)
            divider
            Text("Preview").frame(maxWidth: .infinity, alignment: .leading)
            divider
            Text("Missing").frame(width: 160, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, ListRowBackground.contentInset)
        .frame(height: 28)
        .overlay(alignment: .bottom) { Divider() }
    }

    private static func characters(_ scalars: [UInt32]) -> String {
        scalars.compactMap { Unicode.Scalar($0) }.map { String(Character($0)) }.joined(separator: " ")
    }

    private func search(_ query: Query) async {
        guard !query.text.isEmpty else {
            isSearching = false
            matches = []
            unindexed = 0
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let data = model.data
        let families = model.library.families.filter { family in
            data.lists(family) && (!query.activatedOnly || family.hasActive)
        }
        let index = model.coverage
        let text = query.text
        let maxMissing = query.maxMissing
        let work = Task.detached(priority: .userInitiated) {
            CoverageSearch.families(having: text, in: families, maxMissing: maxMissing, index: index)
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        matches = result.matches
        unindexed = result.unindexed
        isSearching = false
    }
}

// MARK: - Languages

private struct LanguagesTab: View {
    @Environment(AppModel.self) private var model
    @AppStorage("toolbox.languageSort") private var sortByName = false
    @AppStorage("toolbox.language") private var languageID = ""
    @State private var search = ""
    @State private var support = LanguageSupport()
    @State private var selection: Set<String> = []
    @State private var languageCache = LanguageListCache()

    private final class LanguageListCache {
        var key: (search: String, sortByName: Bool, count: Int)?
        var languages: [Language] = []
    }

    private struct LanguageSupport {
        var languageID = ""
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
            list.frame(minWidth: 260, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
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
        if let cached = languageCache.key, cached.search == query, cached.sortByName == sortByName, cached.count == all.count {
            return languageCache.languages
        }
        let found = query.isEmpty ? all : all.filter { language in
            language.name.localizedCaseInsensitiveContains(query)
                || (language.autonym?.localizedCaseInsensitiveContains(query) ?? false)
                || language.scripts.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let sorted = found.sorted { a, b in
            if sortByName || a.speakers == b.speakers { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return a.speakers > b.speakers
        }
        languageCache.key = (query, sortByName, all.count)
        languageCache.languages = sorted
        return sorted
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
        .topBar {
            HStack(spacing: 8) {
                TextField("Search", text: $search, prompt: Text("Language or script"))
                    .textFieldStyle(.roundedBorder)
                    .noAutoFill()
                Picker("Sort", selection: $sortByName) {
                    Text("Name").tag(true)
                    Text("Speakers").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .help("Sort by name or by speakers")
            }
            .padding(10)
            .overlay(alignment: .bottom) { Divider() }
        }
        .hardTopScrollEdge()
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
            let shown = support.languageID == language.id ? support : LanguageSupport(languageID: language.id)
            FamilyRowList(sections: [
                FamilyRowSection(id: "full", title: "Fully Supported (\(shown.full.count.plain))", families: shown.full, emptyText: "None"),
                FamilyRowSection(id: "base", title: "Base Characters Only (\(shown.base.count.plain))", families: shown.base, emptyText: "None"),
            ], selection: $selection) { family in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(family.name).lineLimit(1).truncationMode(.middle)
                        StatusTag(family: family)
                    }
                    .frame(width: 220, alignment: .leading)
                    FontText(text: language.sampleCharacters, face: family.regular.face, size: 17)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22)
                }
            }
            .topBar {
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
            .hardTopScrollEdge()
            .task(id: query) { await load(query) }
        } else {
            EmptyState("No Language Selected", systemImage: "globe",
                       description: Text("Choose a language to see which fonts support it."))
        }
    }

    private func facts(_ language: Language) -> String {
        var parts = ["\(language.scripts.joined(separator: ", ")) · \(language.speakers.formatted(.number.notation(.compactName))) speakers"]
        if let progress = model.coverageProgress, support.unindexed > 0 {
            parts.append("checking characters, \(progress.done.plain) of \(progress.total.plain)…")
        }
        return parts.joined(separator: " · ")
    }

    private func load(_ query: Query) async {
        let data = model.data
        let families = model.library.families.filter { data.lists($0) }
        let index = model.coverage
        let id = query.id
        let work = Task.detached(priority: .userInitiated) {
            CoverageSearch.families(supporting: id, in: families, index: index)
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        support = LanguageSupport(languageID: id, full: result.full, base: result.base, unindexed: result.unindexed)
    }
}
