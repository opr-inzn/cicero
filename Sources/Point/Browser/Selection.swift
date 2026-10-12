import AppKit
import PointCore
import SwiftUI

extension AppModel {
    /// Command toggles, Shift extends from the anchor, a plain click selects one.
    func click(_ family: Family, in families: [Family], anchor: inout String?) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedIDs.contains(family.id) { selectedIDs.remove(family.id) } else { selectedIDs.insert(family.id) }
            anchor = family.id
        } else if modifiers.contains(.shift), let start = anchor,
                  let a = families.firstIndex(where: { $0.id == start }),
                  let b = families.firstIndex(where: { $0.id == family.id }) {
            selectedIDs = Set(families[min(a, b)...max(a, b)].map(\.id))
        } else {
            selectedIDs = [family.id]
            anchor = family.id
        }
    }
}

/// Keyboard handling for the grid and specimens: Return opens, Escape deselects, ⌘A selects all,
/// typing a letter jumps to the first family starting with it.
struct FamilyKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let families: [Family]
    @Binding var anchor: String?
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return) {
                guard model.selectedIDs.count == 1 else { return .ignored }
                model.openFamilyID = model.selectedIDs.first
                return .handled
            }
            .onKeyPress(.escape) {
                model.selectedIDs = []
                return .handled
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    guard press.characters == "a" else { return .ignored }
                    model.selectedIDs = Set(families.map(\.id))
                    return .handled
                }
                guard press.modifiers.isEmpty || press.modifiers == .shift,
                      let target = families.first(where: { $0.name.lowercased().hasPrefix(press.characters.lowercased()) }) else {
                    return .ignored
                }
                model.selectedIDs = [target.id]
                anchor = target.id
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                return .handled
            }
    }
}

/// Clicking, double-clicking, dragging, the right-click menu and accessibility for one family's tile or row.
struct FamilyItem: ViewModifier {
    let family: Family
    let families: [Family]
    let model: AppModel
    @Binding var anchor: String?
    let focus: () -> Void

    func body(content: Content) -> some View {
        let isSelected = model.selectedIDs.contains(family.id)
        content
            .id(family.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) { model.openFamilyID = family.id }
            .simultaneousGesture(TapGesture().onEnded {
                focus()
                model.click(family, in: families, anchor: &anchor)
            })
            .contextMenu { FamilyMenu(families: model.targets(for: family), model: model) }
            .draggable(family.name)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.openFamilyID = family.id }
            .accessibilityAction(named: "Select") { model.click(family, in: families, anchor: &anchor) }
            .accessibilityAction(named: family.hasActive ? "Deactivate" : "Activate") { model.toggle(family) }
    }
}
