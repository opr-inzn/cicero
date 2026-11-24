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
    public mutating func addSet(named name: String, parentID: UUID? = nil, families: [String] = [], styles: [String: [String]] = [:]) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parent = parentID.flatMap { id in sets.contains { $0.id == id } ? id : nil }
        let set = FontSet(name: trimmed, parentID: parent, families: families, styles: styles)
        sets.append(set)
        sidebar.hidden.remove(SidebarPreferences.setsSectionKey)
        if let parent { sidebar.collapsed.remove("set.\(parent)") }
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

    public func descendants(ofSet id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        while let current = queue.popLast() {
            for set in sets where set.parentID == current && result.insert(set.id).inserted {
                queue.append(set.id)
            }
        }
        return result
    }

    public func subtreeSets(of id: UUID) -> [FontSet] {
        var ids = descendants(ofSet: id)
        ids.insert(id)
        return sets.filter { ids.contains($0.id) }
    }

    public func subtreeSmartSets(of id: UUID) -> Set<UUID> {
        var parents = descendants(ofSet: id)
        parents.insert(id)
        return Set(smartSets.filter { $0.parentID.map(parents.contains) == true }.map(\.id))
    }

    public func members(ofSet id: UUID) -> (families: Set<String>, styles: [String: Set<String>]) {
        var families = Set<String>()
        var styles: [String: Set<String>] = [:]
        for set in subtreeSets(of: id) {
            families.formUnion(set.families)
            for (family, names) in set.styles where !names.isEmpty {
                styles[family, default: []].formUnion(names)
            }
        }
        for family in families { styles[family] = nil }
        return (families.union(styles.keys), styles)
    }

    public func contains(style: String, of family: String, inSetSubtree id: UUID) -> Bool {
        subtreeSets(of: id).contains { $0.contains(style: style, of: family) }
    }

    public func ancestorIDs(ofSet id: UUID) -> [UUID] {
        var byID: [UUID: FontSet] = [:]
        for set in sets { byID[set.id] = set }
        var chain: [UUID] = []
        var seen: Set<UUID> = [id]
        var current = byID[id]?.parentID
        while let parent = current, seen.insert(parent).inserted, let node = byID[parent] {
            chain.insert(parent, at: 0)
            current = node.parentID
        }
        return chain
    }

    public func path(ofSet id: UUID) -> String {
        guard let set = sets.first(where: { $0.id == id }) else { return "" }
        let byID = Dictionary(sets.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let names = ancestorIDs(ofSet: id).compactMap { byID[$0] } + [set.name]
        return names.joined(separator: " / ")
    }

    public func path(ofSmartSet id: UUID) -> String {
        guard let smart = smartSets.first(where: { $0.id == id }) else { return "" }
        guard let parentID = smart.parentID else { return smart.name }
        let prefix = path(ofSet: parentID)
        return prefix.isEmpty ? smart.name : "\(prefix) / \(smart.name)"
    }

    public func canMove(set id: UUID, into parentID: UUID?) -> Bool {
        guard let parentID else { return true }
        guard parentID != id, sets.contains(where: { $0.id == parentID }) else { return false }
        return !descendants(ofSet: id).contains(parentID)
    }

    public mutating func moveSets(_ ids: Set<UUID>, to parentID: UUID?) {
        if let parentID, !sets.contains(where: { $0.id == parentID }) { return }
        for index in sets.indices where ids.contains(sets[index].id) && canMove(set: sets[index].id, into: parentID) {
            sets[index].parentID = parentID
        }
        if let parentID { sidebar.collapsed.remove("set.\(parentID)") }
    }

    public mutating func moveSmartSets(_ ids: Set<UUID>, to parentID: UUID?) {
        if let parentID, !sets.contains(where: { $0.id == parentID }) { return }
        for index in smartSets.indices where ids.contains(smartSets[index].id) {
            smartSets[index].parentID = parentID
        }
        if let parentID { sidebar.collapsed.remove("set.\(parentID)") }
    }

    public mutating func deleteSets(_ ids: Set<UUID>) {
        var allSets = ids
        var allSmartSets = Set<UUID>()
        for id in ids {
            allSets.formUnion(descendants(ofSet: id))
            allSmartSets.formUnion(subtreeSmartSets(of: id))
        }
        let values = Set(allSets.map(\.uuidString))
        sets.removeAll { allSets.contains($0.id) }
        smartSets.removeAll { allSmartSets.contains($0.id) }
        for id in allSets { sidebar.forget("set.\(id)") }
        for id in allSmartSets { sidebar.forget("smartset.\(id)") }
        for index in smartSets.indices {
            smartSets[index].rules.removeAll { $0.field == .set && values.contains($0.value) }
        }
    }

    public mutating func repairHierarchy() {
        let valid = Set(sets.map(\.id))
        for index in sets.indices {
            if let parent = sets[index].parentID, !valid.contains(parent) || parent == sets[index].id {
                sets[index].parentID = nil
            }
        }
        for index in sets.indices {
            var seen: Set<UUID> = [sets[index].id]
            var current = sets[index].parentID
            while let parent = current {
                if !seen.insert(parent).inserted {
                    sets[index].parentID = nil
                    break
                }
                current = sets.first { $0.id == parent }?.parentID
            }
        }
        for index in smartSets.indices {
            if let parent = smartSets[index].parentID, !valid.contains(parent) {
                smartSets[index].parentID = nil
            }
        }
    }

    // MARK: Locations

    public func showsSubfolders(for folder: WatchedFolder) -> Bool {
        if let explicit = folder.showsSubfolders { return explicit }
        if folder.id == WatchedFolder.fontLibraryID || folder.id == WatchedFolder.adobeAppsID
            || folder.id == WatchedFolder.adobeFontsID || folder.id == WatchedFolder.addedFilesID
            || folder.id == WatchedFolder.inactiveFolderID {
            return false
        }
        return folder.id != fontLibraryLocation?.id
    }

    public mutating func absorbNestedFolders() {
        guard folders.count > 1 else { return }
        let libraryID = fontLibraryLocation?.id
        var removed = Set<UUID>()
        let indices = folders.indices.sorted { folders[$0].path.count < folders[$1].path.count }
        for outerIndex in indices {
            let outer = folders[outerIndex]
            guard !removed.contains(outer.id), outer.id != libraryID else { continue }
            for inner in folders where inner.id != outer.id && inner.id != libraryID && !removed.contains(inner.id) {
                guard let rel = FolderPath.relativePath(of: inner.url, inside: outer.url) else { continue }
                absorb(inner, into: outerIndex, relativePath: rel)
                removed.insert(inner.id)
            }
        }
        guard !removed.isEmpty else { return }
        folders.removeAll { removed.contains($0.id) }
        for id in removed {
            folderNames[id.uuidString] = nil
            sidebar.forget("folder.\(id)")
        }
    }

    public mutating func absorb(_ inner: WatchedFolder, into outerIndex: Int, relativePath rel: String) {
        let outerID = folders[outerIndex].id
        let inherited = folders[outerIndex].policy(forSubfolder: rel)
        if inner.isActive != inherited.isActive || inner.appName != inherited.appName {
            folders[outerIndex].subfolders[rel] = FolderPolicy(isActive: inner.isActive, appName: inner.appName, fileID: FolderPath.fileID(of: inner.path))
        }
        for (subRel, policy) in inner.subfolders {
            let combined = "\(rel)/\(subRel)"
            if folders[outerIndex].subfolders[combined] == nil {
                folders[outerIndex].subfolders[combined] = policy
            }
        }
        let innerPrefix = inner.id.uuidString + "/"
        let innerExact = inner.id.uuidString
        for setIndex in smartSets.indices {
            for ruleIndex in smartSets[setIndex].rules.indices where smartSets[setIndex].rules[ruleIndex].field == .folder {
                let value = smartSets[setIndex].rules[ruleIndex].value
                if value == innerExact {
                    smartSets[setIndex].rules[ruleIndex].value = "\(outerID.uuidString)/\(rel)"
                } else if value.hasPrefix(innerPrefix) {
                    let tail = value.dropFirst(innerPrefix.count)
                    smartSets[setIndex].rules[ruleIndex].value = "\(outerID.uuidString)/\(rel)/\(tail)"
                }
            }
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
