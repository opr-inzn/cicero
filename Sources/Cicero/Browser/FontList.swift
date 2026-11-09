import CiceroCore
import SwiftUI

nonisolated struct FontRow: Identifiable, Equatable, Sendable {
    private let box: FamilyBox
    var family: Family { box.family }
    let id: String
    let name: String
    let foundry: String
    let styles: Int
    let classification: String
    let format: String
    let activation: Int
    let coverage: [FontListColumn: CoverageCell]
    let added: Date
    let year: Int
    let rating: Int
    let tags: [TagColor]
    var position = 0
    let libraryPosition: Int


    subscript(rank column: FontListColumn) -> Int {
        switch coverage[column] {
        case .largest(_, let level): level
        case .missing(let missing, let total): total - missing
        case nil: -1
        }
    }

    struct Inputs {
        let library: Library
        let foundryName: (Family) -> String?
        let classificationName: (Family) -> String
        let ratings: [String: Int]
        let tagDots: [String: [TagColor]]

        @MainActor init(_ model: AppModel) {
            library = model.library
            foundryName = model.foundryNamer()
            classificationName = model.classificationNamer()
            ratings = model.data.familyRatings
            tagDots = model.tagDots
        }
    }

    @MainActor init(_ family: Family, coverage sources: [(FontListColumn, CoverageSource)], inputs: Inputs, model: AppModel) {
        box = FamilyBox(family)
        id = family.id
        name = family.name
        libraryPosition = inputs.library.position(of: family.id) ?? .max
        foundry = inputs.foundryName(family) ?? ""
        styles = family.faces.count
        classification = inputs.classificationName(family)
        format = family.format.rawValue
        activation = switch family.state {
        case .active, .system: 0
        case .partial: 1
        case .appOnly: 2
        case .inactive: 3
        }
        var coverage: [FontListColumn: CoverageCell] = [:]
        for (column, source) in sources {
            coverage[column] = Self.cell(source, for: family, model: model)
        }
        self.coverage = coverage
        added = family.dateAdded ?? .distantPast
        year = family.year ?? 0
        rating = inputs.ratings[family.id] ?? 0
        tags = inputs.tagDots[family.id] ?? []
    }

    @MainActor static func cell(_ source: CoverageSource, for family: Family, model: AppModel) -> CoverageCell? {
        switch source {
        case .series(let series):
            model.largestSet(in: series, for: family).map { .largest(label($0, in: series), level: $0.level) }
        case .set(let set):
            model.missingCount(set, family).flatMap { $0 < set.scalars.count ? .missing($0, of: set.scalars.count) : nil }
        }
    }

    private static func label(_ set: CharacterSetDefinition, in series: CharacterSetSeries) -> String {
        if series.id == CharacterSetCatalog.adobeSeriesID { return set.name.replacingOccurrences(of: "Adobe Latin", with: "AL") }
        return set.name.hasPrefix(series.name + " ") ? String(set.name.dropFirst(series.name.count + 1)) : set.name
    }
}

nonisolated final class FamilyBox: Equatable, Sendable {
    let family: Family

    init(_ family: Family) { self.family = family }

    static func == (lhs: FamilyBox, rhs: FamilyBox) -> Bool { lhs === rhs || lhs.family == rhs.family }
}

enum CoverageSource {
    case series(CharacterSetSeries)
    case set(CharacterSetDefinition)
}

nonisolated enum CoverageCell: Equatable, Sendable {
    case largest(String, level: Int)
    case missing(Int, of: Int)
}

nonisolated enum FontListColumn: Hashable, Identifiable, Sendable {
    case status, name, preview, styles, classification, foundry, year, rating, added, format
    case series(String)
    case characterSet(String)

    static let latin = FontListColumn.series(CharacterSetCatalog.latinSeriesID)
    static let adobe = FontListColumn.series(CharacterSetCatalog.adobeSeriesID)

    var id: String {
        switch self {
        case .status: "status"
        case .name: "name"
        case .preview: "preview"
        case .styles: "styles"
        case .classification: "classification"
        case .foundry: "foundry"
        case .year: "year"
        case .rating: "rating"
        case .added: "added"
        case .format: "format"
        case .series(CharacterSetCatalog.latinSeriesID): "latin"
        case .series(CharacterSetCatalog.adobeSeriesID): "adobe"
        case .series(let id): "series.\(id)"
        case .characterSet(let id): "set.\(id)"
        }
    }

    init?(id: String) {
        if let column = [Self.status, .name, .preview, .styles, .classification, .foundry, .year, .rating, .latin, .adobe, .added, .format].first(where: { $0.id == id }) {
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
        case .year: "Year"
        case .rating: "Rating"
        case .added: "Date Added"
        case .format: "Format"
        case .series(let id): model.characterSetSeries(id)?.name ?? ""
        case .characterSet(let id): model.characterSetName(id) ?? ""
        }
    }

    var defaultWidth: CGFloat? {
        switch self {
        case .status: 52
        case .name: 220
        case .preview: nil
        case .styles: 54
        case .classification: 110
        case .foundry: 150
        case .year: 56
        case .rating: 76
        case .series: 96
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
        case .styles, .year: 44
        case .rating: 60
        case .classification, .foundry, .added, .format: 80
        case .series, .characterSet: 60
        }
    }

    var canHide: Bool { ![.status, .name, .preview].contains(self) }

    var isSeries: Bool {
        if case .series = self { true } else { false }
    }

    var isSingleSet: Bool {
        if case .characterSet = self { true } else { false }
    }

    var isStandard: Bool {
        switch self {
        case .series(let id): id == CharacterSetCatalog.latinSeriesID || id == CharacterSetCatalog.adobeSeriesID
        case .year, .rating, .characterSet: false
        default: true
        }
    }

    var comparator: KeyPathComparator<FontRow>? {
        switch self {
        case .status: KeyPathComparator(\.activation)
        case .name: KeyPathComparator(\.libraryPosition)
        case .preview: nil
        case .styles: KeyPathComparator(\.styles)
        case .classification: KeyPathComparator(\.classification)
        case .foundry: KeyPathComparator(\.foundry, comparator: .localizedStandard)
        case .year: KeyPathComparator(\.year)
        case .rating: KeyPathComparator(\.rating)
        case .series, .characterSet: KeyPathComparator(\FontRow.[rank: self])
        case .added: KeyPathComparator(\.added)
        case .format: KeyPathComparator(\.format)
        }
    }
}

struct FontList: View {
    @Environment(AppModel.self) private var model
    @State private var sortColumn = FontListColumn.name
    @State private var ascending = true
    @State private var keepsOwnOrder = true
    @AppStorage("fontList.hiddenColumns") private var hiddenColumns = "added,format"
    @AppStorage("fontList.characterSetColumns") private var addedColumns = ""
    @AppStorage("fontList.columnWidths") private var columnWidths = ""
    @State private var anchor = SelectionAnchor()
    @State private var resizing: (column: FontListColumn, start: CGFloat, room: CGFloat)?
    @FocusState private var focused: Bool
    @State private var visibleWidth: CGFloat = 900
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        let columns = shownColumns
        let sort: FontListColumn? = model.hasOwnOrder && keepsOwnOrder ? nil : columns.contains(sortColumn) ? sortColumn : .name
        let sortsByCoverage = sort.map { $0.isSeries || $0.isSingleSet } ?? false
        let (rows, families) = model.fontRows(sortedBy: sort.map(order) ?? [], coverageColumns: sortsByCoverage ? sort.map { [$0] } ?? [] : [])
        let widths = Self.fit(columns, widths: self.widths, in: visibleWidth)
        ScrollViewReader { proxy in
            ScrollView {
                // A lazy stack, not a Table: a Table makes every row's cells whenever an accessibility client, like a password manager's autofill, walks the window.
                LazyVStack(spacing: 0) {
                    // The rows themselves, not Array(rows.enumerated()), which copied every row at each update.
                    ForEach(rows) { row in
                        FontListRow(row: row, columns: columns, widths: widths, isStriped: !row.position.isMultiple(of: 2),
                                    isSelected: model.selectedIDs.contains(row.id), model: model)
                            .modifier(FamilyItem(family: row.family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                            .onAppear { ReadAhead.around(row.family, in: families) }
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .topBar {
                header(columns: columns, widths: widths, sort: sort)
            }
            .hardTopScrollEdge()
            .visibleHeight($visibleHeight)
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy))
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                move(press.key == .downArrow ? 1 : -1, in: families, extending: press.modifiers.contains(.shift), proxy: proxy)
            }
        }
        .onChange(of: model.similarFamilyID) { keepsOwnOrder = true }
        .onChange(of: model.selectedItems) { keepsOwnOrder = true }
    }

    private func order(_ column: FontListColumn) -> [KeyPathComparator<FontRow>] {
        var comparator = column.comparator ?? KeyPathComparator(\FontRow.libraryPosition)
        comparator.order = ascending ? .forward : .reverse
        return [comparator]
    }

    private var allColumns: [FontListColumn] {
        let series = model.characterSetCatalog.series.map { FontListColumn.series($0.id) }
        let sets = singleSetGroups.flatMap(\.sets).map(\.id) + model.data.customCharacterSets.map(\.setID)
        return [.status, .name, .preview, .styles, .classification, .foundry, .year, .rating] + series + sets.map(FontListColumn.characterSet) + [.added, .format]
    }

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

    private func header(columns: [FontListColumn], widths: [FontListColumn: CGFloat], sort: FontListColumn?) -> some View {
        HStack(spacing: FontListRow.spacing) {
            ForEach(columns) { column in
                HeaderCell(column: column, title: column.title(model), sortColumn: sort, ascending: ascending,
                           resizeEdge: resizeEdge(column, in: columns)) {
                    if sort == column {
                        ascending.toggle()
                    } else {
                        sortColumn = column
                        ascending = true
                        keepsOwnOrder = false
                    }
                } resize: { change in
                    resize(column, by: change, widths: widths)
                } endResize: {
                    resizing = nil
                }
                .frame(width: widths[column], alignment: .leading)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, FontListRow.inset)
        .frame(width: visibleWidth, height: 28)
        .overlay(alignment: .bottom) { Divider() }
        .contextMenu {
            ForEach(allColumns.filter { $0.canHide && ![.added, .format].contains($0) && !$0.isSeries && !$0.isSingleSet }) { column in
                toggle(column)
            }
            Menu("Coverage") {
                ForEach(allColumns.filter(\.isSeries)) { column in
                    toggle(column)
                }
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
                if !model.data.customCharacterSets.isEmpty { Divider() }
                ForEach(model.data.customCharacterSets) { set in
                    toggle(.characterSet(set.setID))
                }
            }
            toggle(.added)
            toggle(.format)
        }
        // As wide as the bar, whatever the columns add up to: while a font page covers the list, its width isn't measured again, and columns wider than the bar would widen the whole stack, page included.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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

    private func resizeEdge(_ column: FontListColumn, in columns: [FontListColumn]) -> HorizontalEdge? {
        guard column != .status, column.defaultWidth != nil, let index = columns.firstIndex(of: column),
              let preview = columns.firstIndex(of: .preview) else { return nil }
        return index < preview ? .trailing : .leading
    }

    private func resize(_ column: FontListColumn, by change: CGFloat, widths: [FontListColumn: CGFloat]) {
        if resizing?.column != column {
            setWidths(widths)
            let room = (widths[.preview] ?? 0) - FontListColumn.preview.minimumWidth
            resizing = (column, widths[column] ?? column.minimumWidth, max(0, room))
        }
        guard let resizing else { return }
        setWidths([column: resizing.start + min(change, resizing.room)])
    }

    private func setWidths(_ widths: [FontListColumn: CGFloat]) {
        var saved = savedWidths
        for (column, width) in widths where column.defaultWidth != nil {
            saved[column] = max(column.minimumWidth, width.rounded())
        }
        let text = saved.compactMap { column, width in
            width == column.defaultWidth ? nil : "\(column.id):\(Int(width))"
        }.sorted().joined(separator: ",")
        if text != columnWidths { columnWidths = text }
    }

    private func move(_ step: Int, in families: [Family], extending: Bool, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = FamilySelection.step(step, in: families.map(\.id), selection: &model.selectedIDs, anchor: &anchor, extending: extending) else {
            return .ignored
        }
        proxy.scrollTo(target)
        return .handled
    }
}

private struct HeaderCell: View {
    let column: FontListColumn
    let title: String
    let sortColumn: FontListColumn?
    let ascending: Bool
    let resizeEdge: HorizontalEdge?
    let sort: () -> Void
    let resize: (CGFloat) -> Void
    let endResize: () -> Void

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
        .overlay(alignment: resizeEdge == .leading ? .leading : .trailing) {
            if let resizeEdge {
                // The drag is measured in the window, where it doesn't move with the edge.
                let gap = FontListRow.spacing
                Color.clear
                    .frame(width: gap)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .offset(x: resizeEdge == .leading ? -gap : gap)
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in resize(resizeEdge == .leading ? -drag.translation.width : drag.translation.width) }
                        .onEnded { _ in endResize() })
                    .accessibilityHidden(true)
            }
        }
    }
}

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
            ActivationSwitch(family: family, model: model).accessibilityHidden(true)
        case .name:
            HStack(spacing: 6) {
                Text(row.name).lineLimit(1)
                TagDots(colors: row.tags)
                StatusTag(family: family)
                VariableTag(family: family)
            }
        case .preview:
            let (style, weight) = model.previewStyle(of: family, weight: preview.weight)
            FontLine(
                text: model.scriptSamples.text(preview.text(for: family), for: style.face), face: style.face,
                size: 17, weight: weight, variations: model.variations(for: family, face: style.id), features: model.searchFeatures,
                height: 22
            )
        case .styles:
            Text(row.styles.plain).monospacedDigit().foregroundStyle(.secondary)
        case .classification:
            Text(row.classification).foregroundStyle(.secondary).lineLimit(1)
        case .foundry:
            Text(row.foundry).foregroundStyle(.secondary).lineLimit(1)
        case .year:
            if row.year > 0 {
                Text(String(row.year)).monospacedDigit().foregroundStyle(.secondary)
            }
        case .rating:
            if row.rating > 0 {
                Text(Rating.stars(row.rating)).foregroundStyle(.secondary).lineLimit(1).accessibilityLabel(Rating.description(row.rating))
            }
        case .series:
            if case .largest(let name, _) = model.coverageCell(column, of: row) {
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            }
        case .characterSet:
            switch model.coverageCell(column, of: row) {
            case .missing(0, _):
                Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Has all of \(column.title(model))")
            case .missing(let missing, _):
                Text("\(missing.plain) missing").foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel("\(missing.plain) missing from \(column.title(model))")
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
