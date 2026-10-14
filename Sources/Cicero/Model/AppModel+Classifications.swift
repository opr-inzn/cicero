import CiceroCore
import Foundation

/// Classifications: the one a family's fonts suggest, unless the user put it in another, the user's own among
/// them. Built-in ones keep their place under the names the user gave them.
extension AppModel {
    /// Every classification, for menus: the built-in ones under their names, then the user's.
    var classificationNames: [String] {
        Classification.allCases.map(name(of:)) + data.classifications
    }

    /// A built-in classification's name, as the user renamed it.
    func name(of classification: Classification) -> String {
        data.classificationRenames[classification.rawValue] ?? classification.rawValue
    }

    func classificationName(of family: Family) -> String {
        classificationNamer()(family)
    }

    /// `classificationName(of:)` for many families: the user's choices are read once, not for every family.
    func classificationNamer() -> (Family) -> String {
        let overrides = data.classificationOverrides
        let renames = data.classificationRenames
        return { family in
            overrides[family.id] ?? renames[family.classification.rawValue] ?? family.classification.rawValue
        }
    }

    func isUserClassification(_ name: String) -> Bool {
        data.classifications.contains(name)
    }

    /// The icon of a built-in classification, or of the user's.
    func classificationIcon(_ name: String) -> String {
        Classification.allCases.first { self.name(of: $0) == name }?.icon ?? "character"
    }

    /// Puts the families in the classification; nil takes them back to the one their fonts suggest.
    func setClassification(_ name: String?, for families: [Family]) {
        var data = data
        for family in families { data.classificationOverrides[family.id] = name }
        self.data = data
    }

    func newClassification(for families: [Family] = []) {
        prompt("New Classification", confirm: "Create") { self.addClassification(named: $0, to: families) }
    }

    /// Makes a classification and puts the families in it. A name that's taken puts them in that one.
    func addClassification(named name: String, to families: [Family] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var data = data
        if !classificationNames.contains(trimmed) {
            data.classifications.append(trimmed)
            data.sidebar.hidden.remove(SidebarSection.classifications.key)
        }
        for family in families { data.classificationOverrides[family.id] = trimmed }
        self.data = data
    }

    /// Renames one of the user's classifications, or gives a built-in one another name (its own name back
    /// undoes that). Families put in it, smart set rules and the sidebar follow.
    func renameClassification(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        guard !classificationNames.contains(trimmed) else { return showToast("There’s already a classification called “\(trimmed)”.") }
        var data = data
        if let index = data.classifications.firstIndex(of: old) {
            data.classifications[index] = trimmed
        } else if let builtIn = Classification.allCases.first(where: { name(of: $0) == old }) {
            data.classificationRenames[builtIn.rawValue] = trimmed == builtIn.rawValue ? nil : trimmed
        } else {
            return
        }
        for (family, name) in data.classificationOverrides where name == old { data.classificationOverrides[family] = trimmed }
        for set in data.smartSets.indices {
            for rule in data.smartSets[set].rules.indices
            where data.smartSets[set].rules[rule].field == .classification && data.smartSets[set].rules[rule].value == old {
                data.smartSets[set].rules[rule].value = trimmed
            }
        }
        data.sidebar.rename("classification.\(old)", to: "classification.\(trimmed)")
        self.data = data
        if selectedItems.contains(.classification(old)) {
            selectSidebarItems(Set(selectedItems.map { $0 == .classification(old) ? .classification(trimmed) : $0 }))
        }
    }

    /// Deletes one of the user's classifications: its families go back to the ones their fonts suggest, and
    /// smart set rules for it go.
    func deleteClassification(_ name: String) {
        guard isUserClassification(name) else { return }
        var data = data
        data.classifications.removeAll { $0 == name }
        data.classificationOverrides = data.classificationOverrides.filter { $0.value != name }
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .classification && $0.value == name }
        }
        data.sidebar.forget("classification.\(name)")
        self.data = data
        deselect { $0 == .classification(name) }
    }
}
