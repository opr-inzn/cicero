import Foundation

/// The rules for the names the user gave things, and for tags and folders, the app and the `cicero` tool both follow.
extension UserData {
    // MARK: Foundries

    /// The foundry a family is shown in, for many families: the one the user put it in, else the one its fonts name,
    /// under the name the user gave that. The user's names are read once, not for every family.
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

    /// A built-in classification's name, as the user renamed it.
    public func name(of classification: Classification) -> String {
        classificationRenames[classification.rawValue] ?? classification.rawValue
    }

    /// Every classification, for menus: the built-in ones under their names, then the user's.
    public var classificationNames: [String] {
        Classification.allCases.map(name(of:)) + classifications
    }

    /// The classification a family is shown in, for many families: the one the user put it in, else `guess`'s for it,
    /// else the one its fonts suggest, under the name the user gave that. The user's choices are read once.
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

    /// The families that have the tag.
    public func families(tagged tag: String) -> Set<String> {
        Set(familyTags.filter { $0.value.contains(tag) }.keys)
    }

    /// Makes a tag in the colour (nil: none) and gives it to the families, which keep the ones they have. A name that's
    /// taken gives them that tag, in the colour it has. Returns the tag's name as made, trimmed; nil for an empty name.
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

    /// Gives the families the tag, or takes it off them; each keeps its other tags.
    public mutating func setTag(_ tag: String, _ isOn: Bool, for families: [String]) {
        for family in families {
            var tags = familyTags[family] ?? []
            if isOn, !tags.contains(tag) { tags.append(tag) }
            if !isOn { tags.removeAll { $0 == tag } }
            familyTags[family] = tags.isEmpty ? nil : tags
        }
    }

    // MARK: Folders (sets)

    /// Makes a folder with the families, whole, and the styles of others; nil for an empty name. Folders can share a
    /// name, as in the app.
    @discardableResult
    public mutating func addSet(named name: String, families: [String] = [], styles: [String: [String]] = [:]) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let set = FontSet(name: trimmed, families: families, styles: styles)
        sets.append(set)
        sidebar.hidden.remove(SidebarPreferences.setsSectionKey)
        return set.id
    }

    /// Puts the families in the folder whole, in place of the styles of them it had, or takes them out with their
    /// styles. False when there's no such folder.
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

    // MARK: After an activation

    /// Added files an earlier version installed a copy of leave Added Fonts: the copy in ~/Library/Fonts is the font in
    /// the library now, in All Fonts like any installed font, and what Reveal in Finder shows. For the records earlier
    /// versions wrote, before the scan after an operation.
    public mutating func forgetInstalledAddedFiles() {
        let installed = Set(records.installedCopies.values)
        guard fontFiles.contains(where: installed.contains) else { return }
        fontFiles.removeAll(where: installed.contains)
    }
}

extension SidebarPreferences {
    /// The keys of the Tags and Folders sections, which making a tag or a folder shows again (the app's
    /// `SidebarSection.key`).
    public static let tagsSectionKey = "section.tags"
    public static let setsSectionKey = "section.sets"
}
