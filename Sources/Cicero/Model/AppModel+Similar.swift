import CiceroCore
import Foundation

struct SimilarKey: Equatable {
    var fingerprint: Int
    var measurementRevision: Int
    var dataRevision: Int
    var guessRevision: Int
}

extension AppModel {
    static let similarListed = SimilarFonts.longestList

    var similarFonts: SimilarFonts {
        let key = SimilarKey(fingerprint: library.fingerprint, measurementRevision: measurementRevision, dataRevision: dataRevision,
                             guessRevision: guessRevision)
        if let cached = similarCache, cached.key == key { return cached.table }
        let measurements = measurements
        let table = SimilarFonts(families: library.families.filter(data.lists), measurements: { measurements.measurements(of: $0.regular.face.id) },
                                 embeddings: { measurements.embedding(of: $0.regular.face.id) },
                                 italicMeasurements: { $0.italic.flatMap { measurements.measurements(of: $0.face.id) } },
                                 italicEmbeddings: { $0.italic.flatMap { measurements.embedding(of: $0.face.id) } },
                                 classification: similarClassifier())
        similarCache = (key, table)
        return table
    }

    private func similarClassifier() -> (Family) -> String? {
        let classification = classificationNamer()
        let unclassified = data.classificationRenames[Classification.unclassified.rawValue] ?? Classification.unclassified.rawValue
        return { family in
            let name = classification(family)
            return name == unclassified ? nil : name
        }
    }

    func similarFamilies(to family: Family, limit: Int) -> [Family] {
        similarFonts.nearest(to: family.id, limit: limit).compactMap(library.family)
    }

    func canShowSimilar(_ family: Family) -> Bool {
        similarFonts.contains(family.id)
    }

    func showSimilar(to family: Family) {
        if similarFamilyID == nil, documentList == nil {
            listReturn = selectedItems
            listReturnPage = openFamilyID
        }
        clearSearch()
        selection = nil
        documentList = nil
        similarFamilyID = family.id
        openFamilyID = nil
        selectedIDs = [family.id]
        jumpTargets = [family.id]
    }

    func endSimilar() {
        guard let id = similarFamilyID else { return }
        returnFromList()
        if visibleFamilies.contains(where: { $0.id == id }) {
            selectedIDs = [id]
            jumpTargets = [id]
        }
    }

    func returnFromList() {
        let items = listReturn ?? [.all]
        let page = listReturnPage
        listReturn = nil
        listReturnPage = nil
        selectSidebarItems(items.isEmpty ? [.all] : items)
        if selection == nil { selection = .all }
        similarFamilyID = nil
        documentList = nil
        if let page, library.family(page) != nil { openFamilyID = page }
    }
}
