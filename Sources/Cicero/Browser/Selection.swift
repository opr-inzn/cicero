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

/// Clicking between families, or below the last, deselects them as Escape does, as in the Finder. For a scroll
/// view's content: it fills the visible height (`visibleHeight(_:)`), so a click below a short list counts too,
/// and the click target sits behind the families, which take their own clicks.
struct DeselectsOnEmptyClick: ViewModifier {
    let model: AppModel
    let height: CGFloat
    let focus: () -> Void

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        focus()
                        model.selectedIDs = []
                    }
            }
    }
}

extension View {
    /// For a scroll view: the height it shows, less what runs under the toolbar.
    func visibleHeight(_ height: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { height.wrappedValue = $1 }
    }
}

/// Keyboard handling for the browser: Return opens, Escape deselects, ⌘A selects all, typing the start of a name
/// jumps to the first family starting with it, Space opens and closes Quick Look, and the arrow keys as the layout has them.
struct FamilyKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let families: [Family]
    @Binding var anchor: String?
    let proxy: ScrollViewProxy
    var layout = FamilyLayout.list
    /// What's been typed so far, as in Finder: letters typed within a second of each other go together, so E and then d
    /// jump to the first family starting with Ed.
    @State private var typed = ""
    @State private var lastTyped = Date.distantPast

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
                guard press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
                if Date.now.timeIntervalSince(lastTyped) > 1 { typed = "" }
                typed += press.characters
                lastTyped = .now
                guard let target = families.first(where: {
                    $0.name.range(of: typed, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                }) else {
                    // Nothing starts with what's been typed: the selection stays where the letters before took it.
                    // A first letter that finds nothing isn't kept, so the next one starts afresh.
                    if typed.count == 1 { typed = ""; return .ignored }
                    return .handled
                }
                model.selectedIDs = [target.id]
                anchor = target.id
                scrollToTop(target.id)
                return .handled
            }
            // After installing fonts: the first of them, selected and in view at once (see `AppModel.jumpTargets`).
            .onChange(of: model.jumpTargets, initial: true) { _, targets in
                guard let targets, let first = families.first(where: { targets.contains($0.id) }) else { return }
                model.selectedIDs = [first.id]
                anchor = first.id
                scrollToTop(first.id)
                model.jumpTargets = nil
            }
            // Opened from the menu, or open while the view changes: several families go in the order this view shows them.
            .onChange(of: quickLook.isOpen, initial: true) { _, isOpen in
                if isOpen { quickLook.updateOrder(families.map(\.id)) }
            }
    }

    /// Brings a family to the top of the view at once. The list's column headers stay pinned over its top row, so
    /// there the row before goes under them instead (they're as tall as a row).
    private func scrollToTop(_ id: String) {
        if case .list = layout, let index = families.firstIndex(where: { $0.id == id }), index > 0 {
            proxy.scrollTo(families[index - 1].id, anchor: .top)
        } else {
            proxy.scrollTo(id, anchor: .top)
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
