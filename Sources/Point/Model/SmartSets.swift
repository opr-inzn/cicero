import Foundation

/// A set whose fonts are picked by rules, and stays current as the library changes.
struct SmartSet: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var matchAll = true
    var rules: [SmartRule] = [SmartRule()]
}

struct SmartRule: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var field: Field = .name
    var comparison: Comparison = .contains
    /// Text, a number, or the id of the chosen option, depending on the field.
    var value = ""

    enum Field: String, Codable, CaseIterable, Sendable {
        case name, foundry, classification, tag, set, folder, status, kind, format, styles, language, characterSet, added

        var title: String {
            switch self {
            case .name: "Name"
            case .foundry: "Foundry"
            case .classification: "Classification"
            case .tag: "Tag"
            case .set: "Set"
            case .folder: "Folder"
            case .status: "Status"
            case .kind: "Kind"
            case .format: "Format"
            case .styles: "Number of Styles"
            case .language: "Language"
            case .characterSet: "Character Set"
            case .added: "Date Added"
            }
        }

        var comparisons: [Comparison] {
            switch self {
            case .name: [.contains, .doesNotContain, .beginsWith, .is]
            case .foundry: [.is, .isNot, .contains]
            case .styles: [.is, .greaterThan, .lessThan]
            case .added: [.inLast, .notInLast]
            default: [.is, .isNot]
            }
        }

        var takesText: Bool { self == .name }
        var takesNumber: Bool { self == .styles || self == .added }
    }

    enum Comparison: String, Codable, Sendable {
        case contains, doesNotContain, beginsWith, `is`, isNot, greaterThan, lessThan, inLast, notInLast
    }

    init() {}

    init(field: Field) {
        self.field = field
        comparison = field.comparisons[0]
        value = field == .styles ? "1" : field == .added ? "30" : ""
    }

    /// Wording that reads naturally with the field, e.g. "Tag has", "Language is supported".
    func label(for comparison: Comparison) -> String {
        switch (field, comparison) {
        case (.tag, .is): "has"
        case (.tag, .isNot): "doesn’t have"
        case (.set, .is), (.folder, .is): "is in"
        case (.set, .isNot), (.folder, .isNot): "isn’t in"
        case (.language, .is), (.characterSet, .is): "is supported"
        case (.language, .isNot), (.characterSet, .isNot): "isn’t supported"
        case (_, .contains): "contains"
        case (_, .doesNotContain): "doesn’t contain"
        case (_, .beginsWith): "begins with"
        case (_, .is): "is"
        case (_, .isNot): "is not"
        case (_, .greaterThan): "is more than"
        case (_, .lessThan): "is less than"
        case (_, .inLast): "is in the last"
        case (_, .notInLast): "isn’t in the last"
        }
    }
}

/// Options for fields that pick from a fixed list.
enum SmartRuleOption {
    static let statuses: [(id: String, title: String)] = [
        ("active", "Activated"), ("partial", "Partly Activated"), ("inactive", "Not Activated"),
        ("appOnly", "Active in Apps Only"), ("system", "Installed with macOS"),
    ]
    static let kinds: [(id: String, title: String)] = [
        ("variable", "Variable"), ("monospaced", "Monospaced"), ("italics", "Has Italics"),
    ]
    static let formats = [
        "OpenType, PostScript outlines", "OpenType, TrueType outlines", "Font Collection",
        "Datafork TrueType", "Web Font", "Mixed",
    ]
}

extension LibraryStore {
    func smartSet(_ id: UUID) -> SmartSet? {
        data.smartSets.first { $0.id == id }
    }

    func matches(_ family: FontFamily, _ smartSet: SmartSet) -> Bool {
        let rules = smartSet.rules
        guard !rules.isEmpty else { return false }
        return smartSet.matchAll ? rules.allSatisfy { matches(family, $0) } : rules.contains { matches(family, $0) }
    }

    func matches(_ family: FontFamily, _ rule: SmartRule) -> Bool {
        let value = rule.value
        func compare(_ isMatch: Bool) -> Bool { rule.comparison == .isNot ? !isMatch : isMatch }
        switch rule.field {
        case .name:
            let name = family.name
            switch rule.comparison {
            case .contains: return value.isEmpty || name.localizedCaseInsensitiveContains(value)
            case .doesNotContain: return value.isEmpty || !name.localizedCaseInsensitiveContains(value)
            case .beginsWith: return name.lowercased().hasPrefix(value.lowercased())
            default: return name.localizedCaseInsensitiveCompare(value) == .orderedSame
            }
        case .foundry:
            let foundry = foundryName(of: family) ?? ""
            if rule.comparison == .contains { return foundry.localizedCaseInsensitiveContains(value) }
            return compare(foundry == value)
        case .classification:
            return compare(family.classification.rawValue == value)
        case .tag:
            return compare(tags(of: family).contains(value))
        case .set:
            return compare(data.sets.first { $0.id.uuidString == value }?.familyNames.contains(family.name) ?? false)
        case .folder:
            return compare(UUID(uuidString: value).map(family.folderIDs.contains) ?? false)
        case .status:
            let status: String = switch family.status {
            case .active: "active"
            case .partial: "partial"
            case .inactive: "inactive"
            case .appOnly: "appOnly"
            case .system: "system"
            }
            // Fonts that come with macOS are activated too.
            return compare(status == value || (value == "active" && status == "system"))
        case .kind:
            let isKind = switch value {
            case "variable": family.isVariable
            case "monospaced": family.isMonospaced
            case "italics": family.faces.contains { $0.face.isItalic }
            default: false
            }
            return compare(isKind)
        case .format:
            return compare(family.format == value)
        case .styles:
            let count = family.faces.count
            let number = Int(value) ?? 0
            switch rule.comparison {
            case .greaterThan: return count > number
            case .lessThan: return count < number
            default: return count == number
            }
        case .language:
            guard let supported = CharacterCoverage.shared.supports(family, language: value) else { return false }
            return compare(supported)
        case .characterSet:
            guard let set = characterSet(value), let supported = supports(family, characterSet: set) else { return false }
            return compare(supported)
        case .added:
            guard let added = family.dateAdded else { return false }
            let days = Double(Int(value) ?? 0)
            let isRecent = added > Date().addingTimeInterval(-days * 86_400)
            return rule.comparison == .notInLast ? !isRecent : isRecent
        }
    }

    // MARK: Editing

    func addSmartSet(_ smartSet: SmartSet) {
        data.smartSets.append(smartSet)
        data.hiddenSidebarItems.remove(SidebarSection.sets.key)
        save()
        sidebarSelection = .smartSet(smartSet.id)
    }

    func updateSmartSet(_ smartSet: SmartSet) {
        guard let index = data.smartSets.firstIndex(where: { $0.id == smartSet.id }) else { return }
        data.smartSets[index] = smartSet
        save()
    }

    func deleteSmartSet(_ id: UUID) {
        data.smartSets.removeAll { $0.id == id }
        data.hiddenSidebarItems.remove("smartset.\(id)")
        if sidebarSelection == .smartSet(id) { sidebarSelection = .all }
        save()
    }
}
