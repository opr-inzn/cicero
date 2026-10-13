import CiceroCore
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

/// A column of the font list.
enum FontListColumn: String, CaseIterable, Identifiable {
    case status, name, preview, styles, classification, foundry, latin, adobe, added, format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .name: "Name"
        case .preview: "Preview"
        case .styles: "Styles"
        case .classification: "Classification"
        case .foundry: "Foundry"
        case .latin: "Latin S–XL"
        case .adobe: "Adobe Latin"
        case .added: "Date Added"
        case .format: "Format"
        }
    }

    /// nil for the preview, which takes the room the others leave.
    var defaultWidth: CGFloat? {
        switch self {
        case .status: 52
        case .name: 220
        case .preview: nil
        case .styles: 54
        case .classification: 110
        case .foundry: 150
        case .latin, .adobe: 80
        case .added: 100
        case .format: 140
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .status: 52
        case .name: 140
        case .preview: 160
        case .styles: 44
        case .classification, .foundry, .added, .format: 80
        case .latin, .adobe: 60
        }
    }

    /// Status, name and preview are always shown.
    var canHide: Bool { ![.status, .name, .preview].contains(self) }

    var comparator: KeyPathComparator<FontRow>? {
        switch self {
        case .status: KeyPathComparator(\.activation)
        case .name: KeyPathComparator(\.name, comparator: .localizedStandard)
        case .preview: nil
        case .styles: KeyPathComparator(\.styles)
        case .classification: KeyPathComparator(\.classification)
        case .foundry: KeyPathComparator(\.foundry, comparator: .localizedStandard)
        case .latin: KeyPathComparator(\.latinRank)
        case .adobe: KeyPathComparator(\.adobeRank)
        case .added: KeyPathComparator(\.added)
        case .format: KeyPathComparator(\.format)
        }
    }
}

/// The visible families as rows under sortable column headers, with an on/off switch and a preview per
/// row. A lazy stack like the grid's rather than a Table: a Table makes every row's cells whenever an
/// accessibility client (a password manager's autofill, say) walks the window, and with a thousand
/// families that kept the app busy for minutes each time it came to the front.
struct FontList: View {
    @Environment(AppModel.self) private var model
    @State private var sortColumn = FontListColumn.name
    @State private var ascending = true
    @AppStorage("fontList.hiddenColumns") private var hiddenColumns = "added,format"
    @AppStorage("fontList.columnWidths") private var columnWidths = ""
    @State private var anchor: String?
    @FocusState private var focused: Bool
    /// The rows' width: the scroll view's, less what the sidebar and Info panel cover.
    @State private var visibleWidth: CGFloat = 900

    var body: some View {
        let rows = model.fontRows(sortedBy: order)
        let families = rows.map(\.family)
        let columns = shownColumns
        let widths = Self.fit(columns, widths: self.widths, in: visibleWidth)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            FontListRow(row: row, columns: columns, widths: widths, isStriped: !index.isMultiple(of: 2),
                                        isSelected: model.selectedIDs.contains(row.id), model: model)
                                .modifier(FamilyItem(family: row.family, families: families, model: model, anchor: $anchor) { focused = true })
                        }
                    } header: {
                        header(columns: columns, widths: widths)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
                // The columns always add up to this width, so it never depends on them.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            }
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(families: families, anchor: $anchor, proxy: proxy))
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                move(press.key == .downArrow ? 1 : -1, in: families, extending: press.modifiers.contains(.shift), proxy: proxy)
            }
        }
    }

    private var order: [KeyPathComparator<FontRow>] {
        var comparator = sortColumn.comparator ?? KeyPathComparator(\FontRow.name, comparator: .localizedStandard)
        comparator.order = ascending ? .forward : .reverse
        return [comparator]
    }

    private var shownColumns: [FontListColumn] {
        let hidden = Set(hiddenColumns.split(separator: ",").map(String.init))
        return FontListColumn.allCases.filter { !$0.canHide || !hidden.contains($0.rawValue) }
    }

    /// Every shown column's width in the room there is: the preview takes what the others leave; when that's
    /// less than its minimum, the others give way down to theirs, and past that every column shrinks alike.
    static func fit(_ columns: [FontListColumn], widths: [FontListColumn: CGFloat], in visible: CGFloat) -> [FontListColumn: CGFloat] {
        let room = visible - 2 * FontListRow.inset - FontListRow.spacing * CGFloat(columns.count - 1)
        let minimums = columns.reduce(0) { $0 + $1.minimumWidth }
        if room <= minimums {
            let scale = max(0, room) / minimums
            return Dictionary(uniqueKeysWithValues: columns.map { ($0, ($0.minimumWidth * scale).rounded(.down)) })
        }
        let fixed = columns.filter { $0.defaultWidth != nil }
        let ideal = fixed.reduce(0) { $0 + (widths[$1] ?? 0) }
        let slack = fixed.reduce(0) { $0 + max(0, (widths[$1] ?? 0) - $1.minimumWidth) }
        let preview = FontListColumn.preview.minimumWidth
        let ratio = slack > 0 ? min(1, max(0, ideal + preview - room) / slack) : 0
        var result: [FontListColumn: CGFloat] = [:]
        for column in fixed {
            let width = widths[column] ?? column.minimumWidth
            result[column] = (width - (width - column.minimumWidth) * ratio).rounded()
        }
        result[.preview] = max(preview, room - fixed.reduce(0) { $0 + (result[$1] ?? 0) })
        return result
    }

    /// Saved widths ("name:240,foundry:180"), else the defaults.
    private var widths: [FontListColumn: CGFloat] {
        var widths: [FontListColumn: CGFloat] = [:]
        for column in FontListColumn.allCases { widths[column] = column.defaultWidth }
        for entry in columnWidths.split(separator: ",") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let column = FontListColumn(rawValue: String(parts[0])), let width = Double(parts[1]), column.defaultWidth != nil {
                widths[column] = max(column.minimumWidth, width)
            }
        }
        return widths
    }

    private func header(columns: [FontListColumn], widths: [FontListColumn: CGFloat]) -> some View {
        HStack(spacing: FontListRow.spacing) {
            ForEach(columns) { column in
                HeaderCell(column: column, sortColumn: sortColumn, ascending: ascending) {
                    if sortColumn == column { ascending.toggle() } else { sortColumn = column; ascending = true }
                } resize: { width in
                    setWidth(width, for: column)
                }
                .frame(width: widths[column], alignment: .leading)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, FontListRow.inset)
        .frame(height: 28)
        .background(Color.canvas)
        .overlay(alignment: .bottom) { Divider() }
        .contextMenu {
            ForEach(FontListColumn.allCases.filter(\.canHide)) { column in
                Toggle(column.title, isOn: Binding(
                    get: { shownColumns.contains(column) },
                    set: { setHidden(!$0, column) }
                ))
            }
        }
    }

    private func setHidden(_ hidden: Bool, _ column: FontListColumn) {
        var set = Set(hiddenColumns.split(separator: ",").map(String.init))
        if hidden { set.insert(column.rawValue) } else { set.remove(column.rawValue) }
        hiddenColumns = set.sorted().joined(separator: ",")
    }

    private func setWidth(_ width: CGFloat, for column: FontListColumn) {
        var saved = widths
        saved[column] = max(column.minimumWidth, width.rounded())
        columnWidths = FontListColumn.allCases.compactMap { column in
            guard let width = saved[column], width != column.defaultWidth else { return nil }
            return "\(column.rawValue):\(Int(width))"
        }.joined(separator: ",")
    }

    private func move(_ step: Int, in families: [Family], extending: Bool, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = FamilySelection.step(step, in: families.map(\.id), selection: &model.selectedIDs, anchor: &anchor, extending: extending) else {
            return .ignored
        }
        proxy.scrollTo(target)
        return .handled
    }
}

/// A column title: click to sort by it (again to reverse); drag its right edge to resize it.
private struct HeaderCell: View {
    let column: FontListColumn
    let sortColumn: FontListColumn
    let ascending: Bool
    let sort: () -> Void
    let resize: (CGFloat) -> Void
    @State private var startWidth: CGFloat?

    var body: some View {
        HStack(spacing: 4) {
            Text(column.title).lineLimit(1)
            if column == sortColumn {
                Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { if column.comparator != nil { sort() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if column.comparator != nil { sort() } }
        .overlay(alignment: .trailing) {
            if column.defaultWidth != nil {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        .frame(width: 8)
                        .frame(maxHeight: .infinity)
                        .offset(x: geometry.size.width - 2)
                        .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                            let start = startWidth ?? geometry.size.width
                            startWidth = start
                            resize(start + drag.translation.width)
                        }.onEnded { _ in startWidth = nil })
                        .onHover { inside in if inside { NSCursor.columnResize.push() } else { NSCursor.pop() } }
                }
                .frame(width: 8)
                .accessibilityHidden(true)
            }
        }
    }
}

/// One family's row: every shown column's value, the preview set in the font.
private struct FontListRow: View {
    @Environment(PreviewSettings.self) private var preview
    let row: FontRow
    let columns: [FontListColumn]
    let widths: [FontListColumn: CGFloat]
    let isStriped: Bool
    let isSelected: Bool
    let model: AppModel

    static let spacing: CGFloat = 12
    static let inset: CGFloat = 12

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(columns) { column in
                cell(column).frame(width: widths[column], alignment: .leading)
            }
        }
        .padding(.horizontal, Self.inset)
        .frame(height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)).padding(.horizontal, 4)
            } else if isStriped {
                Rectangle().fill(.quaternary.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func cell(_ column: FontListColumn) -> some View {
        let family = row.family
        switch column {
        case .status:
            // The row offers Activate/Deactivate to accessibility already.
            ActivationSwitch(family: family, model: model).accessibilityHidden(true)
        case .name:
            HStack(spacing: 6) {
                Text(row.name).lineLimit(1)
                StatusTag(family: family)
            }
        case .preview:
            FontText(
                text: preview.text(for: family), face: family.face(nearestWeight: preview.weight).face,
                size: 17, weight: preview.weight, features: model.features(for: family), kerning: preview.kerning(at: 17)
            )
            // Every row the same height, however tall the font's glyphs.
            .frame(height: 22)
            .clipped()
        case .styles:
            Text(row.styles, format: .number).monospacedDigit().foregroundStyle(.secondary)
        case .classification:
            Text(row.classification).foregroundStyle(.secondary).lineLimit(1)
        case .foundry:
            Text(row.foundry).foregroundStyle(.secondary).lineLimit(1)
        case .latin:
            Text(row.latin).foregroundStyle(.secondary).lineLimit(1)
        case .adobe:
            Text(row.adobe).foregroundStyle(.secondary).lineLimit(1)
        case .added:
            if row.added != .distantPast {
                Text(row.added, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary).lineLimit(1)
            }
        case .format:
            Text(row.format).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
