import Foundation

extension UserData {
    // MARK: Foundries

    public func foundryNamer() -> (Family) -> String? {
        let overrides = foundryOverrides
        let renames = foundryRenames
        return { family in
            if let override = overrides[family.id] { return override }
            guard let raw = family.manufacturer else { return nil }
            return renames[raw] ?? raw
        }
    }

    // MARK: Classifications

    public func name(of classification: Classification) -> String {
        classificationRenames[classification.rawValue] ?? classification.rawValue
    }

    public var classificationNames: [String] {
        Classification.allCases.map(name(of:)) + classifications
    }

    public func classificationNamer(guess: @escaping (Family) -> Classification? = { _ in nil }) -> (Family) -> String {
        let overrides = classificationOverrides
        let renames = classificationRenames
        return { family in
            if let override = overrides[family.id] { return override }
            let classification = guess(family) ?? family.classification
            return renames[classification.rawValue] ?? classification.rawValue
        }
    }

    // MARK: Tags

    public func families(tagged tag: String) -> Set<String> {
        Set(familyTags.filter { $0.value.contains(tag) }.keys)
    }

    @discardableResult
    public mutating func addTag(named name: String, color: TagColor?, to families: [String] = []) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !tags.contains(trimmed) {
            tags.append(trimmed)
            tagColors[trimmed] = color
            sidebar.hidden.remove(SidebarPreferences.tagsSectionKey)
        }
        setTag(trimmed, true, for: families)
        return trimmed
    }

    public mutating func setTag(_ tag: String, _ isOn: Bool, for families: [String]) {
        for family in families {
            var tags = familyTags[family] ?? []
            if isOn, !tags.contains(tag) { tags.append(tag) }
            if !isOn { tags.removeAll { $0 == tag } }
            familyTags[family] = tags.isEmpty ? nil : tags
        }
    }

    @discardableResult
    public mutating func renameTag(_ old: String, to new: String) -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, !tags.contains(trimmed), let index = tags.firstIndex(of: old) else { return false }
        tags[index] = trimmed
        let color = tagColors.removeValue(forKey: old)
        tagColors[trimmed] = color
        for (family, names) in familyTags where names.contains(old) {
            familyTags[family] = names.map { $0 == old ? trimmed : $0 }
        }
        for set in smartSets.indices {
            for rule in smartSets[set].rules.indices where smartSets[set].rules[rule].field == .tag && smartSets[set].rules[rule].value == old {
                smartSets[set].rules[rule].value = trimmed
            }
        }
        sidebar.rename("tag.\(old)", to: "tag.\(trimmed)")
        return true
    }

    public mutating func deleteTags(_ names: Set<String>) {
        tags.removeAll(where: names.contains)
        for (family, tags) in familyTags where tags.contains(where: names.contains) {
            let left = tags.filter { !names.contains($0) }
            familyTags[family] = left.isEmpty ? nil : left
        }
        for index in smartSets.indices {
            smartSets[index].rules.removeAll { $0.field == .tag && names.contains($0.value) }
        }
        for name in names {
            tagColors[name] = nil
            sidebar.forget("tag.\(name)")
        }
    }

    // MARK: Folders (sets)

    @discardableResult
    public mutating func addSet(named name: String, families: [String] = [], styles: [String: [String]] = [:]) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let set = FontSet(name: trimmed, families: families, styles: styles)
        sets.append(set)
        sidebar.hidden.remove(SidebarPreferences.setsSectionKey)
        return set.id
    }

    @discardableResult
    public mutating func setMembership(_ member: Bool, for families: [String], in setID: UUID) -> Bool {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return false }
        if member {
            sets[index].add(families: families)
        } else {
            sets[index].remove(families: Set(families))
        }
        return true
    }

    @discardableResult
    public mutating func renameSet(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sets.firstIndex(where: { $0.id == id }) else { return false }
        sets[index].name = trimmed
        return true
    }

    public mutating func deleteSets(_ ids: Set<UUID>) {
        let values = Set(ids.map(\.uuidString))
        sets.removeAll { ids.contains($0.id) }
        for id in ids { sidebar.forget("set.\(id)") }
        for index in smartSets.indices {
            smartSets[index].rules.removeAll { $0.field == .set && values.contains($0.value) }
        }
    }

    // MARK: After an activation

    public mutating func forgetInstalledAddedFiles() {
        let installed = Set(records.installedCopies.values)
        guard fontFiles.contains(where: installed.contains) else { return }
        fontFiles.removeAll(where: installed.contains)
    }
}

extension SidebarPreferences {
    public static let tagsSectionKey = "section.tags"
    public static let setsSectionKey = "section.sets"
}
