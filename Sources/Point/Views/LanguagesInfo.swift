import SwiftUI

/// The Info pane's Languages row: a count and a few names, with a popover listing every language
/// the face supports according to Hyperglot, grouped by script.
struct LanguagesRow: View {
    let face: FontFace
    @State private var coverage: FaceCoverage?
    @State private var showingAll = false

    /// The user's own languages lead the summary; the rest follow by number of speakers.
    private static let preferredISO: [String] = Locale.preferredLanguages.compactMap {
        Locale(identifier: $0).language.languageCode?.identifier(.alpha3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Languages").font(.caption).foregroundStyle(.secondary)
            if Languages.all.isEmpty {
                Text("No language data").font(.callout).foregroundStyle(.secondary)
            } else if let coverage {
                let languages = Self.ranked(coverage.supportedLanguages)
                if languages.isEmpty {
                    Text("None").font(.callout)
                } else {
                    Text(Self.summary(of: languages))
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show All") { showingAll = true }
                        .controlSize(.small)
                        .padding(.top, 2)
                        .popover(isPresented: $showingAll, arrowEdge: .leading) {
                            LanguageListPopover(coverage: coverage)
                        }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: face.id) {
            coverage = nil
            let result = await CharacterCoverage.shared.coverage(computingFor: face)
            if !Task.isCancelled { coverage = result }
        }
    }

    static func ranked(_ languages: [Language]) -> [Language] {
        languages.sorted { a, b in
            let ra = preferredISO.firstIndex(of: a.iso) ?? .max
            let rb = preferredISO.firstIndex(of: b.iso) ?? .max
            if ra != rb { return ra < rb }
            if a.speakers != b.speakers { return a.speakers > b.speakers }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// "212 languages, including English, German, French, Spanish and Italian".
    static func summary(of languages: [Language], sampleCount: Int = 5) -> String {
        let sample = ListFormatter.localizedString(byJoining: languages.prefix(sampleCount).map(\.name))
        return languages.count <= sampleCount ? sample : "\(languages.count) languages, including \(sample)"
    }
}

private struct LanguageListPopover: View {
    let coverage: FaceCoverage
    @State private var query = ""

    private struct ScriptGroup: Identifiable {
        var script: String
        var languages: [Language]
        var id: String { script }
    }

    var body: some View {
        let groups = groups()
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Search", text: $query, prompt: Text("Name, autonym or script"))
                    .textFieldStyle(.roundedBorder)
                Text(header)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            List {
                ForEach(groups) { group in
                    Section("\(group.script) · \(group.languages.count)") {
                        ForEach(group.languages) { row($0) }
                    }
                }
            }
            .overlay {
                if groups.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
        .frame(width: 320, height: 460)
    }

    private var header: String {
        let count = coverage.supported.count
        let full = coverage.full.count
        return "\(count == 1 ? "1 language" : "\(count) languages") · \(full) with auxiliary characters too"
    }

    private func row(_ language: Language) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(language.name)
                Text([language.autonym, language.status == .living ? nil : language.status.rawValue].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if coverage.support(for: language) == .full {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Fully supported: auxiliary characters too")
            }
        }
    }

    /// Languages under each script whose orthography the face covers, so a language written in two
    /// scripts only shows up under the ones it is actually supported in.
    private func groups() -> [ScriptGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var byScript: [String: [Language]] = [:]
        for language in coverage.supportedLanguages {
            if !needle.isEmpty {
                let haystack = ([language.name, language.autonym ?? "", language.iso] + language.scripts).joined(separator: " ").lowercased()
                guard haystack.contains(needle) else { continue }
            }
            for orthography in language.orthographies where coverage.scalars.containsAll(orthography.baseScalars) {
                if byScript[orthography.script]?.last?.iso != language.iso {
                    byScript[orthography.script, default: []].append(language)
                }
            }
        }
        return byScript.keys.sorted().map { script in
            ScriptGroup(script: script, languages: byScript[script]!.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
