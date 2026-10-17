import CiceroCore
import SwiftUI

/// A titled group of families in a `FamilyRowList`.
struct FamilyRowSection: Identifiable {
    var id: String
    var title: String?
    var families: [Family]
    /// Shown when there are no families.
    var emptyText: String?
}

/// Families as rows with a selection of their own, for the Character Toolbox: click, ⌘- and ⇧-click and
/// the arrow keys select, double-click or Return opens, right-click for the family menu. A lazy stack, not
/// a Table or List: those make every row whenever an accessibility client walks the window, which keeps
/// the app busy for minutes with a thousand families. Section titles scroll with the rows rather than pin, so rows
/// only meet the bar above them, where they fade out (see `safeAreaBar`) instead of ending at a title's edge.
struct FamilyRowList<Row: View>: View {
    @Environment(AppModel.self) private var model
    let sections: [FamilyRowSection]
    @Binding var selection: Set<String>
    let open: (String) -> Void
    @ViewBuilder let row: (Family) -> Row
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool

    var body: some View {
        let ids = sections.flatMap { $0.families.map(\.id) }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Section {
                            if section.families.isEmpty, let empty = section.emptyText {
                                Text(empty).foregroundStyle(.tertiary).padding(.horizontal, 12).frame(height: 30)
                            }
                            ForEach(Array(section.families.enumerated()), id: \.element.id) { index, family in
                                item(family, isStriped: !index.isMultiple(of: 2), ids: ids)
                            }
                        } header: {
                            if let title = section.title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.return) {
                guard selection.count == 1, let id = selection.first else { return .ignored }
                open(id)
                return .handled
            }
            .onKeyPress(.escape) {
                selection = []
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard let target = FamilySelection.step(press.key == .downArrow ? 1 : -1, in: ids, selection: &selection,
                                                        anchor: &anchor, extending: press.modifiers.contains(.shift)) else { return .ignored }
                proxy.scrollTo(target)
                return .handled
            }
        }
    }

    private func item(_ family: Family, isStriped: Bool, ids: [String]) -> some View {
        let isSelected = selection.contains(family.id)
        return row(family)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)).padding(.horizontal, 4)
                } else if isStriped {
                    Rectangle().fill(.quaternary.opacity(0.35))
                }
            }
            .id(family.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) { open(family.id) }
            .simultaneousGesture(TapGesture().onEnded {
                focused = true
                FamilySelection.click(family.id, in: ids, selection: &selection, anchor: &anchor)
            })
            .contextMenu {
                let targets = selection.contains(family.id) && selection.count > 1 ? ids.filter(selection.contains) : [family.id]
                FamilyMenu(families: targets.compactMap(model.family), model: model)
            }
            .draggable(family.name)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { open(family.id) }
            .accessibilityAction(named: "Select") { FamilySelection.click(family.id, in: ids, selection: &selection, anchor: &anchor) }
    }
}
