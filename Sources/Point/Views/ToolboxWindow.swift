import SwiftUI

enum ToolboxTab: String, CaseIterable {
    case text = "Text"
    case languages = "Languages"
}

/// Finds fonts by what they can show: every family that has the characters of a text, or that
/// supports a language. Double-clicking a family opens it in the main window.
struct ToolboxWindow: View {
    @AppStorage("toolbox.tab") private var tab: ToolboxTab = .text

    var body: some View {
        let coverage = CharacterCoverage.shared
        Group {
            switch tab {
            case .text: TextToolbox()
            case .languages: LanguageToolbox()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tool", selection: $tab) {
                    ForEach(ToolboxTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if coverage.isIndexing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Indexing fonts… \(coverage.indexedCount) of \(coverage.totalCount)")
                        .font(.callout)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(16)
            }
        }
    }
}

// MARK: - Text

private struct TextToolbox: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("toolbox.text") private var text = ""
    @AppStorage("toolbox.allowMissing") private var allowMissing = false
    @AppStorage("toolbox.maxMissing") private var maxMissing = 3
    @AppStorage("toolbox.activatedOnly") private var activatedOnly = false
    @State private var results = TextMatches()
    @State private var selection: String?

    private struct Key: Equatable {
        var text: String
        var maxMissing: Int
        var activatedOnly: Bool
        var showSystem: Bool
        var generation: Int
        var familyCount: Int
    }

    var body: some View {
        let coverage = CharacterCoverage.shared
        let key = Key(
            text: text, maxMissing: allowMissing ? maxMissing : 0, activatedOnly: activatedOnly,
            showSystem: library.data.showSystemFonts, generation: coverage.generation, familyCount: library.families.count
        )
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Text", text: $text, prompt: Text("Type or paste text to find fonts that can show it"), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 14) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Toggle("Activated only", isOn: $activatedOnly)
                    Toggle("Include fonts missing up to", isOn: $allowMissing)
                    Stepper("\(maxMissing)", value: $maxMissing, in: 1...20)
                        .monospacedDigit()
                        .disabled(!allowMissing)
                }
                .toggleStyle(.checkbox)
            }
            .padding(16)
            Divider()
            List(results.matches, selection: $selection) { match in
                FamilyRow(family: match.family, sample: firstLine, note: note(for: match))
                    .modifier(OpensFamily(family: match.family))
                    .tag(match.id)
            }
            .overlay { placeholder }
        }
        .task(id: key) { await match(key) }
        .onKeyPress(.return) {
            guard let selection, let family = library.family(named: selection) else { return .ignored }
            OpensFamily.open(family, in: library, openWindow: openWindow)
            return .handled
        }
    }

    private var firstLine: String {
        String(text.prefix { !$0.isNewline })
    }

    private var summary: String {
        guard results.scalarCount > 0 else { return " " }
        let complete = results.matches.filter(\.missing.isEmpty).count
        var parts = [complete == 1 ? "1 font has every character" : "\(complete.formatted()) fonts have every character"]
        if allowMissing {
            let partial = results.matches.count - complete
            parts.append("\(partial.formatted()) missing up to \(maxMissing)")
        }
        if results.unindexed > 0 { parts.append("\(results.unindexed.formatted()) not indexed yet") }
        return parts.joined(separator: " · ")
    }

    private func note(for match: TextMatch) -> String? {
        guard !match.missing.isEmpty else { return nil }
        let characters = match.missing.compactMap(Unicode.Scalar.init).map { String($0) }.joined(separator: " ")
        return "Missing: \(characters)"
    }

    @ViewBuilder
    private var placeholder: some View {
        if results.scalarCount == 0 {
            ContentUnavailableView("Find Fonts for a Text", systemImage: "character.cursor.ibeam",
                                   description: Text("Type or paste text above to list every font that has all of its characters."))
        } else if results.matches.isEmpty {
            if results.unindexed > 0 && (library.isScanning || CharacterCoverage.shared.isIndexing) {
                ProgressView()
            } else {
                ContentUnavailableView("No Fonts Have Every Character", systemImage: "character.cursor.ibeam",
                                       description: Text("Try a shorter text, or include fonts that are missing a few characters."))
            }
        }
    }

    private func match(_ key: Key) async {
        guard !CharacterCoverage.scalars(in: key.text).isEmpty else {
            results = TextMatches()
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let families = library.families.filter {
            (key.showSystem || $0.status != .system) && (!key.activatedOnly || $0.hasActiveFaces)
        }
        let coverage = CharacterCoverage.shared
        let result = await Task.detached(priority: .userInitiated) {
            coverage.matches(for: key.text, in: families, maxMissing: key.maxMissing)
        }.value
        guard !Task.isCancelled else { return }
        results = result
    }
}

// MARK: - Languages

private enum LanguageSort: String {
    case speakers, name
}

private struct LanguageToolbox: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openWindow) private var openWindow
    @AppStorage("toolbox.activatedOnly") private var activatedOnly = false
    @AppStorage("toolbox.languageSort") private var sort: LanguageSort = .speakers
    @SceneStorage("toolbox.language") private var selectedISO: String?
    @State private var query = ""
    @State private var matches = LanguageMatches()
    @State private var familySelection: String?

    private struct Key: Equatable {
        var iso: String?
        var activatedOnly: Bool
        var showSystem: Bool
        var generation: Int
        var familyCount: Int
    }

    var body: some View {
        HSplitView {
            languageList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 420)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Language list

    private var languageList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search", text: $query, prompt: Text("Language, autonym or script"))
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $sort) {
                    Text("By Speakers").tag(LanguageSort.speakers)
                    Text("By Name").tag(LanguageSort.name)
                }
                .labelsHidden()
                .fixedSize()
                .help("Order of the language list")
            }
            .padding(10)
            List(languages, selection: $selectedISO) { language in
                languageRow(language).tag(language.iso)
            }
            .overlay {
                if Languages.all.isEmpty {
                    ContentUnavailableView("No Language Data", systemImage: "globe",
                                           description: Text("Languages.json is missing from the app."))
                } else if languages.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private var languages: [Language] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = Languages.all.filter { language in
            needle.isEmpty || ([language.name, language.autonym ?? "", language.iso] + language.scripts)
                .joined(separator: " ").lowercased().contains(needle)
        }
        switch sort {
        case .speakers:
            return filtered.sorted {
                $0.speakers != $1.speakers ? $0.speakers > $1.speakers : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func languageRow(_ language: Language) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.name).lineLimit(1)
                Spacer()
                if language.speakers > 0 {
                    Text(language.speakers.formatted(.number.notation(.compactName)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle(for: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }

    private func subtitle(for language: Language) -> String {
        var parts = [language.autonym, language.scripts.joined(separator: ", ")].compactMap { $0 }.filter { !$0.isEmpty }
        if language.status != .living { parts.append(language.status.rawValue) }
        return parts.joined(separator: " · ")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        let coverage = CharacterCoverage.shared
        if let language = selectedISO.flatMap(Languages.language) {
            let key = Key(
                iso: language.iso, activatedOnly: activatedOnly, showSystem: library.data.showSystemFonts,
                generation: coverage.generation, familyCount: library.families.count
            )
            VStack(spacing: 0) {
                header(language)
                Divider()
                List(selection: $familySelection) {
                    if !matches.full.isEmpty {
                        Section("Fully Supported · \(matches.full.count)") {
                            ForEach(matches.full) { familyRow($0, language) }
                        }
                    }
                    if !matches.base.isEmpty {
                        Section("Base Characters Only · \(matches.base.count)") {
                            ForEach(matches.base) { familyRow($0, language) }
                        }
                    }
                }
                .overlay {
                    if matches.full.isEmpty && matches.base.isEmpty {
                        if coverage.isIndexing && matches.unindexed > 0 {
                            ProgressView()
                        } else {
                            ContentUnavailableView("No Fonts Support \(language.name)", systemImage: "globe",
                                                   description: Text("None of your fonts has every base character of this language."))
                        }
                    }
                }
            }
            .task(id: key) { await match(key, language) }
            .onKeyPress(.return) {
                guard let familySelection, let family = library.family(named: familySelection) else { return .ignored }
                OpensFamily.open(family, in: library, openWindow: openWindow)
                return .handled
            }
        } else {
            ContentUnavailableView("No Language Selected", systemImage: "globe",
                                   description: Text("Pick a language to see which fonts support it."))
        }
    }

    private func header(_ language: Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(language.name).font(.title2.weight(.semibold))
                if let autonym = language.autonym, !autonym.isEmpty {
                    Text(autonym).font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Activated only", isOn: $activatedOnly).toggleStyle(.checkbox)
            }
            Text(facts(for: language))
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Array(language.orthographies.enumerated()), id: \.offset) { _, orthography in
                sample(orthography, showScript: language.orthographies.count > 1)
            }
            Text(countLine(for: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facts(for language: Language) -> String {
        var parts = [language.scripts.joined(separator: ", ")]
        if language.speakers > 0 { parts.append("\(language.speakers.formatted(.number.notation(.compactName))) speakers") }
        if language.status != .living { parts.append(language.status.rawValue) }
        parts.append("\(language.validity) data")
        return parts.joined(separator: " · ")
    }

    /// The characters Hyperglot requires, base on one line and auxiliary on another.
    private func sample(_ orthography: LanguageOrthography, showScript: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LanguageOrthography.spaced(orthography.base + orthography.marks))
                .font(.title3)
                .lineLimit(3)
                .textSelection(.enabled)
            if !orthography.auxiliary.isEmpty {
                Text("Auxiliary: " + LanguageOrthography.spaced(orthography.auxiliary + orthography.auxiliaryMarks))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .help(showScript ? orthography.script : "")
    }

    private func countLine(for language: Language) -> String {
        let total = matches.full.count + matches.base.count
        var line = total == 1 ? "1 font supports \(language.name)" : "\(total.formatted()) fonts support \(language.name)"
        if total > 0 { line += ", \(matches.full.count.formatted()) of them fully" }
        if matches.unindexed > 0 { line += " · \(matches.unindexed.formatted()) not indexed yet" }
        return line
    }

    private func familyRow(_ family: FontFamily, _ language: Language) -> some View {
        FamilyRow(family: family, sample: language.sampleText)
            .modifier(OpensFamily(family: family))
            .tag(family.id)
    }

    private func match(_ key: Key, _ language: Language) async {
        let families = library.families.filter {
            (key.showSystem || $0.status != .system) && (!key.activatedOnly || $0.hasActiveFaces)
        }
        let coverage = CharacterCoverage.shared
        let result = await Task.detached(priority: .userInitiated) {
            coverage.families(supporting: language, in: families)
        }.value
        guard !Task.isCancelled else { return }
        matches = result
    }
}

// MARK: - Shared pieces

/// A family's name and status, with the sample set in the family itself.
private struct FamilyRow: View {
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    let sample: String
    var note: String?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(family.name).lineLimit(1)
                    StatusTag(family: family)
                }
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 230, alignment: .leading)
            FontPreviewText(
                text: sample,
                face: family.face(nearestWeight: Int(preview.weight)).face,
                size: 22, weight: preview.weight, kerning: preview.kerning(atSize: 22)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

/// Double-click opens the family in the main window; the usual font actions are in the context menu.
private struct OpensFamily: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(\.openWindow) private var openWindow
    let family: FontFamily

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onTapGesture(count: 2) { Self.open(family, in: library, openWindow: openWindow) }
            .contextMenu { FontActionsMenu(families: [family]) }
    }

    @MainActor
    static func open(_ family: FontFamily, in library: LibraryStore, openWindow: OpenWindowAction) {
        library.detailFamilyID = family.id
        openWindow(id: "main")
    }
}
