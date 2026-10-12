import SwiftUI

/// One row of the font table, with the sortable values precomputed.
struct FontRow: Identifiable {
    let family: FontFamily
    let name: String
    let foundry: String
    let styleCount: Int
    let classification: String
    let format: String
    /// Sorts activated families first, then partly activated, then the rest.
    let activationRank: Int
    /// The largest Latin S–XL and Adobe Latin sets the family has, ranked by size; -1 for none.
    let latinSize: String
    let latinSizeRank: Int
    let adobeLatin: String
    let adobeLatinRank: Int
    let dateAdded: Date

    var id: String { family.id }

    init(family: FontFamily, foundry: String?, latinSize: CharacterSetDefinition?, adobeLatin: CharacterSetDefinition?) {
        self.family = family
        name = family.name
        self.foundry = foundry ?? ""
        styleCount = family.faces.count
        classification = family.classification.rawValue
        format = family.format
        self.latinSize = latinSize?.name ?? ""
        latinSizeRank = latinSize?.level ?? -1
        self.adobeLatin = adobeLatin?.name ?? ""
        adobeLatinRank = adobeLatin?.level ?? -1
        dateAdded = family.dateAdded ?? .distantPast
        switch family.status {
        case .active, .system: activationRank = 0
        case .partial: activationRank = 1
        case .appOnly: activationRank = 2
        case .inactive: activationRank = 3
        }
    }
}

struct FontTable: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let families: [FontFamily]

    @State private var sortOrder = [KeyPathComparator(\FontRow.name, comparator: .localizedStandard)]
    @SceneStorage("FontTableColumns") private var columns: TableColumnCustomization<FontRow>

    var body: some View {
        @Bindable var library = library
        let rows = families.map {
            FontRow(
                family: $0, foundry: library.foundryName(of: $0),
                latinSize: library.largestCharacterSet(of: $0, inGroup: "koeberlin"),
                adobeLatin: library.largestCharacterSet(of: $0, inGroup: "adobe")
            )
        }
        .sorted(using: sortOrder)
        Table(rows, selection: $library.selectedFamilyIDs, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("On", value: \.activationRank) { row in
                ActivationSwitch(family: row.family, library: library)
            }
            .width(34)
            .customizationID("on")

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
                FontPreviewText(
                    text: preview.text(for: row.family),
                    face: row.family.face(nearestWeight: Int(preview.weight)).face,
                    size: 17, weight: preview.weight, features: library.features(for: row.family), kerning: preview.kerning(atSize: 17)
                )
            }
            .width(min: 160, ideal: 380)
            .customizationID("preview")

            TableColumn("Styles", value: \.styleCount) { row in
                Text(row.styleCount, format: .number).monospacedDigit().foregroundStyle(.secondary)
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

            TableColumn("Latin S–XL", value: \.latinSizeRank) { row in
                Text(row.latinSize).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            .customizationID("latinSize")

            TableColumn("Adobe Latin", value: \.adobeLatinRank) { row in
                Text(row.adobeLatin.replacingOccurrences(of: "Adobe Latin", with: "AL")).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            .customizationID("adobeLatin")

            TableColumn("Date Added", value: \.dateAdded) { row in
                if row.dateAdded != .distantPast {
                    Text(row.dateAdded, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 100)
            .customizationID("added")
            .defaultVisibility(.hidden)

            TableColumn("Format", value: \.format) { row in
                Text(row.format).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 150)
            .customizationID("format")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            FontActionsMenu(families: library.families(withIDs: ids))
        } primaryAction: { ids in
            if ids.count == 1 { library.detailFamilyID = ids.first }
        }
        .onKeyPress(.return) {
            guard library.selectedFamilyIDs.count == 1 else { return .ignored }
            library.detailFamilyID = library.selectedFamilyIDs.first
            return .handled
        }
        // A new list reloads the table instead of diffing it: inserting a thousand rows makes the
        // table measure every one of them, which takes minutes with live font previews.
        .id(TableIdentity(selection: library.sidebarSelection, search: library.appliedSearch))
    }
}

private struct TableIdentity: Hashable {
    var selection: SidebarSelection?
    var search: String
}
