import CiceroCore
import Foundation

struct SimilarKey: Equatable {
    var fingerprint: Int
    var measurementRevision: Int
    var dataRevision: Int
    var guessRevision: Int
}

extension AppModel {
    var similarFonts: SimilarFonts {
        let key = SimilarKey(fingerprint: library.fingerprint, measurementRevision: measurementRevision, dataRevision: dataRevision,
                             guessRevision: guessRevision)
        if let cached = similarCache, cached.key == key { return cached.table }
        let measurements = measurements
        let table = SimilarFonts(families: library.families.filter(data.lists), measurements: { measurements.measurements(of: $0.regular.face.id) },
                                 embeddings: { measurements.embedding(of: $0.regular.face.id) },
                                 styleMeasurements: { measurements.measurements(of: $0.id) },
                                 styleEmbeddings: { measurements.embedding(of: $0.id) },
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

    func similarFamilies(to family: Family, kind: SearchQuery.Style?, limit: Int) -> [Family] {
        var table = similarFonts
        if !table.contains(family.id, kind: kind), covers(family, kind: kind) {
            similarCache = nil
            table = similarFonts
        }
        return table.nearest(to: family.id, kind: kind, limit: limit).compactMap(library.family)
    }

    func canShowSimilar(_ family: Family, style: LibraryFace?) -> Bool {
        _ = measurementRevision
        return covers(family, kind: style.map(family.kind(of:)))
    }

    private func covers(_ family: Family, kind: SearchQuery.Style?) -> Bool {
        guard let listed = library.family(family.id), data.lists(listed) else { return false }
        let measurements = measurements
        return SimilarFonts.covers(listed, kind: kind,
                                   measurements: { measurements.measurements(of: $0.regular.face.id) },
                                   embeddings: { measurements.embedding(of: $0.regular.face.id) },
                                   styleMeasurements: { measurements.measurements(of: $0.id) },
                                   styleEmbeddings: { measurements.embedding(of: $0.id) })
    }

    func shownStyle(of family: Family) -> LibraryFace? {
        let chosen = openFamilyID == family.id && pageStyleID != nil
        let searched = family.namesStyle(SearchQuery(appliedSearch), tokens: searchTokens)
        guard chosen || searched || similarStyle != nil else { return nil }
        let face = previewStyle(of: family).face
        return face.id == family.regular.id ? nil : face
    }

    var similarStyle: LibraryFace? {
        guard let id = similarStyleID, let family = similarFamilyID.flatMap(library.family) else { return nil }
        return family.faces.first { $0.id == id }
    }

    var similarName: String? {
        guard let id = similarFamilyID else { return nil }
        let name = library.family(id)?.name ?? id
        return similarStyle.map { "\(name) \($0.face.styleName)" } ?? name
    }

    func showSimilar(to family: Family, style: LibraryFace?) {
        if similarFamilyID == nil, documentList == nil {
            listReturn = selectedItems
            listReturnPage = openFamilyID
        }
        clearSearch()
        selection = nil
        documentList = nil
        similarFamilyID = family.id
        similarStyleID = style?.id
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

    private func isInSidebar(_ item: SidebarItem) -> Bool {
        libraryRows.contains { $0.item == item } || SidebarSection.allCases.contains { rows(for: $0).contains { $0.item == item } }
    }

    func returnFromList() {
        let items = (listReturn ?? [.all]).filter(isInSidebar)
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
