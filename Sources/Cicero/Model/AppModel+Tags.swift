import CiceroCore

extension AppModel {
    /// Asks for a name and a colour, starting with the first colour no tag has, and makes a tag, given to `families`.
    func newTag(for families: [Family] = []) {
        newTagRequest = NewTagRequest(families: families, color: TagColor.next(after: data.tagColors.values))
    }

    /// Makes a tag in the colour (nil: none) and gives it to the families. A name that's taken gives them
    /// that tag, in the colour it has.
    func addTag(named name: String, color: TagColor?, to families: [Family] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var data = data
        if !data.tags.contains(trimmed) {
            data.tags.append(trimmed)
            data.tagColors[trimmed] = color
            data.sidebar.hidden.remove(SidebarSection.tags.key)
        }
        Self.setTag(trimmed, true, for: families, in: &data)
        self.data = data
    }

    func renameTag(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, let index = data.tags.firstIndex(of: old) else { return }
        guard !data.tags.contains(trimmed) else { return showToast("There’s already a tag called “\(trimmed)”.") }
        var data = data
        data.tags[index] = trimmed
        let color = data.tagColors.removeValue(forKey: old)
        data.tagColors[trimmed] = color
        for (family, tags) in data.familyTags where tags.contains(old) {
            data.familyTags[family] = tags.map { $0 == old ? trimmed : $0 }
        }
        for set in data.smartSets.indices {
            for rule in data.smartSets[set].rules.indices
            where data.smartSets[set].rules[rule].field == .tag && data.smartSets[set].rules[rule].value == old {
                data.smartSets[set].rules[rule].value = trimmed
            }
        }
        data.sidebar.rename("tag.\(old)", to: "tag.\(trimmed)")
        self.data = data
        if selectedItems.contains(.tag(old)) {
            selectSidebarItems(Set(selectedItems.map { $0 == .tag(old) ? .tag(trimmed) : $0 }))
        }
    }

    /// Takes the tag off every family, and out of smart set rules.
    func deleteTag(_ name: String) {
        var data = data
        data.tags.removeAll { $0 == name }
        data.tagColors[name] = nil
        for (family, tags) in data.familyTags where tags.contains(name) {
            let left = tags.filter { $0 != name }
            data.familyTags[family] = left.isEmpty ? nil : left
        }
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .tag && $0.value == name }
        }
        data.sidebar.forget("tag.\(name)")
        self.data = data
        deselect { $0 == .tag(name) }
    }

    func setColor(_ color: TagColor?, forTag name: String) {
        data.tagColors[name] = color
    }

    func hasTag(_ tag: String, _ family: Family) -> Bool {
        data.familyTags[family.id]?.contains(tag) ?? false
    }

    func setTag(_ tag: String, _ on: Bool, for families: [Family]) {
        Self.setTag(tag, on, for: families, in: &data)
    }

    private static func setTag(_ tag: String, _ on: Bool, for families: [Family], in data: inout UserData) {
        for family in families {
            var tags = data.familyTags[family.id] ?? []
            if on, !tags.contains(tag) { tags.append(tag) }
            if !on { tags.removeAll { $0 == tag } }
            data.familyTags[family.id] = tags.isEmpty ? nil : tags
        }
    }

    /// The colours of the family's tags, in the order the tags were made; tags without a colour have no dot.
    func tagColors(of family: Family) -> [TagColor] {
        tagDots[family.id] ?? []
    }
}
