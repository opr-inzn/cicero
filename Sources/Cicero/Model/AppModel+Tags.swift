import CiceroCore

extension AppModel {
    func newTag(for families: [Family] = []) {
        newTagRequest = NewTagRequest(families: families, color: TagColor.next(after: data.tagColors.values))
    }

    func addTag(named name: String, color: TagColor?, to families: [Family] = []) {
        data.addTag(named: name, color: color, to: families.map(\.id))
    }

    func renameTag(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, data.tags.contains(old) else { return }
        guard !data.tags.contains(trimmed) else { return showToast("There’s already a tag called “\(trimmed)”") }
        data.renameTag(old, to: trimmed)
        if selectedItems.contains(.tag(old)) {
            selectSidebarItems(Set(selectedItems.map { $0 == .tag(old) ? .tag(trimmed) : $0 }))
        }
    }

    func deleteTags(_ names: Set<String>) {
        data.deleteTags(names)
        deselect { if case .tag(let name) = $0 { names.contains(name) } else { false } }
    }

    func setColor(_ color: TagColor?, forTags names: [String]) {
        for name in names { data.tagColors[name] = color }
    }

    func hasTag(_ tag: String, _ family: Family) -> Bool {
        data.familyTags[family.id]?.contains(tag) ?? false
    }

    func setTag(_ tag: String, _ isOn: Bool, for families: [Family]) {
        data.setTag(tag, isOn, for: families.map(\.id))
    }

    func removeTags(from families: [Family]) {
        var data = data
        for family in families { data.familyTags[family.id] = nil }
        self.data = data
    }

    func tagColors(of family: Family) -> [TagColor] {
        tagDots[family.id] ?? []
    }

    // MARK: Ratings

    func rating(of family: Family) -> Int? {
        data.familyRatings[family.id]
    }

    func setRating(_ stars: Int?, for families: [Family]) {
        let stars = stars.flatMap { (1...5).contains($0) ? $0 : nil }
        var data = data
        for family in families { data.familyRatings[family.id] = stars }
        self.data = data
    }

    func note(of family: Family) -> String? {
        data.familyNotes[family.id]
    }

    func setNote(_ note: String, for family: Family) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        guard data.familyNotes[family.id] != note else { return }
        data.familyNotes[family.id] = note
    }
}
