import AppKit
import CiceroCore
import SwiftUI

extension AppModel {
    func click(_ family: Family, in families: [Family], anchor: inout String?) {
        FamilySelection.click(family.id, in: families.map(\.id), selection: &selectedIDs, anchor: &anchor)
    }
}

/// How clicks and arrow keys select in every list of families, the browser's and the Character Toolbox's.
enum FamilySelection {
    /// Command toggles, Shift extends from the anchor, a plain click selects one.
    static func click(_ id: String, in ids: [String], selection: inout Set<String>, anchor: inout String?) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if modifiers.contains(.shift), let start = anchor,
                  let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: id) {
            selection = Set(ids[min(a, b)...max(a, b)])
        } else {
            selection = [id]
            anchor = id
        }
    }

    /// ↑ and ↓ move the selection a row, Shift extending it from the anchor. Returns the row to scroll to.
    static func step(_ step: Int, in ids: [String], selection: inout Set<String>, anchor: inout String?, extending: Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        let first = ids.firstIndex { selection.contains($0) }
        let current: Int?
        if extending, let start = anchor, selection.contains(start), let a = ids.firstIndex(of: start), let first {
            // The end of the selection away from the anchor moves, so Shift grows and shrinks it either way.
            current = first < a ? first : ids.lastIndex { selection.contains($0) }
        } else {
            current = ids.lastIndex { selection.contains($0) && (extending || $0 != anchor) } ?? first
        }
        let index = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        if extending, let start = anchor, let a = ids.firstIndex(of: start) {
            selection = Set(ids[min(a, index)...max(a, index)])
        } else {
            selection = [ids[index]]
            anchor = ids[index]
        }
        return ids[index]
    }
}

/// How a browser view lays out its families, which decides what the arrow keys do.
enum FamilyLayout {
    /// Rows under column headers: the list moves the selection with ↑/↓ itself; ←/→ go through the families Quick Look shows.
    case list
    /// ↑/↓ move the selection; ←/→ go through the families Quick Look shows.
    case specimens
    /// Rows of tiles: ←/→ move the selection a tile, ↑/↓ a row.
    case grid(columns: Int)
}

/// Keyboard handling for the browser: Return opens, Escape deselects, ⌘A selects all, typing a letter jumps
/// to the first family starting with it, Space opens and closes Quick Look, and the arrow keys as the layout has them.
struct FamilyKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let families: [Family]
    @Binding var anchor: String?
    let proxy: ScrollViewProxy
    var layout = FamilyLayout.list

    func body(content: Content) -> some View {
        let quickLook = model.quickLook
        content
            .onKeyPress(.return) {
                // With Quick Look open, the family it shows, which may be one of several selected.
                if quickLook.isOpen, let shown = quickLook.shown {
                    model.openFamilyID = shown.family.id
                    return .handled
                }
                guard model.selectedIDs.count == 1 else { return .ignored }
                model.openFamilyID = model.selectedIDs.first
                return .handled
            }
            .onKeyPress(.escape) {
                // Quick Look closes before the selection clears.
                if quickLook.isOpen { quickLook.close() } else { model.selectedIDs = [] }
                return .handled
            }
            .onKeyPress(.space, phases: [.down, .repeat]) { press in
                guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
                // Holding the bar down opens or closes it once.
                if press.phase == .down { quickLook.toggle(order: families.map(\.id)) }
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { arrow($0) }
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
            // Opened from the menu, or open while the view changes: several families go in the order this view shows them.
            .onChange(of: quickLook.isOpen, initial: true) { _, isOpen in
                if isOpen { quickLook.updateOrder(families.map(\.id)) }
            }
    }

    private func arrow(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let vertical = press.key == .upArrow || press.key == .downArrow
        let forward = press.key == .downArrow || press.key == .rightArrow
        var step = 1
        switch layout {
        case .grid(let columns):
            if vertical { step = columns }
        case .list, .specimens:
            guard vertical else {
                // As in Finder's list view: through the selected families, while the selection stays.
                guard model.quickLook.isOpen, !press.modifiers.contains(.shift) else { return .ignored }
                model.quickLook.updateOrder(families.map(\.id))
                return model.quickLook.step(forward ? 1 : -1) ? .handled : .ignored
            }
            // The list moves the selection with ↑/↓ itself.
            if case .list = layout { return .ignored }
        }
        guard let target = FamilySelection.step(forward ? step : -step, in: families.map(\.id), selection: &model.selectedIDs,
                                                anchor: &anchor, extending: press.modifiers.contains(.shift)) else {
            return .ignored
        }
        proxy.scrollTo(target)
        return .handled
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
