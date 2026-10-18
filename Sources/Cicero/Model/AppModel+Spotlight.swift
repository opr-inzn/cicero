import CiceroCore
import Foundation

/// Cicero in Spotlight: an item for every family the library lists, with what Cicero knows of it (see
/// `SpotlightEntry`), kept up to date a moment after the library or the user's data changes, and a family's page
/// opened when one is chosen in Spotlight. The index stays on this Mac.
extension AppModel {
    /// Gathers changes for a moment, as when tagging families one after another, then updates the items that changed.
    func updateSpotlight(after delay: Duration = .seconds(2)) {
        guard indexesSpotlight, hasScanned else { return }
        spotlightTask?.cancel()
        let previous = spotlightTask
        spotlightTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            let entries = self.spotlightEntries()
            try? await self.spotlight.update(entries)
        }
    }

    func removeFromSpotlight() {
        spotlightTask?.cancel()
        let previous = spotlightTask
        spotlightTask = Task(priority: .utility) { [spotlight] in
            await previous?.value
            try? await spotlight.removeAll()
        }
    }

    /// Every listed family as the browser shows it: classification and foundry under the user's names, its tags,
    /// rating, and the sets and smart sets it's in.
    func spotlightEntries() -> [SpotlightEntry] {
        let families = library.families.filter(data.lists)
        let foundryName = foundryNamer()
        let classificationName = classificationNamer()
        let unclassified = name(of: .unclassified)
        var sets: [String: [String]] = [:]
        for set in data.sets {
            for family in set.memberFamilies { sets[family, default: []].append(set.name) }
        }
        var smartSets: [String: [String]] = [:]
        for set in data.smartSets {
            let test = matcher(for: set)
            for family in families where test(family) { smartSets[family.id, default: []].append(set.name) }
        }
        return families.map { family in
            let classification = classificationName(family)
            return SpotlightEntry(
                family: family, classification: classification == unclassified ? nil : classification, foundry: foundryName(family),
                tags: data.tags(of: family.id), rating: data.familyRatings[family.id], sets: sets[family.id] ?? [],
                smartSets: smartSets[family.id] ?? []
            )
        }
    }

    /// Opens the page of a family chosen in Spotlight, in the list the browser shows when it has the family, else in
    /// All Fonts. One the library no longer lists leaves Spotlight.
    func show(familyFromSpotlight name: String) {
        guard let family = library.family(name), data.lists(family) else {
            if !hasScanned { return awaitedSpotlightFamily = name }
            showToast("“\(name)” is no longer in your library")
            return updateSpotlight(after: .zero)
        }
        if !visibleFamilies.contains(where: { $0.id == name }) {
            searchText = ""
            selection = .all
        }
        selectedIDs = [name]
        openFamilyID = name
    }
}
