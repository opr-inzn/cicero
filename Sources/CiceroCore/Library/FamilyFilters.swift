import Foundation

public enum SidebarItem: Hashable, Sendable {
    case all, active, inactive, system, problems
    case recent
    case temporary
    case folder(UUID)
    case set(UUID)
    case smartSet(UUID)
    case tag(String)
    case foundry(String)
    case classification(String)
    case characterSet(String)
}

extension LibraryFace {
    public var isOnUntilQuit: Bool { state == .active(.temporary(.untilQuit)) }
}

public struct CoverageAnswers {
    public var characterSet: (String) -> CharacterSetDefinition?
    public var missingCount: (CharacterSetDefinition, Family) -> Int?
    public var supports: (Family, String) -> Bool?

    public init(characterSet: @escaping (String) -> CharacterSetDefinition?,
                missingCount: @escaping (CharacterSetDefinition, Family) -> Int?,
                supports: @escaping (Family, String) -> Bool?) {
        self.characterSet = characterSet
        self.missingCount = missingCount
        self.supports = supports
    }

    public static var none: CoverageAnswers { CoverageAnswers(characterSet: { _ in nil }, missingCount: { _, _ in nil }, supports: { _, _ in nil }) }
}

public struct FamilyFilters {
    public var library: Library
    public var data: UserData
    public var classificationGuess: (Family) -> Classification?
    public var coverage: CoverageAnswers
    public var now: Date

    public static let recentDays = 7

    public init(library: Library, data: UserData, classificationGuess: @escaping (Family) -> Classification? = { _ in nil },
                coverage: CoverageAnswers = .none, now: Date = .now) {
        self.library = library
        self.data = data
        self.classificationGuess = classificationGuess
        self.coverage = coverage
        self.now = now
    }

    public func classificationNamer() -> (Family) -> String {
        data.classificationNamer(guess: classificationGuess)
    }

    public func has(_ set: CharacterSetDefinition, _ family: Family) -> Bool? {
        coverage.missingCount(set, family).map { $0 == 0 }
    }

    // MARK: Search

    public func searchMatcher(_ search: SearchQuery, tokens: [SearchToken] = [],
                              moreTexts: @escaping (Family) -> [String] = { _ in [] }) -> (Family) -> Bool {
        guard !search.isEmpty else { return tokens.isEmpty ? { _ in true } : { $0.matches(tokens) } }
        let library = library, data = data
        let notes = data.familyNotes.mapValues { $0.lowercased() }
        let foundryName = data.foundryNamer(), classificationName = classificationNamer()
        var classificationTerms: [String: [String]] = [:]
        for name in data.classifications { classificationTerms[name] = [name.lowercased()] }
        for classification in Classification.allCases {
            let shown = data.name(of: classification)
            classificationTerms[shown] = [shown.lowercased()] + classification.searchTerms
        }
        return { family in
            guard tokens.isEmpty || family.matches(tokens) else { return false }
            let foundry = foundryName(family).flatMap { $0 == family.manufacturer ? nil : $0.lowercased() }
            let classification = classificationName(family)
            let terms = (classificationTerms[classification] ?? [classification.lowercased()]) + data.tags(of: family.id).map { $0.lowercased() }
            return library.matches(family, search: search, note: notes[family.id], texts: (foundry.map { [$0] } ?? []) + moreTexts(family), terms: terms)
        }
    }

    // MARK: Sidebar items

    public func filter(for item: SidebarItem) -> (Family) -> Bool {
        switch item {
        case .all: return { _ in true }
        case .active: return { $0.hasActive }
        case .inactive: return { family in family.faces.contains { $0.state == .inactive } }
        case .system: return { $0.state == .system }
        case .temporary: return { $0.faces.contains(where: \.isOnUntilQuit) }
        case .recent:
            let cutoff = now.addingTimeInterval(-Double(Self.recentDays) * 86_400)
            return { $0.lastAdded.map { $0 > cutoff } ?? false }
        case .problems: return { _ in false }
        case .folder(let id): return { $0.folderIDs.contains(id) }
        case .set(let id):
            let members = Set(data.sets.first { $0.id == id }?.memberFamilies ?? [])
            return { members.contains($0.id) }
        case .smartSet(let id):
            guard let smartSet = data.smartSets.first(where: { $0.id == id }) else { return { _ in false } }
            return matcher(for: smartSet)
        case .tag(let name):
            let tagged = data.families(tagged: name)
            return { tagged.contains($0.id) }
        case .foundry(let name):
            let foundryName = data.foundryNamer()
            return { foundryName($0) == name }
        case .classification(let name):
            let classificationName = classificationNamer()
            return { classificationName($0) == name }
        case .characterSet(let id):
            guard let set = coverage.characterSet(id) else { return { _ in false } }
            let has = has
            return { has(set, $0) == true }
        }
    }

    // MARK: Smart folders

    public func matcher(for smartSet: SmartSet) -> (Family) -> Bool {
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
            let foundryName = data.foundryNamer()
            if rule.comparison == .contains {
                let lower = value.lowercased()
                return { (foundryName($0) ?? "").lowercased().contains(lower) }
            }
            return compare { foundryName($0) == value }
        case .designer:
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
            let tagged = data.families(tagged: value)
            return compare { tagged.contains($0.id) }
        case .note:
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
            let supports = coverage.supports
            return { family in
                guard let supported = supports(family, value) else { return false }
                return supported != negate
            }
        case .characterSet:
            guard let set = coverage.characterSet(value) else { return { _ in false } }
            let has = has
            return { family in
                guard let has = has(set, family) else { return false }
                return has != negate
            }
        case .added:
            let cutoff = now.addingTimeInterval(-Double(Int(value) ?? 0) * 86_400)
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
            let activations = data.activations
            let cutoff = now.addingTimeInterval(-Double(Int(value) ?? 0) * 86_400)
            let recent = rule.comparison != .notInLast
            return { family in
                guard let last = activations[family.id]?.last else { return !recent }
                return (last > cutoff) == recent
            }
        }
    }
}
