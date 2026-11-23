import CiceroCore
import SwiftUI

extension AppModel {
    var shownSort: FontListColumn? { hasOwnOrder && keepsOwnOrder ? nil : sortColumn }

    func sort(by column: FontListColumn) {
        sortColumn = column
        sortsAscending = ![.added, .year, .rating, .styles].contains(column)
        keepsOwnOrder = false
    }

    func sortOrder(_ column: FontListColumn) -> [KeyPathComparator<FontRow>] {
        var comparator = column.comparator ?? KeyPathComparator(\FontRow.libraryPosition)
        comparator.order = sortsAscending ? .forward : .reverse
        return [comparator]
    }

    var sortedFamilies: [Family] {
        guard let column = shownSort, column != .name || !sortsAscending else { return visibleFamilies }
        let coverage = column.isSeries || column.isSingleSet ? [column] : []
        return fontRows(sortedBy: sortOrder(column), coverageColumns: coverage).families
    }
}

extension FontListColumn {
    static let sortable: [FontListColumn] = [.name, .added, .foundry, .year, .rating, .status, .styles]
}

struct FamilyGroup: Identifiable {
    let title: String?
    let families: ArraySlice<Family>

    var id: String { title ?? "" }

    static func groups(_ families: ArraySlice<Family>, sort: FontListColumn?) -> [FamilyGroup] {
        guard !families.isEmpty else { return [FamilyGroup(title: nil, families: families)] }
        switch sort {
        case .added: return grouped(families, by: dateTitle())
        case .year: return grouped(families) { family in
            guard let year = family.year else { return "Unknown Year" }
            return year >= 2010 ? String(year) : "\(year / 10 * 10)s"
        }
        default: return [FamilyGroup(title: nil, families: families)]
        }
    }

    private static func dateTitle() -> (Family) -> String {
        let calendar = Calendar.current, now = Date.now
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let year = calendar.component(.year, from: now)
        return { family in
            guard let date = family.dateAdded else { return "Unknown Date" }
            if date >= today { return "Today" }
            if date >= yesterday { return "Yesterday" }
            if date >= week { return "Previous 7 Days" }
            return calendar.component(.year, from: date) == year
                ? date.formatted(.dateTime.month(.wide))
                : date.formatted(.dateTime.month(.wide).year())
        }
    }

    private static func grouped(_ families: ArraySlice<Family>, by title: (Family) -> String) -> [FamilyGroup] {
        var groups: [FamilyGroup] = []
        var start = families.startIndex
        var current = title(families[start])
        for index in families.indices.dropFirst() {
            let next = title(families[index])
            if next != current {
                groups.append(FamilyGroup(title: current, families: families[start..<index]))
                start = index
                current = next
            }
        }
        groups.append(FamilyGroup(title: current, families: families[start...]))
        return groups
    }

    static func starts(_ groups: [FamilyGroup]) -> [Int] {
        guard let first = groups.first?.families.startIndex, groups.count > 1 else { return [] }
        return groups.map { $0.families.startIndex - first }
    }
}

struct FamilyGroupHeader: View {
    let group: FamilyGroup
    var isFirst = false
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        let count = group.families.count
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.title ?? "")
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(appearsActive ? 1 : 0.82))
                Text(count == 1 ? "1 family" : "\(count.plain) families")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)
        }
        .padding(.top, isFirst ? 8 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SortMenuItems: View {
    let model: AppModel

    var body: some View {
        Picker("Sort By", selection: Binding(get: { model.shownSort }, set: { if let column = $0 { model.sort(by: column) } })) {
            ForEach(FontListColumn.sortable) { column in
                Text(column.title(model)).tag(Optional(column))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Divider()
        let isDate = model.sortColumn == .added
        Picker("Order", selection: Binding(get: { model.sortsAscending }, set: { model.sortsAscending = $0 })) {
            Text(isDate ? "Oldest" : "Ascending").tag(true)
            Text(isDate ? "Newest" : "Descending").tag(false)
        }
        .pickerStyle(.inline)
        .labelsHidden()
        .disabled(model.shownSort == nil)
    }
}

struct SortButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("Sort By") { SortMenuItems(model: model) }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .toolbarButtonStyle()
        .menuIndicator(.hidden)
        .help("Sort the fonts")
    }
}
