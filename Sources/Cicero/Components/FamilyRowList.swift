import CiceroCore
import SwiftUI

struct FamilyRowSection: Identifiable {
    var id: String
    var title: String?
    var families: [Family]
    var emptyText: String?
}

struct FamilyRowList<Row: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let sections: [FamilyRowSection]
    @Binding var selection: Set<String>
    @ViewBuilder let row: (Family) -> Row
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool

    var body: some View {
        let ids = sections.flatMap { $0.families.map(\.id) }
        ScrollViewReader { proxy in
            ScrollView {
                // A lazy stack, not a Table or List: those make every row whenever an accessibility client walks the window.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Section {
                            if section.families.isEmpty, let empty = section.emptyText {
                                Text(empty).foregroundStyle(.tertiary).padding(.horizontal, ListRowBackground.contentInset).frame(height: 30)
                            }
                            let families = section.families
                            ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                                item(family, isStriped: !index.isMultiple(of: 2), ids: ids,
                                     previous: index > 0 ? families[index - 1].id : nil,
                                     next: index + 1 < families.count ? families[index + 1].id : nil)
                            }
                        } header: {
                            if let title = section.title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, ListRowBackground.contentInset)
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
                let shown = selection.filter(ids.contains)
                guard shown.count == 1, let id = shown.first else { return .ignored }
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

    private func open(_ id: String) {
        model.openFamilyID = id
        openWindow(id: WindowID.main)
    }

    private func item(_ family: Family, isStriped: Bool, ids: [String], previous: String?, next: String?) -> some View {
        let isSelected = selection.contains(family.id)
        return row(family)
            .padding(.horizontal, ListRowBackground.contentInset)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                ListRowBackground(isSelected: isSelected, isStriped: isStriped,
                                  joinsAbove: isSelected && (previous.map(selection.contains) ?? false),
                                  joinsBelow: isSelected && (next.map(selection.contains) ?? false))
            }
            .id(family.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) { open(family.id) }
            .simultaneousGesture(TapGesture().onEnded {
                focused = true
                FamilySelection.click(family.id, in: ids, selection: &selection, anchor: &anchor)
            })
            .contextMenu { FamilyMenu(families: targets(for: family.id, in: ids).compactMap(model.family), model: model) }
            .familyDrag { targets(for: family.id, in: ids).compactMap(model.family) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { open(family.id) }
            .accessibilityAction(named: "Select") { FamilySelection.click(family.id, in: ids, selection: &selection, anchor: &anchor) }
    }

    private func targets(for id: String, in ids: [String]) -> [String] {
        selection.contains(id) && selection.count > 1 ? ids.filter(selection.contains) : [id]
    }
}

struct ListRowBackground: View {
    let isSelected: Bool
    let isStriped: Bool
    let joinsAbove: Bool
    let joinsBelow: Bool

    static let inset: CGFloat = 10
    static let contentInset: CGFloat = 20

    var body: some View {
        if isSelected {
            UnevenRoundedRectangle(topLeadingRadius: joinsAbove ? 0 : 6, bottomLeadingRadius: joinsBelow ? 0 : 6,
                                   bottomTrailingRadius: joinsBelow ? 0 : 6, topTrailingRadius: joinsAbove ? 0 : 6)
                .fill(Color.accentColor.opacity(0.25))
                .overlay(alignment: .top) {
                    if joinsAbove {
                        Rectangle().fill(Color.selectionSeparator).frame(height: 1).padding(.horizontal, Self.contentInset - Self.inset)
                    }
                }
                .padding(.horizontal, Self.inset)
        } else if isStriped {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35)).padding(.horizontal, Self.inset)
        }
    }
}
