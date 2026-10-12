import Foundation

/// What the Compare and Slideshow windows show. Lives in the store so the windows can be reopened
/// and so a new selection replaces the old one.
struct PresentationState: Sendable {
    var compareIDs: [String] = []
    var slideshowIDs: [String] = []
    var slideshowStart = 0
    /// Bumped whenever Slideshow is chosen, so an open slideshow starts over.
    var slideshowRun = 0
}

extension LibraryStore {
    func prepareCompare(_ families: [FontFamily]) {
        presentation.compareIDs = families.map(\.id)
    }

    /// Adds dropped family names to the comparison; false when none of them is a family.
    func addToCompare(_ names: [String]) -> Bool {
        let ids = names.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { family(named: $0) != nil && !presentation.compareIDs.contains($0) }
        guard !ids.isEmpty else { return false }
        presentation.compareIDs += ids
        return true
    }

    func removeFromCompare(_ id: String) {
        presentation.compareIDs.removeAll { $0 == id }
    }

    /// Shows the given families, or the whole current list when fewer than two are given,
    /// starting at the single given family.
    func prepareSlideshow(_ families: [FontFamily]) {
        let list = families.count >= 2 ? families : visibleFamilies
        presentation.slideshowIDs = list.map(\.id)
        presentation.slideshowStart = families.count == 1 ? (list.firstIndex { $0.id == families[0].id } ?? 0) : 0
        presentation.slideshowRun += 1
    }
}
