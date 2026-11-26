import CiceroCore
import SwiftUI

struct LanguagesRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var loaded: Loaded<Prepared>?
    @State private var showsAll = false

    private struct Prepared {
        let coverage: FaceCoverage
        let languages: [Language]
    }

    private static let preferred: [String] = Locale.preferredLanguages.compactMap {
        Locale(identifier: $0).language.languageCode?.identifier(.alpha3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Languages").font(.caption).foregroundStyle(.secondary)
            if let prepared = loaded?.value {
                let languages = prepared.languages
                if languages.isEmpty {
                    Text("None").font(.callout)
                } else {
                    Text(summary(languages)).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button("Show All") { showsAll = true }
                        .controlSize(.small)
                        .padding(.top, 2)
                        .popover(isPresented: $showsAll, arrowEdge: .leading) {
                            LanguageList(languages: languages, coverage: prepared.coverage)
                        }
                }
            } else {
                SamplePlaceholder(size: 13).frame(width: 180)
            }
        }
        .loading($loaded, for: FileFace(face), cached: { [face] in
            model.coverage.coverage(of: face.id).map(prepare)
        }) { [face] in
            async let coverage = model.coverage.coverage(computing: face)
            await model.languages.load()
            return prepare(await coverage)
        }
    }

    private func prepare(_ coverage: FaceCoverage) -> Prepared {
        Prepared(coverage: coverage, languages: ranked(coverage.supportedLanguages.compactMap(model.languages.language)))
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
        let sample = languages.prefix(5).map(\.name).listed()
        return languages.count <= 5 ? sample : "\(languages.count.plain) languages, including \(sample)"
    }
}

private struct LanguageList: View {
    @Environment(AppModel.self) private var model
    let languages: [Language]
    let coverage: FaceCoverage
    @State private var query = ""
    @State private var showsMissing: String?
    @State private var cache = SearchCache()

    private struct Results {
        var scripts: [(name: String, languages: [Language])]
        var unsupported: [(language: Language, missingCount: Int)]
    }

    private final class SearchCache {
        var query: String?
        var results: Results?
        var missingCounts: [String: Int] = [:]
        var unsupportedBySpeakers: [Language]?
    }

    var body: some View {
        let results = searchResults()
        List {
            ForEach(results.scripts, id: \.name) { script in
                Section("\(script.name) (\(script.languages.count.plain))") {
                    ForEach(script.languages) { language in
                        HStack {
                            Text(language.name)
                            if let autonym = language.autonym, autonym != language.name {
                                Text(autonym).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if coverage.support(for: language.id) == .full {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                                    .accessibilityLabel("Fully supported")
                                    .help("Fully supported, including less common characters")
                            } else {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                                    .accessibilityLabel("Partially supported")
                                    .help("Supported, without some less common characters")
                            }
                        }
                    }
                }
            }
            if !results.unsupported.isEmpty {
                Section("Not Supported (\(results.unsupported.count.plain))") {
                    ForEach(results.unsupported, id: \.language.id) { entry in
                        unsupportedRow(entry.language, missingCount: entry.missingCount)
                    }
                }
            }
        }
        .listStyle(.plain)
        .popoverListInsets(top: 0, bottom: 10)
        .topBar {
            TextField("Search", text: $query, prompt: Text("Search languages"))
                .textFieldStyle(.roundedBorder)
                .noAutoFill()
                .padding([.horizontal, .top], 10)
                .padding(.bottom, 6)
        }
        .frame(width: 320, height: 420)
    }

    private func searchResults() -> Results {
        if cache.query == query, let results = cache.results { return results }
        let shown = query.isEmpty ? languages : languages.filter(matches)
        let grouped = Dictionary(grouping: shown) { $0.scripts.first ?? "Other" }
        let scripts = grouped.keys.sorted { (grouped[$0]?.count ?? 0) > (grouped[$1]?.count ?? 0) }.map {
            (name: $0, languages: grouped[$0] ?? [])
        }
        let unsupported: [(language: Language, missingCount: Int)]
        if query.isEmpty {
            unsupported = []
        } else {
            let candidates = cache.unsupportedBySpeakers ?? {
                let list = model.languages.languages.filter { coverage.support(for: $0.id) == nil }.sorted { $0.speakers > $1.speakers }
                cache.unsupportedBySpeakers = list
                return list
            }()
            unsupported = candidates.filter(matches).map { language in
                let missing = cache.missingCounts[language.id] ?? {
                    let count = model.languages.missingCount(language.id, in: coverage.scalars)
                    cache.missingCounts[language.id] = count
                    return count
                }()
                return (language, missing)
            }
        }
        let results = Results(scripts: scripts, unsupported: unsupported)
        cache.query = query
        cache.results = results
        return results
    }

    private func matches(_ language: Language) -> Bool {
        language.name.localizedCaseInsensitiveContains(query) || (language.autonym?.localizedCaseInsensitiveContains(query) ?? false)
            || language.scripts.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func unsupportedRow(_ language: Language, missingCount: Int) -> some View {
        let shows = Binding(get: { showsMissing == language.id }, set: { if !$0 { showsMissing = nil } })
        return HStack {
            Text(language.name)
            if let autonym = language.autonym, autonym != language.name {
                Text(autonym).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(missingCount.plain) missing").foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .onTapGesture { showsMissing = language.id }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showsMissing = language.id }
        .help("Show the characters the font needs for \(language.name)")
        .popover(isPresented: shows, arrowEdge: .trailing) {
            MissingCharacterList(missing: model.languages.missing(language.id, in: coverage.scalars))
        }
    }
}

struct CharacterSetsRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var loaded: Loaded<Prepared>?
    @State private var showsMissing: CharacterSetDefinition?

    private struct Key: Hashable {
        let face: FileFace
        let customSets: [CharacterSetDefinition]
    }

    private struct Prepared {
        let ranges: ScalarRanges
        let supported: [CharacterSetDefinition]
        let nextLatin: (name: String, missing: Int)?
        let incomplete: [(name: String, sets: [(set: CharacterSetDefinition, missing: Int)])]
    }

    var body: some View {
        let key = Key(face: FileFace(face), customSets: model.customCharacterSets)
        VStack(alignment: .leading, spacing: 2) {
            Text("Coverage").font(.caption).foregroundStyle(.secondary)
            if let prepared = loaded?.value {
                let has = prepared.supported
                Text(has.isEmpty ? "None" : has.map(\.name).listed())
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = prepared.nextLatin {
                    Text(next.missing == 1 ? "\(next.name) needs 1 more character" : "\(next.name) needs \(next.missing.plain) more characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !prepared.incomplete.isEmpty {
                    Menu {
                        ForEach(prepared.incomplete, id: \.name) { group in
                            Section(group.name) {
                                ForEach(group.sets, id: \.set.id) { entry in
                                    Button("\(entry.set.name) (\(entry.missing.plain) missing)") { showsMissing = entry.set }
                                }
                            }
                        }
                    } label: {
                        // One text, as a menu's label puts an image of its own first.
                        Text("Show Missing \(Image(systemName: "chevron.down"))")
                            .accessibilityLabel("Show Missing")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .controlSize(.small)
                    .fixedSize()
                    .padding(.top, 2)
                    .popover(item: $showsMissing, arrowEdge: .leading) { set in
                        MissingCharacterList(missing: prepared.ranges.missing(sorted: set.scalars))
                    }
                }
            } else {
                SamplePlaceholder(size: 13).frame(width: 180)
            }
        }
        .loading($loaded, for: key, cached: { [face] in
            model.coverage.coverage(of: face.id).map { prepare($0.scalars) }
        }) { [face] in
            prepare(await model.coverage.coverage(computing: face).scalars)
        }
    }

    private func prepare(_ ranges: ScalarRanges) -> Prepared {
        let has = supported(by: ranges)
        let next = nextLatin(after: has).map { (name: $0.name, missing: ranges.missingCount(sorted: $0.scalars)) }
        return Prepared(ranges: ranges, supported: has, nextLatin: next, incomplete: incompleteSets(in: ranges))
    }

    private func supported(by ranges: ScalarRanges) -> [CharacterSetDefinition] {
        var best: [String: CharacterSetDefinition] = [:]
        var order: [String] = []
        let seriesOf = Dictionary(model.characterSetCatalog.series.flatMap { series in series.sets.map { ($0.id, series.id) } }) { first, _ in first }
        for set in model.characterSets where set.groupID != Self.unicodeGroupID && ranges.missingCount(sorted: set.scalars) == 0 {
            let series = seriesOf[set.id] ?? set.id
            if best[series] == nil { order.append(series) }
            best[series] = set
        }
        return order.compactMap { best[$0] }
    }

    static let unicodeGroupID = "unicode"

    private func incompleteSets(in ranges: ScalarRanges) -> [(name: String, sets: [(set: CharacterSetDefinition, missing: Int)])] {
        let groups = model.characterSetCatalog.groups.filter { $0.id != Self.unicodeGroupID }.map { ($0.name, $0.sets) }
            + [("Your Coverage Sets", model.customCharacterSets)]
        return groups.compactMap { name, sets in
            let incomplete = sets.compactMap { set in
                let missing = ranges.missingCount(sorted: set.scalars)
                return missing > 0 ? (set: set, missing: missing) : nil
            }
            return incomplete.isEmpty ? nil : (name: name, sets: incomplete)
        }
    }

    private func nextLatin(after has: [CharacterSetDefinition]) -> CharacterSetDefinition? {
        guard let series = model.characterSetCatalog.groups.first(where: { $0.id == CharacterSetCatalog.latinSeriesID })?.sets else { return nil }
        let level = has.first { $0.groupID == CharacterSetCatalog.latinSeriesID }?.level ?? -1
        return series.first { $0.level == level + 1 }
    }
}

private struct MissingCharacterList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let missing: [UInt32]

    var body: some View {
        List(missing, id: \.self) { scalar in
            HStack(spacing: 8) {
                Text(Self.drawn(scalar))
                    .font(.system(size: 18))
                    .frame(width: 30, alignment: .leading)
                Text(GlyphSection.shownName(of: scalar) ?? "Unnamed")
                    .textSelection(.enabled)
                Spacer()
                Text(CharacterCodes.unicode(scalar))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .popoverListInsets(top: 2, bottom: 14)
        .bottomBar {
            // StillPushButtonStyle on the list's background, as the default button's fill is see-through and the rows showed through its label.
            Button(missing.count == 1 ? "Copy Character" : "Copy Characters", systemImage: "doc.on.doc", action: copy)
                .buttonStyle(StillPushButtonStyle())
                .background(Self.background, in: .rect(cornerRadius: 6))
                .help(missing.count == 1 ? "Copy the missing character" : "Copy the \(missing.count.plain) missing characters, separated by spaces")
                .padding(.bottom, Self.barBottom)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(gradient: Self.fade, startPoint: .top, endPoint: .bottom)
                        .padding(.top, -Self.fadeAbove)
                        .allowsHitTesting(false)
                }
        }
        .frame(width: 340, height: min(420, CGFloat(missing.count) * 30 + 2 + 14 + Self.buttonHeight + Self.barBottom))
    }

    private static let background = Color(nsColor: .controlBackgroundColor)
    private static let buttonHeight: CGFloat = 26
    private static let barBottom: CGFloat = 12
    private static let fadeAbove: CGFloat = 15
    private static let fadeIntoButton: CGFloat = 10
    private static let fadeAtEdge = 0.5
    private static let fadeUnder = 0.15
    private static let fade: Gradient = {
        let height = fadeAbove + buttonHeight + barBottom
        let edge = fadeAbove / height
        let under = (fadeAbove + fadeIntoButton) / height
        func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let up = (0...10).map { step in
            let t = Double(step) / 10
            return Gradient.Stop(color: background.opacity(fadeAtEdge * eased(t)), location: edge * t)
        }
        let down = (1...6).map { step in
            let t = Double(step) / 6
            return Gradient.Stop(color: background.opacity(fadeAtEdge + (fadeUnder - fadeAtEdge) * eased(t)), location: edge + (under - edge) * t)
        }
        return Gradient(stops: up + down + [Gradient.Stop(color: background.opacity(fadeUnder), location: 1)])
    }()

    private static func drawn(_ scalar: UInt32) -> String {
        let text = GlyphsSection.text(scalar)
        switch Unicode.Scalar(scalar)?.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .spacingMark: return "\u{25CC}" + text
        default: return text
        }
    }

    private func copy() {
        // Spaced, so a combining mark doesn't stack on the letter before it.
        GlyphsSection.copy(missing.map(GlyphsSection.text).joined(separator: " "))
        dismiss()
        model.showToast(missing.count == 1 ? "1 character copied to clipboard" : "\(missing.count.plain) characters copied to clipboard")
    }
}

struct UnicodeBlocksRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var loaded: Loaded<(ranges: ScalarRanges, blocks: [BlockCoverage])>?
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unicode Blocks").font(.caption).foregroundStyle(.secondary)
            if let (ranges, coverage) = loaded?.value {
                let complete = coverage.filter(\.isComplete).map(\.block.name)
                let partial = coverage.count { $0.has > 0 && !$0.isComplete }
                Text(complete.isEmpty ? "None complete" : "Complete: " + complete.listed())
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if partial > 0 {
                    let word = partial == 1 ? "block" : "blocks"
                    Text(complete.isEmpty ? "\(partial.plain) \(word) partly covered" : "\(partial.plain) more \(word) partly covered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Show All") { showsAll = true }
                    .controlSize(.small)
                    .padding(.top, 2)
                    .popover(isPresented: $showsAll, arrowEdge: .leading) { BlockList(ranges: ranges, coverage: coverage) }
            } else {
                SamplePlaceholder(size: 13).frame(width: 180)
            }
        }
        .loading($loaded, for: FileFace(face), cached: { [face] in model.coverage.coverage(of: face.id).map { ($0.scalars, blocks(covered: $0.scalars)) } }) { [face] in
            let ranges = await model.coverage.coverage(computing: face).scalars
            return (ranges, blocks(covered: ranges))
        }
    }

    private func blocks(covered ranges: ScalarRanges) -> [BlockCoverage] {
        let blocks = model.characterSetCatalog.groups.first { $0.id == CharacterSetsRow.unicodeGroupID }?.sets ?? []
        return blocks.map { BlockCoverage(block: $0, has: $0.scalars.count - ranges.missingCount(sorted: $0.scalars)) }
    }
}

private struct BlockCoverage {
    let block: CharacterSetDefinition
    let has: Int
    var isComplete: Bool { has == block.scalars.count }
}

private struct BlockList: View {
    let ranges: ScalarRanges
    let coverage: [BlockCoverage]
    @State private var showsMissing: CharacterSetDefinition?

    var body: some View {
        List(coverage, id: \.block.id) { entry in
            Button { if !entry.isComplete { showsMissing = entry.block } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.block.name)
                        Spacer()
                        Text("\(entry.has.plain) of \(entry.block.scalars.count.plain)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(entry.has), total: Double(max(entry.block.scalars.count, 1)))
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
                .contentShape(.rect)
            }
            .buttonStyle(StillButtonStyle())
            .help(entry.isComplete ? "" : "Show the missing characters")
            .popover(item: Binding(get: { showsMissing?.id == entry.block.id ? showsMissing : nil }, set: { showsMissing = $0 }), arrowEdge: .leading) { block in
                MissingCharacterList(missing: ranges.missing(sorted: block.scalars))
            }
        }
        .listStyle(.plain)
        .popoverListInsets(top: 3)
        .frame(width: 320, height: 420)
    }
}

private extension View {
    func popoverListInsets(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        safeAreaPadding(.top, top).safeAreaPadding(.bottom, bottom)
    }
}
