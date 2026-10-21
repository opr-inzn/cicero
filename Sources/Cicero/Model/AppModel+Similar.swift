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
    static let similarListed = SimilarFonts.longestList

    /// The listed families side by side by their letters and the letters' embedding, with their classifications as the
    /// sidebar has them. Made again when the library, its measurements or the user's data change, which takes a
    /// millisecond or two.
    var similarFonts: SimilarFonts {
        let key = SimilarKey(fingerprint: library.fingerprint, measurementRevision: measurementRevision, dataRevision: dataRevision,
                             guessRevision: guessRevision)
        if let cached = similarCache, cached.key == key { return cached.table }
        let measurements = measurements
        let table = SimilarFonts(families: library.families.filter(data.lists), measurements: { measurements.measurements(of: $0.regular.face.id) },
                                 embeddings: { measurements.embedding(of: $0.regular.face.id) },
                                 classification: similarClassifier(), notSimilar: data.notSimilar)
        similarCache = (key, table)
        return table
    }

    /// A family's classification as the sidebar has it, for similar fonts; nil for Unclassified.
    private func similarClassifier() -> (Family) -> String? {
        let classification = classificationNamer()
        let unclassified = data.classificationRenames[Classification.unclassified.rawValue] ?? Classification.unclassified.rawValue
        return { family in
            let name = classification(family)
            return name == unclassified ? nil : name
        }
    }

    /// The families that look most like this one, the closest first, without it.
    func similarFamilies(to family: Family, limit: Int) -> [Family] {
        similarFonts.nearest(to: family.id, limit: limit).compactMap(library.family)
    }

    /// Leaves the families out of this one's similar fonts, and it out of theirs, as the user says they don't look like
    /// it; another takes each one's place. Kept in the user's data, and, while usage statistics are on, reported to improve
    /// similar fonts, with the list as it was (see `SimilarReports`), once the toast's Undo has passed, so a mark undone is
    /// never sent.
    func markNotSimilar(_ others: [Family], to family: Family) {
        let marked = data.notSimilar[family.id] ?? []
        let added = others.map(\.id).filter { $0 != family.id && !marked.contains($0) }
        guard !added.isEmpty else { return }
        let report = similarReport(for: family, notSimilar: added)
        data.notSimilar[family.id] = marked + added
        // Out of the list, they're out of the selection too.
        if similarFamilyID == family.id { selectedIDs.subtract(added) }
        let sending = report.map { report in
            Task {
                try? await Task.sleep(for: Self.undoTime)
                if !Task.isCancelled { SimilarReports.send(report) }
            }
        }
        let what = added.count == 1 ? library.family(added[0])?.name ?? added[0] : "\(added.count) families"
        showToast("\(what) marked not similar to \(family.name)") { [weak self] in
            sending?.cancel()
            guard let self else { return }
            let left = (data.notSimilar[family.id] ?? []).filter { !added.contains($0) }
            data.notSimilar[family.id] = left.isEmpty ? nil : left
        }
    }

    /// The report of these families from the family's list as it is, before they leave it; nil while usage statistics are off.
    private func similarReport(for family: Family, notSimilar: [String]) -> SimilarReport? {
        let measurements = measurements, classification = similarClassifier()
        func entry(_ family: Family, distance: Float?) -> SimilarReport.Entry {
            let face = family.regular.face
            return SimilarReport.Entry(name: family.id, style: face.postScriptName, foundry: foundryName(of: family),
                                       classification: classification(family), measurements: measurements.measurements(of: face.id),
                                       embedding: measurements.embedding(of: face.id), distance: distance)
        }
        let list = similarFonts.nearestWithDistances(to: family.id, limit: Self.similarListed).compactMap { nearest in
            library.family(nearest.id).map { entry($0, distance: nearest.distance) }
        }
        // A font page over Show Similar Fonts is the page's.
        let place: SimilarReport.Place = similarFamilyID == family.id && openFamilyID == nil ? .browser : .page
        return SimilarReports.report(family: entry(family, distance: nil), notSimilar: notSimilar, list: list, shownIn: place)
    }

    /// Whether the family's letters are measured, so that there are similar fonts to show.
    func canShowSimilar(_ family: Family) -> Bool {
        similarFonts.contains(family.id)
    }

    /// Fills the browser with the family and the families that look most like it, the closest first, the way a
    /// search does: the sidebar shows nothing selected, and selecting an item there goes back to it.
    func showSimilar(to family: Family) {
        if similarFamilyID == nil {
            similarReturn = selectedItems
            similarReturnPage = openFamilyID
        }
        searchText = ""
        selection = nil
        similarFamilyID = family.id
        openFamilyID = nil
        selectedIDs = [family.id]
        jumpTargets = [family.id]
    }

    /// Back to what the sidebar had selected before, with the family selected there, and to the font page it was
    /// asked for from, if any.
    func endSimilar() {
        guard let id = similarFamilyID else { return }
        let items = similarReturn ?? [.all]
        let page = similarReturnPage
        similarReturn = nil
        similarReturnPage = nil
        selectSidebarItems(items.isEmpty ? [.all] : items)
        if selection == nil { selection = .all }
        similarFamilyID = nil
        if visibleFamilies.contains(where: { $0.id == id }) {
            selectedIDs = [id]
            jumpTargets = [id]
        }
        if let page, library.family(page) != nil { openFamilyID = page }
    }
}
