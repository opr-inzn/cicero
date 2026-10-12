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

    var id: String { family.id }

    init(family: FontFamily, foundry: String?) {
        self.family = family
        name = family.name
        self.foundry = foundry ?? ""
        styleCount = family.faces.count
        classification = family.classification.rawValue
        format = family.format
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
        let rows = families.map { FontRow(family: $0, foundry: library.foundryName(of: $0)) }.sorted(using: sortOrder)
        Table(rows, selection: $library.selectedFamilyIDs, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("On", value: \.activationRank) { row in
                ActivationSwitch(family: row.family)
            }
            .width(34)
            .customizationID("on")

            TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(1)
                    StatusTag(status: row.family.status)
                }
                .draggable(row.name)
            }
            .width(min: 140, ideal: 220)
            .customizationID("name")

            TableColumn("Preview") { row in
                FontPreviewText(
                    text: preview.text(for: row.family),
                    face: row.family.face(nearestWeight: Int(preview.weight)).face,
                    size: 17, weight: preview.weight, kerning: preview.kerning(atSize: 17)
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
    }
}
