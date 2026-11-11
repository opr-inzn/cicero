import Foundation
import CiceroCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case folders, sets, tags, foundries, classifications, characterSets

    var id: String { rawValue }
    var key: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        // `folders` and `sets` are keys in the user's sidebar data (`SidebarPreferences.order`), so the cases can't follow the titles.
        case .folders: "Locations"
        case .sets: "Folders"
        case .tags: "Tags"
        case .foundries: "Foundries"
        case .classifications: "Classifications"
        case .characterSets: "Coverage"
        }
    }

    var icon: String {
        switch self {
        case .folders: "folder"
        case .sets: "folder"
        case .tags: "tag"
        case .foundries: "building.2"
        case .classifications: "textformat"
        case .characterSets: "character.textbox"
        }
    }
}

struct CompareEntry: Identifiable, Equatable {
    let id = UUID()
    let familyID: String
    var style: FaceID?
    var tint: Int
}

struct SidebarRow: Identifiable, Hashable {
    var key: String
    var title: String
    var icon: String
    var item: SidebarItem
    var badge = 0
    var color: TagColor?

    var id: String { key }

    static let alwaysShown: Set<String> = ["library.all", "library.active", "library.inactive"]

    var canHide: Bool { !Self.alwaysShown.contains(key) }
}

struct VisibleKey: Equatable {
    var fingerprint: Int
    var selection: Set<SidebarItem>
    var search: String
    var tokens: [SearchToken]
    var dataRevision: Int
    var coverageRevision: Int
    var guessRevision: Int
    var similar: String?
    var similarStyle: FaceID?
    var document: DocumentList?
    var measurementRevision: Int
}

struct FontRowsKey: Equatable {
    var visible: VisibleKey
    var order: [KeyPathComparator<FontRow>]
    var columns: [FontListColumn]
    var coverageRevision: Int
}

extension Classification {
    var icon: String {
        switch self {
        case .serif: "textformat"
        case .sansSerif: "textformat.alt"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        case .script: "scribble.variable"
        case .ornamental: "sparkles"
        case .symbol: "star.square.on.square"
        case .unclassified: "questionmark.square.dashed"
        }
    }
}

extension AppModel {
    // MARK: Families

    func family(_ id: String) -> Family? { library.family(id).map(shown) }

    var showsAdobeFontsOnly: Bool {
        selectedItems == [.folder(WatchedFolder.adobeFontsID)] && documentList == nil && similarFamilyID == nil
    }

    func shown(_ family: Family) -> Family {
        guard showsAdobeFontsOnly, !family.isAdobeFonts else { return family }
        return adobeFontsOnly[family.id] ?? family
    }

    var adobeFontsOnly: [String: Family] {
        if let cached = adobeFontsOnlyCache, cached.fingerprint == library.fingerprint { return cached.families }
        var families: [String: Family] = [:]
        for family in library.families where !family.isAdobeFonts && family.folderIDs.contains(WatchedFolder.adobeFontsID) {
            families[family.id] = family.adobeFontsOnly
        }
        adobeFontsOnlyCache = (library.fingerprint, families)
        return families
    }

    var openFamily: Family? { openFamilyID.flatMap(family) }

    var shownSelection: Set<String> {
        guard !selectedIDs.isEmpty else { return [] }
        _ = visibleFamilies
        let shown = visibleCache?.ids ?? []
        return selectedIDs.filter(shown.contains)
    }

    var selectedFamilies: [Family] {
        if let open = openFamily { return [open] }
        return inLibraryOrder(shownSelection)
    }

    func targets(for family: Family) -> [Family] {
        let shown = shownSelection
        guard shown.contains(family.id), shown.count > 1 else { return [family] }
        return inLibraryOrder(shown)
    }

    private func inLibraryOrder(_ ids: Set<String>) -> [Family] {
        ids.compactMap { library.position(of: $0) }.sorted().map { shown(library.families[$0]) }
    }

    var inspectedFamily: Family? {
        if let open = openFamily { return open }
        let shown = shownSelection
        guard shown.count == 1, let id = shown.first else { return nil }
        return family(id)
    }

    func foundryName(of family: Family) -> String? {
        foundryNamer()(family)
    }

    func foundryNamer() -> (Family) -> String? { data.foundryNamer() }

    func features(for family: Family) -> [FeatureSetting] {
        let chosen = familyFeatures[family.id] ?? []
        return chosen + searchFeatures.filter { feature in !chosen.contains { $0.type == feature.type } }
    }

    var searchFeatures: [FeatureSetting] { SearchToken.features(of: searchTokens) }

    func variations(for family: Family, face: FaceID? = nil) -> [String: Double] {
        guard let adjusted = familyAxes[family.id], adjusted.face == face ?? family.regular.id else { return [:] }
        return adjusted.values
    }

    func previewStyle(of family: Family) -> (face: LibraryFace, weight: Double) {
        if openFamilyID == family.id, let id = pageStyleID, let chosen = family.faces.first(where: { $0.id == id }) {
            return (chosen, chosen.face.styleWeight)
        }
        return unchosenStyle(of: family)
    }

    func unchosenStyle(of family: Family) -> (face: LibraryFace, weight: Double) {
        if let style = similarStyle, let source = similarFamilyID.flatMap(library.family), appliedSearch.isEmpty, searchTokens.isEmpty {
            if family.id == source.id { return (style, style.face.styleWeight) }
            return (family.face(for: source.kind(of: style), weight: style.face.styleWeight), style.face.styleWeight)
        }
        return automaticStyle(of: family)
    }

    func automaticStyle(of family: Family) -> (face: LibraryFace, weight: Double) {
        family.previewStyle(for: SearchQuery(appliedSearch), tokens: searchTokens)
    }

    func tokenSuggestions(for typed: String) -> [SearchToken] {
        SearchToken.suggestions(for: typed, besides: searchTokens).map(\.token)
    }

    // MARK: The list

    var visibleFamilies: [Family] {
        let key = visibleKey
        if let cached = visibleCache, cached.key == key { return cached.families }
        #if CICERO_MEASURE
        let families = Measurements.time("visibleFamilies") { computeVisibleFamilies() }
        #else
        let families = computeVisibleFamilies()
        #endif
        visibleCache = (key, families, Set(families.map(\.id)))
        return families
    }

    var visibleCounts: (active: Int, appOnly: [String]) {
        let key = visibleKey
        if let cached = visibleCountsCache, cached.key == key { return (cached.active, cached.appOnly) }
        let families = visibleFamilies
        let active = families.count(where: \.hasActive)
        let appOnly = families.compactMap { if case .appOnly(let app) = $0.state { app } else { nil } }
        visibleCountsCache = (key, active, appOnly)
        return (active, appOnly)
    }

    private var visibleKey: VisibleKey {
        VisibleKey(
            fingerprint: library.fingerprint, selection: selectedItems, search: appliedSearch, tokens: searchTokens,
            dataRevision: dataRevision, coverageRevision: listDependsOnCoverage ? coverageRevision : 0, guessRevision: guessRevision,
            similar: similarFamilyID, similarStyle: similarStyleID, document: documentList, measurementRevision: similarFamilyID == nil ? 0 : measurementRevision
        )
    }

    var listDependsOnCoverage: Bool {
        selectedItems.contains { item in
            switch item {
            case .characterSet: true
            case .smartSet(let id):
                data.smartSets.first { $0.id == id }?.rules.contains { $0.field == .language || $0.field == .characterSet } ?? false
            default: false
            }
        }
    }

    func fontRows(sortedBy order: [KeyPathComparator<FontRow>], coverageColumns: [FontListColumn]) -> (rows: [FontRow], families: [Family]) {
        let key = FontRowsKey(visible: visibleKey, order: order, columns: coverageColumns,
                              coverageRevision: coverageColumns.isEmpty ? 0 : coverageRevision)
        if let cached = fontRowsCache, cached.key == key { return (cached.rows, cached.families) }
        let sources = coverageColumns.compactMap { column in coverageSource(of: column).map { (column, $0) } }
        #if CICERO_MEASURE
        let measuring = Measurements.begin("fontRows")
        defer { measuring.end(detail: "\(visibleFamilies.count) rows") }
        #endif
        let inputs = FontRow.Inputs(self)
        let unsorted = visibleFamilies.map { FontRow($0, coverage: sources, inputs: inputs, model: self) }
        var rows = order.isEmpty ? unsorted : unsorted.sorted(using: order)
        for index in rows.indices { rows[index].position = index }
        let families = rows.map(\.family)
        fontRowsCache = (key, rows, families)
        return (rows, families)
    }

    private func computeVisibleFamilies() -> [Family] {
        let query = SearchQuery(appliedSearch)
        var found = listedFamilies(where: searchMatcher(query, tokens: searchTokens))
        if found.isEmpty, !query.isEmpty { found = listedFamilies(where: searchMatcher(query.anywhereInNames, tokens: searchTokens)) }
        FontLoader.shared.prefetch(found.prefix(Self.readAheadNewList).map(\.regular.face))
        return found
    }

    static let readAheadFirst = 200
    static let readAheadNewList = 60

    private func listedFamilies(where matches: (Family) -> Bool) -> [Family] {
        if let list = documentList {
            return list.families.compactMap { library.family($0) }.filter { data.lists($0) && matches($0) }
        }
        if let id = similarFamilyID {
            guard let family = library.family(id), data.lists(family) else { return [] }
            let kind = similarStyle.map(family.kind(of:))
            return ([family] + similarFamilies(to: family, kind: kind, limit: SimilarFonts.longestList)).filter(matches)
        }
        let tests = (selectedItems.isEmpty ? [.all] : selectedItems).map(filter(for:))
        let data = data, families = library.families
        func keeps(_ family: Family) -> Bool { data.lists(family) && tests.contains { $0(family) } && matches(family) }
        var kept: [Int] = []
        for index in families.indices where keeps(families[index]) { kept.append(index) }
        let listed = kept.count == families.count ? families : kept.map { families[$0] }
        if showsAdobeFontsOnly { return listed.map(shown) }
        return selectedItems == [.recent] ? Family.latestFirst(listed) : listed
    }

    var hasOwnOrder: Bool { similarFamilyID != nil || selectedItems == [.recent] }

    func searchSuggestions(for typed: String) -> [Family] {
        let query = SearchQuery(typed)
        guard !query.isEmpty else { return [] }
        var ranks: [String: Int] = [:]
        let found = listedFamilies { family in
            guard let rank = query.suggestionRank(of: family.name.lowercased()) else { return false }
            ranks[family.id] = rank
            return true
        }
        let sorted = found.sorted { a, b in
            let ranked = (ranks[a.id] ?? 1, ranks[b.id] ?? 1)
            return ranked.0 != ranked.1 ? ranked.0 < ranked.1 : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(8))
    }

    func compareCandidates(for typed: String) -> [Family] {
        let query = SearchQuery(typed)
        let listed = library.families.filter(data.lists)
        guard !query.isEmpty else { return listed }
        var found = listed.filter(searchMatcher(query))
        if found.isEmpty { found = listed.filter(searchMatcher(query.anywhereInNames)) }
        let ranks = found.map { query.suggestionRank(of: $0.name.lowercased()) ?? 2 }
        return (0...2).flatMap { rank in zip(found, ranks).filter { $0.1 == rank }.map(\.0) }
    }

    var familyFilters: FamilyFilters {
        let guess = classificationGuess()
        return FamilyFilters(
            library: library, data: data, classificationGuess: { guess($0)?.classification },
            coverage: CoverageAnswers(
                characterSet: { [unowned self] in self.characterSet($0) },
                missingCount: { [unowned self] in self.missingCount($0, $1) },
                supports: { [unowned self] in self.supports($0, language: $1) }
            )
        )
    }

    private func searchMatcher(_ search: SearchQuery, tokens: [SearchToken] = []) -> (Family) -> Bool {
        familyFilters.searchMatcher(search, tokens: tokens)
    }

    func filter(for item: SidebarItem) -> (Family) -> Bool {
        familyFilters.filter(for: item)
    }

    func matcher(for smartSet: SmartSet) -> (Family) -> Bool {
        familyFilters.matcher(for: smartSet)
    }

    // MARK: Coverage

    func supports(_ family: Family, language id: String) -> Bool? {
        coverage.coverage(of: family.regular.id).map { $0.support(for: id) != nil }
    }

    var characterSets: [CharacterSetDefinition] {
        characterSetCatalog.builtIn + customCharacterSets
    }

    var customCharacterSets: [CharacterSetDefinition] {
        let sets = data.customCharacterSets
        if let cached = customSetsCache, cached.sets == sets { return cached.definitions }
        let definitions = sets.enumerated().map { CharacterSetCatalog.definition(for: $1, level: $0) }
        customSetsCache = (sets, definitions)
        return definitions
    }

    func characterSet(_ id: String) -> CharacterSetDefinition? {
        id.hasPrefix("custom.") ? customCharacterSets.first { $0.id == id } : characterSetCatalog.builtIn.first { $0.id == id }
    }

    func missingCount(_ set: CharacterSetDefinition, _ family: Family) -> Int? {
        characterSetLookup.missingCount(set, face: family.regular.id, revision: coverageRevision) { [coverage] in
            coverage.coverage(of: family.regular.id)?.scalars
        }
    }

    func characterSetName(_ id: String) -> String? {
        id.hasPrefix("custom.") ? data.customCharacterSets.first { $0.setID == id }?.name : characterSetCatalog.definition(id)?.name
    }

    func characterSetSeries(_ id: String) -> CharacterSetSeries? {
        characterSetCatalog.series.first { $0.id == id }
    }

    func coverageSource(of column: FontListColumn) -> CoverageSource? {
        switch column {
        case .series(let id): characterSetSeries(id).map(CoverageSource.series)
        case .characterSet(let id): (customCharacterSets.first { $0.id == id } ?? characterSetCatalog.definition(id)).map(CoverageSource.set)
        default: nil
        }
    }

    func coverageCell(_ column: FontListColumn, of row: FontRow) -> CoverageCell? {
        if let cell = row.coverage[column] { return cell }
        return coverageSource(of: column).flatMap { FontRow.cell($0, for: row.family, model: self) }
    }

    func largestSet(in series: CharacterSetSeries, for family: Family) -> CharacterSetDefinition? {
        characterSetLookup.largest(series, family: family.id, revision: coverageRevision) { set in
            self.missingCount(set, family)
        }
    }
}

final class CharacterSetLookup {
    private struct Key: Hashable {
        var set: String
        var size: Int
        var face: FaceID
    }

    private struct SeriesKey: Hashable {
        var series: String
        var family: String
    }

    private var revision = -1
    private var missing: [Key: Int] = [:]
    private var largest: [SeriesKey: Int] = [:]

    func reset() {
        missing.removeAll()
        largest.removeAll()
    }

    private func sync(_ revision: Int) {
        guard revision != self.revision else { return }
        self.revision = revision
        reset()
    }

    func missingCount(_ set: CharacterSetDefinition, face: FaceID, revision: Int, scalars: () -> ScalarRanges?) -> Int? {
        sync(revision)
        let key = Key(set: set.id, size: set.scalars.count, face: face)
        if let known = missing[key] { return known }
        guard let ranges = scalars() else { return nil }
        let count = ranges.missingCount(sorted: set.scalars)
        missing[key] = count
        return count
    }

    func largest(_ series: CharacterSetSeries, family: String, revision: Int, missing: (CharacterSetDefinition) -> Int?) -> CharacterSetDefinition? {
        sync(revision)
        let key = SeriesKey(series: series.id, family: family)
        if let level = largest[key] { return level >= 0 ? series.sets[level] : nil }
        var level = -1
        for (index, set) in series.sets.enumerated().reversed() {
            guard let count = missing(set) else { return nil }
            if count == 0 {
                level = index
                break
            }
        }
        largest[key] = level
        return level >= 0 ? series.sets[level] : nil
    }
}
