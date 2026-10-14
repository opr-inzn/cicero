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
    /// What each shown character set column says; nothing while the family is still being checked.
    let coverage: [FontListColumn: CoverageCell]
    let added: Date
    let tags: [TagColor]

    var id: String { family.id }

    /// A character set column's place to sort by: further along the series, or more of the set; −1 for none.
    subscript(rank column: FontListColumn) -> Int {
        switch coverage[column] {
        case .largest(_, let level): level
        case .missing(let missing, let total): total - missing
        case nil: -1
        }
    }

    @MainActor init(_ family: Family, coverage sources: [(FontListColumn, CoverageSource)], model: AppModel) {
        self.family = family
        name = family.name
        foundry = model.foundryName(of: family) ?? ""
        styles = family.faces.count
        classification = model.classificationName(of: family)
        format = family.format.rawValue
        activation = switch family.state {
        case .active, .system: 0
        case .partial: 1
        case .appOnly: 2
        case .inactive: 3
        }
        var coverage: [FontListColumn: CoverageCell] = [:]
        for (column, source) in sources {
            switch source {
            case .series(let series):
                if let set = model.largestSet(in: series, for: family) {
                    coverage[column] = .largest(Self.label(set, in: series), level: set.level)
                }
            case .set(let set):
                if let missing = model.missingCount(set, family), missing < set.scalars.count {
                    coverage[column] = .missing(missing, of: set.scalars.count)
                }
            }
        }
        self.coverage = coverage
        added = family.dateAdded ?? .distantPast
        tags = model.tagColors(of: family)
    }

    /// A set's name under its series' column: Latin M, AL 3, and Plus for GF Latin Plus.
    private static func label(_ set: CharacterSetDefinition, in series: CharacterSetSeries) -> String {
        if series.id == CharacterSetCatalog.adobeSeriesID { return set.name.replacingOccurrences(of: "Adobe Latin", with: "AL") }
        return set.name.hasPrefix(series.name + " ") ? String(set.name.dropFirst(series.name.count + 1)) : set.name
    }
}

/// What a character set column reads its rows from.
enum CoverageSource {
    case series(CharacterSetSeries)
    case set(CharacterSetDefinition)
}

/// What a character set column says about a family.
nonisolated enum CoverageCell: Sendable {
    /// The largest set of the series the family has, as the column names it, and its place in the series.
    case largest(String, level: Int)
    /// How many of the set's characters the family lacks, of how many; a family with none of them has no cell.
    case missing(Int, of: Int)
}

/// A column of the font list.
nonisolated enum FontListColumn: Hashable, Identifiable, Sendable {
    case status, name, preview, styles, classification, foundry, added, format
    /// The largest set of a series the family has.
    case series(String)
    /// Whether the family has every character of one set, else how many it lacks.
    case characterSet(String)

    static let latin = FontListColumn.series(CharacterSetCatalog.latinSeriesID)
    static let adobe = FontListColumn.series(CharacterSetCatalog.adobeSeriesID)

    /// What the list's settings call it. Latin S–XL and Adobe Latin keep the names they had before other
    /// series could be columns.
    var id: String {
        switch self {
        case .status: "status"
        case .name: "name"
        case .preview: "preview"
        case .styles: "styles"
        case .classification: "classification"
        case .foundry: "foundry"
        case .added: "added"
        case .format: "format"
        case .series(CharacterSetCatalog.latinSeriesID): "latin"
        case .series(CharacterSetCatalog.adobeSeriesID): "adobe"
        case .series(let id): "series.\(id)"
        case .characterSet(let id): "set.\(id)"
        }
    }

    init?(id: String) {
        if let column = [Self.status, .name, .preview, .styles, .classification, .foundry, .latin, .adobe, .added, .format].first(where: { $0.id == id }) {
            self = column
        } else if id.hasPrefix("series.") {
            self = .series(String(id.dropFirst(7)))
        } else if id.hasPrefix("set.") {
            self = .characterSet(String(id.dropFirst(4)))
        } else {
            return nil
        }
    }

    @MainActor func title(_ model: AppModel) -> String {
        switch self {
        case .status: "Status"
        case .name: "Name"
        case .preview: "Preview"
        case .styles: "Styles"
        case .classification: "Classification"
        case .foundry: "Foundry"
        case .added: "Date Added"
        case .format: "Format"
        case .series(let id): model.characterSetSeries(id)?.name ?? ""
        case .characterSet(let id): model.characterSetName(id) ?? ""
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
        case .series: 80
        case .characterSet: 110
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
        case .series, .characterSet: 60
        }
    }

    /// Status, name and preview are always shown.
    var canHide: Bool { ![.status, .name, .preview].contains(self) }

    var isSingleSet: Bool {
        if case .characterSet = self { true } else { false }
    }

    /// Shown unless hidden, where the other series and single sets are hidden unless added.
    var isStandard: Bool {
        switch self {
        case .series(let id): id == CharacterSetCatalog.latinSeriesID || id == CharacterSetCatalog.adobeSeriesID
        case .characterSet: false
        default: true
        }
    }

    var comparator: KeyPathComparator<FontRow>? {
        switch self {
        case .status: KeyPathComparator(\.activation)
        case .name: KeyPathComparator(\.name, comparator: .localizedStandard)
        case .preview: nil
        case .styles: KeyPathComparator(\.styles)
        case .classification: KeyPathComparator(\.classification)
        case .foundry: KeyPathComparator(\.foundry, comparator: .localizedStandard)
        case .series, .characterSet: KeyPathComparator(\FontRow.[rank: self])
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
    /// Standard columns turned off.
    @AppStorage("fontList.hiddenColumns") private var hiddenColumns = "added,format"
    /// Other series and single sets turned on.
    @AppStorage("fontList.characterSetColumns") private var addedColumns = ""
    @AppStorage("fontList.columnWidths") private var columnWidths = ""
    @State private var anchor: String?
    @FocusState private var focused: Bool
    /// The rows' width: the scroll view's, less what the sidebar and Info panel cover.
    @State private var visibleWidth: CGFloat = 900
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        let columns = shownColumns
        // A column that's been turned off, or whose set was deleted, no longer sorts the list.
        let sort = columns.contains(sortColumn) ? sortColumn : .name
        let rows = model.fontRows(sortedBy: order(sort), columns: columns)
        let families = rows.map(\.family)
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
                        header(columns: columns, widths: widths, sort: sort)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
                // The columns always add up to this width, so it never depends on them.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .visibleHeight($visibleHeight)
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

    private func order(_ column: FontListColumn) -> [KeyPathComparator<FontRow>] {
        var comparator = column.comparator ?? KeyPathComparator(\FontRow.name, comparator: .localizedStandard)
        comparator.order = ascending ? .forward : .reverse
        return [comparator]
    }

    /// Every column there is, in order: the series, then single sets (the user's last), between Foundry and Date Added.
    private var allColumns: [FontListColumn] {
        let series = model.characterSetCatalog.series.map { FontListColumn.series($0.id) }
        let sets = singleSetGroups.flatMap(\.sets).map(\.id) + model.data.customCharacterSets.map(\.setID)
        return [.status, .name, .preview, .styles, .classification, .foundry] + series + sets.map(FontListColumn.characterSet) + [.added, .format]
    }

    /// Built-in sets by group, less the ones in a series: its column says already.
    private var singleSetGroups: [(name: String, sets: [CharacterSetDefinition])] {
        let inSeries = Set(model.characterSetCatalog.series.flatMap(\.sets).map(\.id))
        return model.characterSetCatalog.groups
            .map { group in (group.name, group.sets.filter { !inSeries.contains($0.id) }) }
            .filter { !$0.sets.isEmpty }
    }

    private var shownColumns: [FontListColumn] {
        let hidden = Set(hiddenColumns.split(separator: ",").map(String.init))
        let added = Set(addedColumns.split(separator: ",").map(String.init))
        return allColumns.filter { column in
            if !column.canHide { return true }
            return column.isStandard ? !hidden.contains(column.id) : added.contains(column.id)
        }
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

    /// Saved widths ("name:240,set.unicode-arrows:120"), else the defaults.
    private var widths: [FontListColumn: CGFloat] {
        var widths: [FontListColumn: CGFloat] = [:]
        for column in allColumns { widths[column] = column.defaultWidth }
        for (column, width) in savedWidths where column.defaultWidth != nil {
            widths[column] = max(column.minimumWidth, width)
        }
        return widths
    }

    private var savedWidths: [FontListColumn: CGFloat] {
        var widths: [FontListColumn: CGFloat] = [:]
        for entry in columnWidths.split(separator: ",") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let column = FontListColumn(id: String(parts[0])), let width = Double(parts[1]) {
                widths[column] = width
            }
        }
        return widths
    }

    private func header(columns: [FontListColumn], widths: [FontListColumn: CGFloat], sort: FontListColumn) -> some View {
        HStack(spacing: FontListRow.spacing) {
            ForEach(columns) { column in
                HeaderCell(column: column, title: column.title(model), sortColumn: sort, ascending: ascending) {
                    if sort == column { ascending.toggle() } else { sortColumn = column; ascending = true }
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
            ForEach(allColumns.filter { $0.canHide && ![.added, .format].contains($0) && !$0.isSingleSet }) { column in
                toggle(column)
            }
            // The user's sets, then the built-in ones no series covers: a menu per group, unless it has just one.
            Menu("Coverage") {
                ForEach(model.data.customCharacterSets) { set in
                    toggle(.characterSet(set.setID))
                }
                if !model.data.customCharacterSets.isEmpty { Divider() }
                ForEach(singleSetGroups, id: \.name) { group in
                    if group.sets.count == 1 {
                        toggle(.characterSet(group.sets[0].id))
                    } else {
                        Menu(group.name) {
                            ForEach(group.sets) { set in
                                toggle(.characterSet(set.id))
                            }
                        }
                    }
                }
            }
            toggle(.added)
            toggle(.format)
        }
    }

    private func toggle(_ column: FontListColumn) -> some View {
        Toggle(column.title(model), isOn: Binding(
            get: { shownColumns.contains(column) },
            set: { setShown($0, column) }
        ))
    }

    private func setShown(_ shown: Bool, _ column: FontListColumn) {
        if column.isStandard {
            hiddenColumns = Self.updating(hiddenColumns, column, adding: !shown)
        } else {
            addedColumns = Self.updating(addedColumns, column, adding: shown)
        }
    }

    private static func updating(_ list: String, _ column: FontListColumn, adding: Bool) -> String {
        var ids = Set(list.split(separator: ",").map(String.init))
        if adding { ids.insert(column.id) } else { ids.remove(column.id) }
        return ids.sorted().joined(separator: ",")
    }

    private func setWidth(_ width: CGFloat, for column: FontListColumn) {
        var saved = savedWidths
        saved[column] = max(column.minimumWidth, width.rounded())
        columnWidths = saved.compactMap { column, width in
            width == column.defaultWidth ? nil : "\(column.id):\(Int(width))"
        }.sorted().joined(separator: ",")
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
    let title: String
    let sortColumn: FontListColumn
    let ascending: Bool
    let sort: () -> Void
    let resize: (CGFloat) -> Void
    @State private var startWidth: CGFloat?

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
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
                // In a stack, so a cell with nothing to say (no date, no set) still takes its width.
                ZStack(alignment: .leading) { cell(column) }.frame(width: widths[column], alignment: .leading)
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
                TagDots(colors: row.tags)
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
        case .series:
            if case .largest(let name, _) = row.coverage[column] {
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            }
        case .characterSet:
            switch row.coverage[column] {
            case .missing(0, _):
                Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Has all of \(column.title(model))")
            case .missing(let missing, _):
                Text("\(missing.formatted()) missing").foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel("\(missing.formatted()) missing from \(column.title(model))")
            default:
                EmptyView()
            }
        case .added:
            if row.added != .distantPast {
                Text(row.added, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary).lineLimit(1)
            }
        case .format:
            Text(row.format).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
