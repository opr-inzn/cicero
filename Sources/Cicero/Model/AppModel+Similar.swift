import CiceroCore
import Foundation

/// What `similarFonts` was made from.
struct SimilarKey: Equatable {
    var fingerprint: Int
    var measurementRevision: Int
    var dataRevision: Int
    var guessRevision: Int
}

extension AppModel {
    /// How many families Show Similar Fonts lists after the one they look like.
    static let similarListed = 30

    /// The listed families side by side by their letters and the letters' embedding, with their classifications as the
    /// sidebar has them. Made again when the library, its measurements or the user's data change, which takes a
    /// millisecond or two.
    var similarFonts: SimilarFonts {
        let key = SimilarKey(fingerprint: library.fingerprint, measurementRevision: measurementRevision, dataRevision: dataRevision,
                             guessRevision: guessRevision)
        if let cached = similarCache, cached.key == key { return cached.table }
        let measurements = measurements
        let classification = classificationNamer()
        let unclassified = data.classificationRenames[Classification.unclassified.rawValue] ?? Classification.unclassified.rawValue
        let table = SimilarFonts(families: library.families.filter(data.lists), measurements: { measurements.measurements(of: $0.regular.face.id) },
                                 embeddings: { measurements.embedding(of: $0.regular.face.id) },
                                 classification: { family in
                                     let name = classification(family)
                                     return name == unclassified ? nil : name
                                 })
        similarCache = (key, table)
        return table
    }

    /// The families that look most like this one, the closest first, without it.
    func similarFamilies(to family: Family, limit: Int) -> [Family] {
        similarFonts.nearest(to: family.id, limit: limit).compactMap(library.family)
    }

    /// Whether the family's letters are measured, so that there are similar fonts to show.
    func canShowSimilar(_ family: Family) -> Bool {
        similarFonts.contains(family.id)
    }

    /// Fills the browser with the family and the families that look most like it, the closest first, the way a
    /// search does: the sidebar shows nothing selected, and selecting an item there goes back to it.
    func showSimilar(to family: Family) {
        if similarFamilyID == nil { similarReturn = selectedItems }
        searchText = ""
        selection = nil
        similarFamilyID = family.id
        openFamilyID = nil
        selectedIDs = [family.id]
        jumpTargets = [family.id]
    }

    /// Back to what the sidebar had selected before, with the family selected there.
    func endSimilar() {
        guard let id = similarFamilyID else { return }
        let items = similarReturn ?? [.all]
        similarReturn = nil
        selectSidebarItems(items.isEmpty ? [.all] : items)
        if selection == nil { selection = .all }
        similarFamilyID = nil
        if visibleFamilies.contains(where: { $0.id == id }) {
            selectedIDs = [id]
            jumpTargets = [id]
        }
    }
}
