import Foundation
import CiceroCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case folders, sets, tags, foundries, classifications, characterSets

    var id: String { rawValue }
    var key: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        // `folders` and `sets` are keys in the user's sidebar data (`SidebarPreferences.order`), so the cases can't follow
        // the titles.
        case .folders: "Locations"
        case .sets: "Folders"
        case .tags: "Tags"
        case .foundries: "Foundries"
        case .classifications: "Classifications"
        // As in Settings: which fonts have every character of a set.
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

/// A family in Compare, in a style and a colour.
struct CompareEntry: Identifiable, Equatable {
    let id = UUID()
    let familyID: String
    /// nil: the one nearest the preview weight.
    var style: FaceID?
    /// Its place among the tints, the first free one at first or one chosen, kept while it stays, so moving or
    /// removing the others doesn't change its colour.
    var tint: Int
}

struct SidebarRow: Identifiable, Hashable {
    /// Visibility key, see `SidebarPreferences.hidden`.
    var key: String
    var title: String
    var icon: String
    var item: SidebarItem
    var badge = 0
    /// A tag's colour, drawn as a dot instead of the icon; nil for one without and every other row.
    var color: TagColor?

    var id: String { key }

    /// All Fonts, Active and Inactive: the library itself, always in the sidebar.
    static let alwaysShown: Set<String> = ["library.all", "library.active", "library.inactive"]

    /// Whether the row can be hidden from the sidebar: every row but All Fonts, Active and Inactive.
    var canHide: Bool { !Self.alwaysShown.contains(key) }
}

/// What a cached `visibleFamilies` was computed from.
struct VisibleKey: Equatable {
    var fingerprint: Int
    var selection: Set<SidebarItem>
    var search: String
    var tokens: [SearchToken]
    var dataRevision: Int
    var coverageRevision: Int
    var guessRevision: Int
    var similar: String?
    var document: DocumentList?
    /// 0 unless the browser shows similar fonts, so measurements arriving don't make other lists again.
    var measurementRevision: Int
}

/// What the cached rows of the font list were made from.
struct FontRowsKey: Equatable {
    var visible: VisibleKey
    var order: [KeyPathComparator<FontRow>]
    var columns: [FontListColumn]
    /// Coverage as it was, for rows sorted by a character set column; 0 otherwise.
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

    func family(_ id: String) -> Family? { library.family(id) }

    var openFamily: Family? { openFamilyID.flatMap(family) }

    /// The selection in the browser, or the open family on a font page.
    var selectedFamilies: [Family] {
        if let open = openFamily { return [open] }
        return inLibraryOrder(selectedIDs)
    }

    /// Right-click targets: the whole selection when the clicked family is part of it.
    func targets(for family: Family) -> [Family] {
        guard selectedIDs.contains(family.id), selectedIDs.count > 1 else { return [family] }
        return inLibraryOrder(selectedIDs)
    }

    /// The library's families with these IDs, in its order. Found by its index, not by a pass over every family,
    /// which took about 30 ms at 20,000 families each time the menus asked for the selection.
    private func inLibraryOrder(_ ids: Set<String>) -> [Family] {
        ids.compactMap { library.position(of: $0) }.sorted().map { library.families[$0] }
    }

    /// The family the Info panel describes.
    var inspectedFamily: Family? {
        if let open = openFamily { return open }
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return family(id)
    }

    func foundryName(of family: Family) -> String? {
        foundryNamer()(family)
    }

    /// `foundryName(of:)` for many families: the user's names are read once, not for every family.
    func foundryNamer() -> (Family) -> String? { data.foundryNamer() }

    /// The OpenType features chosen for the family in the Info panel, and those for the figures the search's tokens ask
    /// for where the panel doesn't set the same (see `searchFeatures`).
    func features(for family: Family) -> [FeatureSetting] {
        let chosen = familyFeatures[family.id] ?? []
        return chosen + searchFeatures.filter { feature in !chosen.contains { $0.type == feature.type } }
    }

    /// The features the browser's previews turn on for the figures the search's tokens ask for.
    var searchFeatures: [FeatureSetting] { SearchToken.features(of: searchTokens) }

    /// Where the Info panel put the family's axes, by tag, for the style that stands for it unless another is given;
    /// none for a style they weren't moved on.
    func variations(for family: Family, face: FaceID? = nil) -> [String: Double] {
        guard let adjusted = familyAxes[family.id], adjusted.face == face ?? family.regular.id else { return [:] }
        return adjusted.values
    }

    /// The style the family's previews show, and its weight: the one chosen on its open font page, else the one the
    /// search's tokens and words name, as "italic" names the italics (see `Family.previewStyle(for:tokens:weight:)`),
    /// else the one for the preview weight, at that weight.
    func previewStyle(of family: Family, weight: Double) -> (face: LibraryFace, weight: Double) {
        if openFamilyID == family.id, let id = pageStyleID, let chosen = family.faces.first(where: { $0.id == id }) {
            return (chosen, chosen.face.styleWeight)
        }
        return automaticStyle(of: family, weight: weight)
    }

    /// The style the family's previews show without one chosen on its page, and its weight (see `previewStyle`).
    func automaticStyle(of family: Family, weight: Double) -> (face: LibraryFace, weight: Double) {
        family.previewStyle(for: SearchQuery(appliedSearch), tokens: searchTokens, weight: weight)
    }

    /// The tokens the search field suggests for what's typed, but for those it has (see `SearchToken.suggestions`).
    func tokenSuggestions(for typed: String) -> [SearchToken] {
        SearchToken.suggestions(for: typed, besides: searchTokens).map(\.token)
    }

    // MARK: The list

    /// The families the browser shows for the sidebar selection and search. Cached; recomputed only
    /// when the library, selection, search, user data or coverage change.
    var visibleFamilies: [Family] {
        let key = visibleKey
        if let cached = visibleCache, cached.key == key { return cached.families }
        #if CICERO_MEASURE
        let families = Measurements.time("visibleFamilies") { computeVisibleFamilies() }
        #else
        let families = computeVisibleFamilies()
        #endif
        visibleCache = (key, families)
        return families
    }

    /// How many of `visibleFamilies` are active, and the apps of those on in one app only, for the browser's subtitle:
    /// worked out once per list, not with each update of the browser, a pass over every family it lists.
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
            similar: similarFamilyID, document: documentList, measurementRevision: similarFamilyID == nil ? 0 : measurementRevision
        )
    }

    /// Whether the selected items' families can change as coverage is worked out: a character set, or a smart folder with
    /// a language or character set rule. Other lists aren't made again as coverage comes in, every 200 faces while it's
    /// worked out after a scan: at 20,000 families, each time took about 20 ms, and the grid was drawn again too. The
    /// font list's character set columns follow coverage by themselves (`coverageCell`).
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

    /// The font list's rows for `visibleFamilies`, sorted, each with its position, and their families in that order.
    /// Cached: making and sorting thousands of rows takes tens of milliseconds, and the table asks again on every
    /// update, a click included. A row says what a character set column does only for `coverageColumns`, the one the
    /// list is sorted by, if any: worked out for every family, the columns were most of the time it took to make the
    /// rows (0.3 s of 0.4 at 20,000 families). The rows on screen ask for the others as they draw (`coverageCell`).
    func fontRows(sortedBy order: [KeyPathComparator<FontRow>], coverageColumns: [FontListColumn]) -> (rows: [FontRow], families: [Family]) {
        let key = FontRowsKey(visible: visibleKey, order: order, columns: coverageColumns,
                              coverageRevision: coverageColumns.isEmpty ? 0 : coverageRevision)
        if let cached = fontRowsCache, cached.key == key { return (cached.rows, cached.families) }
        let sources = coverageColumns.compactMap { column in coverageSource(of: column).map { (column, $0) } }
        // No order keeps the families' own, as for similar fonts, the closest first.
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
        // Nothing with a word that begins with what's typed: a piece of a longer word, then, like "vetica".
        if found.isEmpty, !query.isEmpty { found = listedFamilies(where: searchMatcher(query.anywhereInNames, tokens: searchTokens)) }
        // A new list's first screens, read ahead before its tiles ask (see `ReadAhead`).
        FontLoader.shared.prefetch(found.prefix(Self.readAheadNewList).map(\.regular.face))
        return found
    }

    /// How many of the browser's first families a scan reads ahead, and a new list (a search, a sidebar item).
    static let readAheadFirst = 200
    static let readAheadNewList = 60

    /// The families the sidebar selection lists, or Show Similar Fonts, or Show in Library, that `matches`.
    private func listedFamilies(where matches: (Family) -> Bool) -> [Family] {
        if let list = documentList {
            return list.families.compactMap { library.family($0) }.filter { data.lists($0) && matches($0) }
        }
        if let id = similarFamilyID {
            guard let family = library.family(id), data.lists(family) else { return [] }
            return ([family] + similarFamilies(to: family, limit: Self.similarListed)).filter(matches)
        }
        let tests = (selectedItems.isEmpty ? [.all] : selectedItems).map(filter(for:))
        // Read once, not through observation for each family; and the families' places first, so that a list of every
        // family, as All Fonts without a search, is the library's own, not a copy of each: copying 20,000 families took
        // 6 ms, half of making the list.
        let data = data, families = library.families
        func keeps(_ family: Family) -> Bool { data.lists(family) && tests.contains { $0(family) } && matches(family) }
        var kept: [Int] = []
        for index in families.indices where keeps(families[index]) { kept.append(index) }
        let listed = kept.count == families.count ? families : kept.map { families[$0] }
        return selectedItems == [.recent] ? Family.latestFirst(listed) : listed
    }

    /// How many days a family stays in Recents.
    static let recentDays = FamilyFilters.recentDays

    /// Whether the browser lists its families in an order of its own, which the list keeps until a column's header is
    /// clicked: similar fonts, the closest first, and Recents, the latest first.
    var hasOwnOrder: Bool { similarFamilyID != nil || selectedItems == [.recent] }

    /// What the search field suggests for what's typed: up to eight of the families the browser would list whose names
    /// begin with it, or have a word that does, those that begin with it first, each alphabetically.
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

    /// The families Compare's Add Families lists for what's typed: of every family the library lists, whatever the
    /// sidebar shows, those the main window's search would find, names that begin with it first, then names with a
    /// word that does, then the rest, each in the library's order. All of them while nothing's typed.
    func compareCandidates(for typed: String) -> [Family] {
        let query = SearchQuery(typed)
        let listed = library.families.filter(data.lists)
        guard !query.isEmpty else { return listed }
        var found = listed.filter(searchMatcher(query))
        // Nothing with a word that begins with what's typed: a piece of a longer word, then, like "vetica".
        if found.isEmpty { found = listed.filter(searchMatcher(query.anywhereInNames)) }
        let ranks = found.map { query.suggestionRank(of: $0.name.lowercased()) ?? 2 }
        return (0...2).flatMap { rank in zip(found, ranks).filter { $0.1 == rank }.map(\.0) }
    }

    /// The rules of the search, the sidebar items and smart folders, from the core (see `FamilyFilters`), with the
    /// guessed classifications and the coverage the app remembers.
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

    /// A test for whether families match a search (see `FamilyFilters.searchMatcher`).
    private func searchMatcher(_ search: SearchQuery, tokens: [SearchToken] = []) -> (Family) -> Bool {
        familyFilters.searchMatcher(search, tokens: tokens)
    }

    /// A test for one sidebar item, with anything expensive looked up once.
    func filter(for item: SidebarItem) -> (Family) -> Bool {
        familyFilters.filter(for: item)
    }

    /// A test for many families at once: set and folder rules resolve their members once.
    func matcher(for smartSet: SmartSet) -> (Family) -> Bool {
        familyFilters.matcher(for: smartSet)
    }

    // MARK: Coverage

    /// nil while the family's characters are still being checked.
    func supports(_ family: Family, language id: String) -> Bool? {
        coverage.coverage(of: family.regular.id).map { $0.support(for: id) != nil }
    }

    /// Built-in character sets, then the user's.
    var characterSets: [CharacterSetDefinition] {
        characterSetCatalog.builtIn + customCharacterSets
    }

    /// Cached: reading a set's characters from what the user typed takes a while for a long one, and the
    /// sidebar and the lists ask on every update.
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

    /// Whether the family's regular face has every character of the set; nil while still being checked.
    func has(_ set: CharacterSetDefinition, _ family: Family) -> Bool? {
        missingCount(set, family).map { $0 == 0 }
    }

    func missingCount(_ set: CharacterSetDefinition, _ family: Family) -> Int? {
        characterSetLookup.missingCount(set, face: family.regular.id, revision: coverageRevision) { [coverage] in
            coverage.coverage(of: family.regular.id)?.scalars
        }
    }

    /// A set's name, without reading the characters of a custom one.
    func characterSetName(_ id: String) -> String? {
        id.hasPrefix("custom.") ? data.customCharacterSets.first { $0.setID == id }?.name : characterSetCatalog.definition(id)?.name
    }

    func characterSetSeries(_ id: String) -> CharacterSetSeries? {
        characterSetCatalog.series.first { $0.id == id }
    }

    /// The largest set of a series (Latin S–XL, Adobe Latin, GF Latin…) the family has.
    /// What a character set column reads its rows from; nil for other columns, or a set that's gone.
    func coverageSource(of column: FontListColumn) -> CoverageSource? {
        switch column {
        case .series(let id): characterSetSeries(id).map(CoverageSource.series)
        case .characterSet(let id): (customCharacterSets.first { $0.id == id } ?? characterSetCatalog.definition(id)).map(CoverageSource.set)
        default: nil
        }
    }

    /// What a character set column says about a family, as its row draws: from the row when the list is sorted by the
    /// column, else worked out now (and kept, see `CharacterSetLookup`). Reads `coverageRevision`, so the row draws
    /// again as coverage changes.
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

/// Memo for character set checks: the font list asks for every family on every render.
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
