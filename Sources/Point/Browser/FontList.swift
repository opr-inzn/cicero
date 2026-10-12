import PointCore
import SwiftUI

/// One row of the font list, with its sortable values worked out up front.
nonisolated struct FontRow: Identifiable, Sendable {
    let family: Family
    let name: String
    let foundry: String
    let styles: Int
    let classification: String
    let format: String
    /// Activated, then partly, then app-only, then off.
    let activation: Int
    /// The largest Latin S–XL and Adobe Latin sets the family has, by size; −1 for none.
    let latin: String
    let latinRank: Int
    let adobe: String
    let adobeRank: Int
    let added: Date

    var id: String { family.id }

    @MainActor init(_ family: Family, model: AppModel) {
        self.family = family
        name = family.name
        foundry = model.foundryName(of: family) ?? ""
        styles = family.faces.count
        classification = family.classification.rawValue
        format = family.format.rawValue
        activation = switch family.state {
        case .active, .system: 0
        case .partial: 1
        case .appOnly: 2
        case .inactive: 3
        }
        let latinSet = model.largestSet(in: CharacterSetCatalog.latinSeriesID, for: family)
        latin = latinSet?.name ?? ""
        latinRank = latinSet?.level ?? -1
        let adobeSet = model.largestSet(in: CharacterSetCatalog.adobeSeriesID, for: family)
        adobe = adobeSet.map { $0.name.replacingOccurrences(of: "Adobe Latin", with: "AL") } ?? ""
        adobeRank = adobeSet?.level ?? -1
        added = family.dateAdded ?? .distantPast
    }
}

/// The families as a sortable table with an on/off switch and a preview per row.
struct FontList: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let families: [Family]
    @State private var sortOrder = [KeyPathComparator(\FontRow.name, comparator: .localizedStandard)]
    @SceneStorage("FontListColumns") private var columns: TableColumnCustomization<FontRow>

    var body: some View {
        @Bindable var bindable = model
        let model = self.model
        let rows = families.map { FontRow($0, model: model) }.sorted(using: sortOrder)
        Table(rows, selection: $bindable.selectedIDs, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Status", value: \.activation) { row in
                ActivationSwitch(family: row.family, model: model)
            }
            .width(min: 52, ideal: 56, max: 64)
            .customizationID("status")

            TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(1)
                    StatusTag(family: row.family)
                }
                .draggable(row.name)
            }
            .width(min: 140, ideal: 220)
            .customizationID("name")

            TableColumn("Preview") { row in
                FontText(
                    text: preview.text(for: row.family), face: row.family.face(nearestWeight: preview.weight).face,
                    size: 17, weight: preview.weight, features: model.features(for: row.family), kerning: preview.kerning(at: 17)
                )
            }
            .width(min: 160, ideal: 380)
            .customizationID("preview")

            TableColumn("Styles", value: \.styles) { row in
                Text(row.styles, format: .number).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 44, ideal: 54, max: 70)
            .customizationID("styles")

            TableColumn("Classification", value: \.classification) { row in
                Text(row.classification).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
            .customizationID("classification")

            TableColumn("Foundry", value: \.foundry, comparator: .localizedStandard) { row in
                Text(row.foundry).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 150)
            .customizationID("foundry")

            TableColumn("Latin S–XL", value: \.latinRank) { row in
                Text(row.latin).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            .customizationID("latin")

            TableColumn("Adobe Latin", value: \.adobeRank) { row in
                Text(row.adobe).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            .customizationID("adobe")

            TableColumn("Date Added", value: \.added) { row in
                if row.added != .distantPast {
                    Text(row.added, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 100)
            .customizationID("added")
            .defaultVisibility(.hidden)

            TableColumn("Format", value: \.format) { row in
                Text(row.format).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 140)
            .customizationID("format")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            FamilyMenu(families: ids.compactMap(model.family), model: model)
        } primaryAction: { ids in
            if ids.count == 1 { model.openFamilyID = ids.first }
        }
        .onKeyPress(.return) {
            guard model.selectedIDs.count == 1 else { return .ignored }
            model.openFamilyID = model.selectedIDs.first
            return .handled
        }
        // A new list replaces the table instead of being diffed into it: inserting many rows makes
        // the table measure every one of them.
        .id(ListIdentity(selection: model.selection, search: model.appliedSearch))
    }
}

private struct ListIdentity: Hashable {
    var selection: SidebarItem?
    var search: String
}
