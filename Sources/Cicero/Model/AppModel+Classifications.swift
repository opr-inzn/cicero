import CiceroCore
import Foundation

typealias ClassificationGuessSource = ClassificationGuesses.Source

extension AppModel {
    var classificationNames: [String] { data.classificationNames }

    func name(of classification: Classification) -> String {
        data.name(of: classification)
    }

    func classificationName(of family: Family) -> String {
        classificationNamer()(family)
    }

    func classificationNamer() -> (Family) -> String {
        let guess = classificationGuess()
        return data.classificationNamer { guess($0)?.classification }
    }

    func suggestedClassification(of family: Family) -> Classification {
        guessedClassification(of: family)?.classification ?? family.classification
    }

    func guessedClassification(of family: Family) -> (classification: Classification, source: ClassificationGuessSource)? {
        classificationGuess()(family)
    }

    func classificationGuess() -> (Family) -> (classification: Classification, source: ClassificationGuessSource)? {
        ClassificationGuesses.rule(names: classificationGuesses, letters: letterGuesses, guessing: guessesClassifications)
    }

    func isUserClassification(_ name: String) -> Bool {
        data.classifications.contains(name)
    }

    func classificationIcon(_ name: String) -> String {
        Classification.allCases.first { self.name(of: $0) == name }?.icon ?? "character"
    }

    func setClassification(_ name: String?, for families: [Family]) {
        var data = data
        for family in families { data.classificationOverrides[family.id] = name }
        self.data = data
    }

    func newClassification(for families: [Family] = []) {
        prompt("New Classification", confirm: "Create") { self.addClassification(named: $0, to: families) }
    }

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

    func renameClassification(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        guard !classificationNames.contains(trimmed) else { return showToast("There’s already a classification called “\(trimmed)”") }
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

    func deleteClassifications(_ names: Set<String>) {
        let names = names.filter(isUserClassification)
        guard !names.isEmpty else { return }
        var data = data
        data.classifications.removeAll(where: names.contains)
        data.classificationOverrides = data.classificationOverrides.filter { !names.contains($0.value) }
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .classification && names.contains($0.value) }
        }
        for name in names { data.sidebar.forget("classification.\(name)") }
        self.data = data
        deselect { if case .classification(let name) = $0 { names.contains(name) } else { false } }
    }
}
