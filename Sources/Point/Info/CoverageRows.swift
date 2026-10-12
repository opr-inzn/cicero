import PointCore
import SwiftUI

/// "213 languages, including English, German, …" with every language in a popover.
struct LanguagesRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var coverage: FaceCoverage?
    @State private var showsAll = false

    /// The user's languages lead; then by number of speakers.
    private static let preferred: [String] = Locale.preferredLanguages.compactMap {
        Locale(identifier: $0).language.languageCode?.identifier(.alpha3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Languages").font(.caption).foregroundStyle(.secondary)
            if let coverage {
                let languages = ranked(coverage.supportedLanguages.compactMap(model.languages.language))
                if languages.isEmpty {
                    Text("None").font(.callout)
                } else {
                    Text(summary(languages)).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button("Show All") { showsAll = true }
                        .controlSize(.small)
                        .padding(.top, 2)
                        .popover(isPresented: $showsAll, arrowEdge: .leading) {
                            LanguageList(languages: languages, coverage: coverage)
                        }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: face.id) {
            coverage = nil
            coverage = await model.coverage.coverage(computing: face)
        }
    }

    private func ranked(_ languages: [Language]) -> [Language] {
        languages.sorted { a, b in
            let ra = Self.preferred.firstIndex(of: a.id) ?? .max
            let rb = Self.preferred.firstIndex(of: b.id) ?? .max
            if ra != rb { return ra < rb }
            if a.speakers != b.speakers { return a.speakers > b.speakers }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func summary(_ languages: [Language]) -> String {
        let sample = ListFormatter.localizedString(byJoining: languages.prefix(5).map(\.name))
        return languages.count <= 5 ? sample : "\(languages.count) languages, including \(sample)"
    }
}

private struct LanguageList: View {
    let languages: [Language]
    let coverage: FaceCoverage
    @State private var query = ""

    var body: some View {
        let shown = query.isEmpty ? languages : languages.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.autonym?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.scripts.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let scripts = Dictionary(grouping: shown) { $0.scripts.first ?? "Other" }
        VStack(spacing: 8) {
            TextField("Search", text: $query, prompt: Text("Search languages"))
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(scripts.keys.sorted { (scripts[$0]?.count ?? 0) > (scripts[$1]?.count ?? 0) }, id: \.self) { script in
                    Section("\(script) (\(scripts[script]?.count ?? 0))") {
                        ForEach(scripts[script] ?? []) { language in
                            HStack {
                                Text(language.name)
                                if let autonym = language.autonym, autonym != language.name {
                                    Text(autonym).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if coverage.support(for: language.id) == .full {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary).help("Fully supported, including less common characters")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding(10)
        .frame(width: 320, height: 420)
    }
}

/// The largest set of each series the face has, and how far it is from the next Latin size.
struct CharacterSetsRow: View {
    @Environment(AppModel.self) private var model
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
                if let next = nextLatin(after: has, ranges: ranges) {
                    Text(next).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: face.id) {
            ranges = nil
            ranges = await model.coverage.coverage(computing: face).scalars
        }
    }

    /// One set per series (Google's grouped by script); custom sets each count on their own.
    private func supported(by ranges: ScalarRanges) -> [CharacterSetDefinition] {
        var best: [String: CharacterSetDefinition] = [:]
        var order: [String] = []
        let seriesIDs = Set(model.characterSetCatalog.groups.filter(\.isSeries).map(\.id))
        for set in model.characterSets where set.groupID != Self.unicodeGroupID && ranges.missingCount(sorted: set.scalars) == 0 {
            let series = set.isCustom ? set.id : seriesIDs.contains(set.groupID) ? set.groupID : String(set.id.split(separator: "-").dropLast().joined(separator: "-"))
            if best[series] == nil { order.append(series) }
            best[series] = set
        }
        return order.compactMap { best[$0] }
    }

    static let unicodeGroupID = "unicode"

    private func nextLatin(after has: [CharacterSetDefinition], ranges: ScalarRanges) -> String? {
        guard let series = model.characterSetCatalog.groups.first(where: { $0.id == CharacterSetCatalog.latinSeriesID })?.sets else { return nil }
        let level = has.first { $0.groupID == CharacterSetCatalog.latinSeriesID }?.level ?? -1
        guard let next = series.first(where: { $0.level == level + 1 }) else { return nil }
        let missing = ranges.missingCount(sorted: next.scalars)
        return missing == 1 ? "\(next.name) needs 1 more character" : "\(next.name) needs \(missing.formatted()) more characters"
    }
}

/// Which Unicode blocks the face covers completely, with every block's coverage in a popover.
struct UnicodeBlocksRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var coverage: [(block: CharacterSetDefinition, has: Int)]?
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unicode Blocks").font(.caption).foregroundStyle(.secondary)
            if let coverage {
                let complete = coverage.filter { $0.has == $0.block.scalars.count }.map(\.block.name)
                let partial = coverage.count { $0.has > 0 && $0.has < $0.block.scalars.count }
                Text(complete.isEmpty ? "None complete" : "Complete: " + ListFormatter.localizedString(byJoining: complete))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if partial > 0 {
                    Text(partial == 1 ? "1 more block partly covered" : "\(partial) more blocks partly covered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Show All") { showsAll = true }
                    .controlSize(.small)
                    .padding(.top, 2)
                    .popover(isPresented: $showsAll, arrowEdge: .leading) { list(coverage) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: face.id) {
            coverage = nil
            let ranges = await model.coverage.coverage(computing: face).scalars
            let blocks = model.characterSetCatalog.groups.first { $0.id == CharacterSetsRow.unicodeGroupID }?.sets ?? []
            coverage = blocks.map { ($0, $0.scalars.count - ranges.missingCount(sorted: $0.scalars)) }
        }
    }

    private func list(_ coverage: [(block: CharacterSetDefinition, has: Int)]) -> some View {
        List(coverage, id: \.block.id) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.block.name)
                    Spacer()
                    Text("\(entry.has) of \(entry.block.scalars.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(entry.has), total: Double(max(entry.block.scalars.count, 1)))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
        }
        .listStyle(.plain)
        .frame(width: 320, height: 420)
    }
}
