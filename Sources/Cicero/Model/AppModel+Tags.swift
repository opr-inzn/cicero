import CiceroCore

extension AppModel {
    /// Asks for a name and a colour, starting with the first colour no tag has, and makes a tag, given to `families`.
    func newTag(for families: [Family] = []) {
        newTagRequest = NewTagRequest(families: families, color: TagColor.next(after: data.tagColors.values))
    }

    /// Makes a tag in the colour (nil: none) and gives it to the families, which keep the ones they have. A name that's
    /// taken gives them that tag, in the colour it has.
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
        guard !data.tags.contains(trimmed) else { return showToast("There’s already a tag called “\(trimmed)”") }
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

    /// Takes the tags off every family, and out of smart set rules.
    func deleteTags(_ names: Set<String>) {
        var data = data
        data.tags.removeAll(where: names.contains)
        for (family, tags) in data.familyTags where tags.contains(where: names.contains) {
            let left = tags.filter { !names.contains($0) }
            data.familyTags[family] = left.isEmpty ? nil : left
        }
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .tag && names.contains($0.value) }
        }
        for name in names {
            data.tagColors[name] = nil
            data.sidebar.forget("tag.\(name)")
        }
        self.data = data
        deselect { if case .tag(let name) = $0 { names.contains(name) } else { false } }
    }

    func setColor(_ color: TagColor?, forTags names: [String]) {
        for name in names { data.tagColors[name] = color }
    }

    func hasTag(_ tag: String, _ family: Family) -> Bool {
        data.familyTags[family.id]?.contains(tag) ?? false
    }

    /// Gives the families the tag, or takes it off them; each keeps its other tags.
    func setTag(_ tag: String, _ isOn: Bool, for families: [Family]) {
        Self.setTag(tag, isOn, for: families, in: &data)
    }

    private static func setTag(_ tag: String, _ isOn: Bool, for families: [Family], in data: inout UserData) {
        for family in families {
            var tags = data.familyTags[family.id] ?? []
            if isOn, !tags.contains(tag) { tags.append(tag) }
            if !isOn { tags.removeAll { $0 == tag } }
            data.familyTags[family.id] = tags.isEmpty ? nil : tags
        }
    }

    /// Takes every tag off the families.
    func removeTags(from families: [Family]) {
        var data = data
        for family in families { data.familyTags[family.id] = nil }
        self.data = data
    }

    /// The colours of the family's tags, in the order the tags were made; one without a colour has no dot.
    func tagColors(of family: Family) -> [TagColor] {
        tagDots[family.id] ?? []
    }

    // MARK: Ratings

    /// The stars the user gave the family, 1…5; nil for none.
    func rating(of family: Family) -> Int? {
        data.familyRatings[family.id]
    }

    /// Gives the families this many stars, 1…5; nil takes their rating away.
    func setRating(_ stars: Int?, for families: [Family]) {
        let stars = stars.flatMap { (1...5).contains($0) ? $0 : nil }
        var data = data
        for family in families { data.familyRatings[family.id] = stars }
        self.data = data
    }

    func note(of family: Family) -> String? {
        data.familyNotes[family.id]
    }

    /// The family's note as written; nothing but spaces and new lines takes it away.
    func setNote(_ note: String, for family: Family) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        guard data.familyNotes[family.id] != note else { return }
        data.familyNotes[family.id] = note
    }
}
