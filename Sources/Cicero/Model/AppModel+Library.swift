import Foundation
import CiceroCore

enum SidebarItem: Hashable {
    case all, active, inactive, system, problems
    /// Families with a style that arrived on the Mac in the last `AppModel.recentDays` days.
    case recent
    /// Families with a style on until Cicero quits (Activate Temporarily); not application sets'.
    case temporary
    case folder(UUID)
    case set(UUID)
    case smartSet(UUID)
    case tag(String)
    case foundry(String)
    /// By name: a built-in classification under the name the user gave it, or one of theirs.
    case classification(String)
    case characterSet(String)
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case folders, sets, tags, foundries, classifications, characterSets

    var id: String { rawValue }
    var key: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        case .folders: "Folders"
        case .sets: "Sets"
        // The license tags to begin with; called License in 1.5 to 1.5.2, when a family had one.
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
        case .sets: "square.stack"
        case .tags: "tag"
        case .foundries: "building.2"
        case .classifications: "textformat"
        case .characterSets: "character.textbox"
        }
    }
}

/// A family in Compare, in a style.
struct CompareEntry: Identifiable, Equatable {
    let id = UUID()
    let familyID: String
    /// nil: the one nearest the preview weight.
    var style: FaceID?
    /// Its place among the tints, kept while it stays, so moving or removing the others doesn't change its colour.
    let tint: Int
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
}

extension LibraryFace {
    /// On until Cicero quits, from Activate Temporarily.
    var isOnUntilQuit: Bool { state == .active(.temporary(.untilQuit)) }
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
        return library.families.filter { selectedIDs.contains($0.id) }
    }

    /// Right-click targets: the whole selection when the clicked family is part of it.
    func targets(for family: Family) -> [Family] {
        guard selectedIDs.contains(family.id), selectedIDs.count > 1 else { return [family] }
        return library.families.filter { selectedIDs.contains($0.id) }
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
    func foundryNamer() -> (Family) -> String? {
        let overrides = data.foundryOverrides
        let renames = data.foundryRenames
        return { family in
            if let override = overrides[family.id] { return override }
            guard let raw = family.manufacturer else { return nil }
            return renames[raw] ?? raw
        }
    }

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
        return family.previewStyle(for: SearchQuery(appliedSearch), tokens: searchTokens, weight: weight)
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
        let families = computeVisibleFamilies()
        visibleCache = (key, families)
        return families
    }

    private var visibleKey: VisibleKey {
        VisibleKey(
            fingerprint: library.fingerprint, selection: selectedItems, search: appliedSearch, tokens: searchTokens,
            dataRevision: dataRevision, coverageRevision: coverageRevision, guessRevision: guessRevision,
            similar: similarFamilyID, document: documentList, measurementRevision: similarFamilyID == nil ? 0 : measurementRevision
        )
    }

    /// The font list's rows for `visibleFamilies`, sorted, with what the shown character set columns say, and
    /// their families in that order. Cached: making and sorting thousands of rows takes tens of milliseconds,
    /// and the table asks again on every update, a click included.
    func fontRows(sortedBy order: [KeyPathComparator<FontRow>], columns: [FontListColumn]) -> (rows: [FontRow], families: [Family]) {
        let key = FontRowsKey(visible: visibleKey, order: order, columns: columns)
        if let cached = fontRowsCache, cached.key == key { return (cached.rows, cached.families) }
        let custom = customCharacterSets
        let sources: [(FontListColumn, CoverageSource)] = columns.compactMap { column in
            switch column {
            case .series(let id): characterSetSeries(id).map { (column, CoverageSource.series($0)) }
            case .characterSet(let id): (custom.first { $0.id == id } ?? characterSetCatalog.definition(id)).map { (column, CoverageSource.set($0)) }
            default: nil
            }
        }
        // No order keeps the families' own, as for similar fonts, the closest first.
        let unsorted = visibleFamilies.map { FontRow($0, coverage: sources, model: self) }
        let rows = order.isEmpty ? unsorted : unsorted.sorted(using: order)
        let families = rows.map(\.family)
        fontRowsCache = (key, rows, families)
        return (rows, families)
    }

    private func computeVisibleFamilies() -> [Family] {
        let query = SearchQuery(appliedSearch)
        let found = listedFamilies(where: searchMatcher(query, tokens: searchTokens))
        // Nothing with a word that begins with what's typed: a piece of a longer word, then, like "vetica".
        guard found.isEmpty, !query.isEmpty else { return found }
        return listedFamilies(where: searchMatcher(query.anywhereInNames, tokens: searchTokens))
    }

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
        let listed = library.families.filter { family in
            guard data.lists(family) else { return false }
            return tests.contains { $0(family) } && matches(family)
        }
        return selectedItems == [.recent] ? Family.latestFirst(listed) : listed
    }

    /// How many days a family stays in Recents.
    static let recentDays = 7

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

    /// A test for whether families match a search: by what the library searches (see `Library.matches`), and by the
    /// user's note, the foundry and classification the family is shown in, a built-in classification by its usual
    /// words too, and its tags; and by the search field's tokens (see `Family.matches`).
    private func searchMatcher(_ search: SearchQuery, tokens: [SearchToken] = []) -> (Family) -> Bool {
        guard !search.isEmpty else { return tokens.isEmpty ? { _ in true } : { $0.matches(tokens) } }
        let library = library, data = data
        let notes = data.familyNotes.mapValues { $0.lowercased() }
        let foundryName = foundryNamer(), classificationName = classificationNamer()
        var classificationTerms: [String: [String]] = [:]
        for name in data.classifications { classificationTerms[name] = [name.lowercased()] }
        for classification in Classification.allCases {
            let shown = name(of: classification)
            classificationTerms[shown] = [shown.lowercased()] + classification.searchTerms
        }
        return { family in
            guard tokens.isEmpty || family.matches(tokens) else { return false }
            let foundry = foundryName(family).flatMap { $0 == family.manufacturer ? nil : $0.lowercased() }
            let classification = classificationName(family)
            let terms = (classificationTerms[classification] ?? [classification.lowercased()]) + data.tags(of: family.id).map { $0.lowercased() }
            return library.matches(family, search: search, note: notes[family.id], texts: foundry.map { [$0] } ?? [], terms: terms)
        }
    }

    /// A test for one sidebar item, with anything expensive looked up once.
    func filter(for item: SidebarItem) -> (Family) -> Bool {
        switch item {
        case .all: return { _ in true }
        case .active: return { $0.hasActive }
        case .inactive: return { family in family.faces.contains { $0.state == .inactive } }
        case .system: return { $0.state == .system }
        case .temporary: return { $0.faces.contains(where: \.isOnUntilQuit) }
        case .recent:
            let cutoff = Date.now.addingTimeInterval(-Double(Self.recentDays) * 86_400)
            return { $0.lastAdded.map { $0 > cutoff } ?? false }
        case .problems: return { _ in false }
        case .folder(let id): return { $0.folderIDs.contains(id) }
        case .set(let id):
            // Families it has only some styles of too.
            let members = Set(data.sets.first { $0.id == id }?.memberFamilies ?? [])
            return { members.contains($0.id) }
        case .smartSet(let id):
            guard let smartSet = data.smartSets.first(where: { $0.id == id }) else { return { _ in false } }
            return matcher(for: smartSet)
        case .tag(let name):
            let tagged = Set(data.familyTags.filter { $0.value.contains(name) }.keys)
            return { tagged.contains($0.id) }
        case .foundry(let name):
            let foundryName = foundryNamer()
            return { foundryName($0) == name }
        case .classification(let name):
            let classificationName = classificationNamer()
            return { classificationName($0) == name }
        case .characterSet(let id):
            guard let set = characterSet(id) else { return { _ in false } }
            return { self.has(set, $0) == true }
        }
    }

    // MARK: Smart sets

    /// A test for many families at once: set and folder rules resolve their members once.
    func matcher(for smartSet: SmartSet) -> (Family) -> Bool {
        let checks = smartSet.rules.map(check(for:))
        guard !checks.isEmpty else { return { _ in false } }
        return smartSet.matchAll ? { family in checks.allSatisfy { $0(family) } } : { family in checks.contains { $0(family) } }
    }

    private func check(for rule: SmartRule) -> (Family) -> Bool {
        let value = rule.value
        let negate = rule.comparison == .isNot
        func compare(_ test: @escaping (Family) -> Bool) -> (Family) -> Bool {
            negate ? { !test($0) } : test
        }
        switch rule.field {
        case .name:
            // The fonts' own name, or the one in the Mac's language a family shows.
            let lower = value.lowercased()
            func names(_ family: Family) -> [String] {
                family.name == family.id ? [family.id.lowercased()] : [family.id.lowercased(), family.name.lowercased()]
            }
            switch rule.comparison {
            case .contains: return { family in lower.isEmpty || names(family).contains { $0.contains(lower) } }
            case .doesNotContain: return { family in lower.isEmpty || !names(family).contains { $0.contains(lower) } }
            case .beginsWith: return { family in names(family).contains { $0.hasPrefix(lower) } }
            default: return { family in names(family).contains(lower) }
            }
        case .foundry:
            if rule.comparison == .contains {
                let lower = value.lowercased()
                return { (self.foundryName(of: $0) ?? "").lowercased().contains(lower) }
            }
            return compare { self.foundryName(of: $0) == value }
        case .designer:
            // Any style's: a family's styles may credit different designers, or some of them none.
            let lower = value.lowercased()
            func designers(_ family: Family) -> [String] { family.faces.compactMap { $0.face.designer?.lowercased() } }
            switch rule.comparison {
            case .contains: return { family in lower.isEmpty || designers(family).contains { $0.contains(lower) } }
            case .doesNotContain: return { family in lower.isEmpty || !designers(family).contains { $0.contains(lower) } }
            default: return { family in designers(family).contains(lower) }
            }
        case .classification:
            let classificationName = classificationNamer()
            return compare { classificationName($0) == value }
        case .tag:
            let tagged = Set(data.familyTags.filter { $0.value.contains(value) }.keys)
            return compare { tagged.contains($0.id) }
        case .note:
            // Without text: whether the family has a note at all, as Has Note says, for sets made before there was one.
            let lower = value.lowercased()
            let notes = data.familyNotes.mapValues { $0.lowercased() }
            let contains = rule.comparison != .doesNotContain
            return { family in
                guard let note = notes[family.id] else { return !contains }
                return (lower.isEmpty || note.contains(lower)) == contains
            }
        case .hasNote:
            let noted = data.familyNotes
            return compare { noted[$0.id] != nil }
        case .rating:
            // No rating is 0 stars.
            let ratings = data.familyRatings
            let stars = Int(value) ?? 0
            switch rule.comparison {
            case .greaterThan: return { ratings[$0.id, default: 0] > stars }
            case .lessThan: return { ratings[$0.id, default: 0] < stars }
            default: return compare { ratings[$0.id, default: 0] == stars }
            }
        case .set:
            let members = Set(data.sets.first { $0.id.uuidString == value }?.memberFamilies ?? [])
            return compare { members.contains($0.id) }
        case .folder:
            let id = UUID(uuidString: value)
            return compare { id.map($0.folderIDs.contains) ?? false }
        case .status:
            return compare { family in
                switch (family.state, value) {
                case (.active, "active"), (.system, "active"), (.partial, "partial"), (.inactive, "inactive"),
                     (.appOnly, "appOnly"), (.system, "system"): true
                default: false
                }
            }
        case .kind:
            return compare { family in
                switch value {
                case "variable": family.isVariable
                case "monospaced": family.isMonospaced
                case "italics": family.hasItalics
                default: false
                }
            }
        case .format:
            return compare { $0.format.rawValue == value }
        case .styles:
            let number = Int(value) ?? 0
            switch rule.comparison {
            case .greaterThan: return { $0.faces.count > number }
            case .lessThan: return { $0.faces.count < number }
            default: return { $0.faces.count == number }
            }
        case .feature:
            guard let feature = OpenTypeFeature(rawValue: value) else { return { _ in false } }
            return compare { $0.features.contains(feature) }
        case .embedding:
            return compare { $0.embedding?.rawValue == value }
        case .language:
            return { family in
                guard let supported = self.supports(family, language: value) else { return false }
                return supported != negate
            }
        case .characterSet:
            guard let set = characterSet(value) else { return { _ in false } }
            return { family in
                guard let has = self.has(set, family) else { return false }
                return has != negate
            }
        case .added:
            let cutoff = Date().addingTimeInterval(-Double(Int(value) ?? 0) * 86_400)
            let recent = rule.comparison != .notInLast
            return { family in
                guard let added = family.dateAdded else { return false }
                return (added > cutoff) == recent
            }
        case .timesActivated:
            let activations = data.activations
            let number = Int(value) ?? 0
            switch rule.comparison {
            case .greaterThan: return { activations[$0.id]?.count ?? 0 > number }
            case .lessThan: return { activations[$0.id]?.count ?? 0 < number }
            default: return { activations[$0.id]?.count ?? 0 == number }
            }
        case .lastActivated:
            // A family never turned on since Cicero began counting wasn't turned on in the last days either.
            let activations = data.activations
            let cutoff = Date().addingTimeInterval(-Double(Int(value) ?? 0) * 86_400)
            let recent = rule.comparison != .notInLast
            return { family in
                guard let last = activations[family.id]?.last else { return !recent }
                return (last > cutoff) == recent
            }
        }
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
