import CiceroCore
import SwiftUI

struct LanguagesRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var loaded: Loaded<FaceCoverage>?
    @State private var showsAll = false

    private static let preferred: [String] = Locale.preferredLanguages.compactMap {
        Locale(identifier: $0).language.languageCode?.identifier(.alpha3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Languages").font(.caption).foregroundStyle(.secondary)
            if let coverage = loaded?.value {
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
        .loading($loaded, for: FileFace(face), cached: { [face] in model.coverage.coverage(of: face.id) }) { [face] in
            await model.coverage.coverage(computing: face)
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
        let sample = languages.prefix(5).map(\.name).listed()
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
        List {
            ForEach(scripts.keys.sorted { (scripts[$0]?.count ?? 0) > (scripts[$1]?.count ?? 0) }, id: \.self) { script in
                Section("\(script) (\((scripts[script]?.count ?? 0).plain))") {
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
        .topBar {
            TextField("Search", text: $query, prompt: Text("Search languages"))
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 10)
                .padding(.bottom, 6)
        }
        .frame(width: 320, height: 420)
    }
}

struct CharacterSetsRow: View {
    @Environment(AppModel.self) private var model
    let face: FontFace
    @State private var loaded: Loaded<ScalarRanges>?
    @State private var showsMissing: CharacterSetDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Coverage").font(.caption).foregroundStyle(.secondary)
            if let ranges = loaded?.value {
                let has = supported(by: ranges)
                Text(has.isEmpty ? "None" : has.map(\.name).listed())
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = nextLatin(after: has) {
                    let missing = ranges.missingCount(sorted: next.scalars)
                    Text(missing == 1 ? "\(next.name) needs 1 more character" : "\(next.name) needs \(missing.plain) more characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let incomplete = incompleteSets(in: ranges)
                if !incomplete.isEmpty {
                    Menu("Show Missing") {
                        ForEach(incomplete, id: \.name) { group in
                            Section(group.name) {
                                ForEach(group.sets, id: \.set.id) { entry in
                                    Button("\(entry.set.name) — \(entry.missing.plain) missing") { showsMissing = entry.set }
                                }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .controlSize(.small)
                    .fixedSize()
                    .padding(.top, 2)
                    .popover(item: $showsMissing, arrowEdge: .leading) { set in
                        MissingCharacterList(missing: ranges.missing(sorted: set.scalars))
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .loading($loaded, for: FileFace(face), cached: { [face] in model.coverage.coverage(of: face.id)?.scalars }) { [face] in
            await model.coverage.coverage(computing: face).scalars
        }
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
        .popoverListInsets(top: 4, bottom: 14)
        .bottomBar {
            // StillPushButtonStyle on the list's background, as the default button's fill is see-through and the rows showed through its label.
            Button("Copy Characters", systemImage: "doc.on.doc", action: copy)
                .buttonStyle(StillPushButtonStyle())
                .background(Self.background, in: .rect(cornerRadius: 6))
                .help("Copies the \(missing.count == 1 ? "character" : "\(missing.count.plain) characters"), with a space between each")
                .padding(.bottom, Self.barBottom)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(gradient: Self.fade, startPoint: .top, endPoint: .bottom)
                        .padding(.top, -Self.fadeAbove)
                        .allowsHitTesting(false)
                }
        }
        .frame(width: 340, height: min(420, CGFloat(missing.count) * 30 + 4 + 14 + Self.buttonHeight + Self.barBottom))
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
    @State private var loaded: Loaded<[(block: CharacterSetDefinition, has: Int)]>?
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unicode Blocks").font(.caption).foregroundStyle(.secondary)
            if let coverage = loaded?.value {
                let complete = coverage.filter { $0.has == $0.block.scalars.count }.map(\.block.name)
                let partial = coverage.count { $0.has > 0 && $0.has < $0.block.scalars.count }
                Text(complete.isEmpty ? "None complete" : "Complete: " + complete.listed())
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if partial > 0 {
                    Text(partial == 1 ? "1 more block partly covered" : "\(partial.plain) more blocks partly covered")
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
        .loading($loaded, for: FileFace(face), cached: { [face] in model.coverage.coverage(of: face.id).map { blocks(covered: $0.scalars) } }) { [face] in
            let ranges = await model.coverage.coverage(computing: face).scalars
            return blocks(covered: ranges)
        }
    }

    private func blocks(covered ranges: ScalarRanges) -> [(block: CharacterSetDefinition, has: Int)] {
        let blocks = model.characterSetCatalog.groups.first { $0.id == CharacterSetsRow.unicodeGroupID }?.sets ?? []
        return blocks.map { ($0, $0.scalars.count - ranges.missingCount(sorted: $0.scalars)) }
    }

    private func list(_ coverage: [(block: CharacterSetDefinition, has: Int)]) -> some View {
        List(coverage, id: \.block.id) { entry in
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
        }
        .listStyle(.plain)
        .popoverListInsets()
        .frame(width: 320, height: 420)
    }
}

private extension View {
    func popoverListInsets(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        safeAreaPadding(.top, top).safeAreaPadding(.bottom, bottom)
    }
}
