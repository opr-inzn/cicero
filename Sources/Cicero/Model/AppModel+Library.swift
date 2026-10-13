import Foundation
import CiceroCore

enum SidebarItem: Hashable {
    case all, active, inactive, system, problems
    case folder(UUID)
    case set(UUID)
    case smartSet(UUID)
    case foundry(String)
    case classification(Classification)
    case characterSet(String)
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case folders, sets, foundries, classifications, characterSets

    var id: String { rawValue }
    var key: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        case .folders: "Folders"
        case .sets: "Sets"
        case .foundries: "Foundries"
        case .classifications: "Classifications"
        case .characterSets: "Character Sets"
        }
    }

    var icon: String {
        switch self {
        case .folders: "folder"
        case .sets: "square.stack"
        case .foundries: "building.2"
        case .classifications: "textformat"
        case .characterSets: "character.textbox"
        }
    }
}

struct SidebarRow: Identifiable, Hashable {
    /// Visibility key, see `SidebarPreferences.hidden`.
    var key: String
    var title: String
    var icon: String
    var item: SidebarItem
    var badge = 0

    var id: String { key }
}

/// What a cached `visibleFamilies` was computed from.
struct VisibleKey: Equatable {
    var fingerprint: Int
    var selection: Set<SidebarItem>
    var search: String
    var dataRevision: Int
    var coverageRevision: Int
}

/// What the cached rows of the font list were made from.
struct FontRowsKey: Equatable {
    var visible: VisibleKey
    var order: [KeyPathComparator<FontRow>]
}

extension Classification {
    var icon: String {
        switch self {
        case .serif: "textformat"
        case .slabSerif: "rectangle.split.3x1"
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
        if let override = data.foundryOverrides[family.id] { return override }
        guard let raw = family.manufacturer else { return nil }
        return data.foundryRenames[raw] ?? raw
    }

    func features(for family: Family) -> [FeatureSetting] { familyFeatures[family.id] ?? [] }

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
            fingerprint: library.fingerprint, selection: selectedItems, search: appliedSearch,
            dataRevision: dataRevision, coverageRevision: coverageRevision
        )
    }

    /// The font list's rows for `visibleFamilies`, sorted. Cached: making and sorting thousands of rows
    /// takes tens of milliseconds, and the table asks again on every update, a click included.
    func fontRows(sortedBy order: [KeyPathComparator<FontRow>]) -> [FontRow] {
        let key = FontRowsKey(visible: visibleKey, order: order)
        if let cached = fontRowsCache, cached.key == key { return cached.rows }
        let rows = visibleFamilies.map { FontRow($0, model: self) }.sorted(using: order)
        fontRowsCache = (key, rows)
        return rows
    }

    private func computeVisibleFamilies() -> [Family] {
        let query = appliedSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let tests = (selectedItems.isEmpty ? [.all] : selectedItems).map(filter(for:))
        return library.families.filter { family in
            if !data.showSystemFonts && family.state == .system { return false }
            return tests.contains { $0(family) } && library.matches(family, search: query)
        }
    }

    /// A test for one sidebar item, with anything expensive looked up once.
    func filter(for item: SidebarItem) -> (Family) -> Bool {
        switch item {
        case .all: return { _ in true }
        case .active: return { $0.hasActive }
        case .inactive: return { family in family.faces.contains { $0.state == .inactive } }
        case .system: return { $0.state == .system }
        case .problems: return { _ in false }
        case .folder(let id): return { $0.folderIDs.contains(id) }
        case .set(let id):
            let members = Set(data.sets.first { $0.id == id }?.families ?? [])
            return { members.contains($0.id) }
        case .smartSet(let id):
            guard let smartSet = data.smartSets.first(where: { $0.id == id }) else { return { _ in false } }
            return matcher(for: smartSet)
        case .foundry(let name): return { self.foundryName(of: $0) == name }
        case .classification(let classification): return { $0.classification == classification }
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
            let lower = value.lowercased()
            switch rule.comparison {
            case .contains: return { lower.isEmpty || $0.name.lowercased().contains(lower) }
            case .doesNotContain: return { lower.isEmpty || !$0.name.lowercased().contains(lower) }
            case .beginsWith: return { $0.name.lowercased().hasPrefix(lower) }
            default: return { $0.name.lowercased() == lower }
            }
        case .foundry:
            if rule.comparison == .contains {
                let lower = value.lowercased()
                return { (self.foundryName(of: $0) ?? "").lowercased().contains(lower) }
            }
            return compare { self.foundryName(of: $0) == value }
        case .classification:
            return compare { $0.classification.rawValue == value }
        case .tag:
            // Tags have no UI for now; rules saved before keep working.
            return compare { self.data.familyTags[$0.id]?.contains(value) == true }
        case .set:
            let members = Set(data.sets.first { $0.id.uuidString == value }?.families ?? [])
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

    var customCharacterSets: [CharacterSetDefinition] {
        data.customCharacterSets.enumerated().map { CharacterSetCatalog.definition(for: $1, level: $0) }
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

    /// The largest set of a series (Latin S–XL, Adobe Latin) the family has.
    func largestSet(in groupID: String, for family: Family) -> CharacterSetDefinition? {
        guard let group = characterSetCatalog.groups.first(where: { $0.id == groupID }) else { return nil }
        return characterSetLookup.largest(group, family: family.id, revision: coverageRevision) { set in
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
        var group: String
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

    func largest(_ group: CharacterSetGroup, family: String, revision: Int, missing: (CharacterSetDefinition) -> Int?) -> CharacterSetDefinition? {
        sync(revision)
        let key = SeriesKey(group: group.id, family: family)
        if let level = largest[key] { return level >= 0 ? group.sets[level] : nil }
        var level = -1
        for (index, set) in group.sets.enumerated().reversed() {
            guard let count = missing(set) else { return nil }
            if count == 0 {
                level = index
                break
            }
        }
        largest[key] = level
        return level >= 0 ? group.sets[level] : nil
    }
}
