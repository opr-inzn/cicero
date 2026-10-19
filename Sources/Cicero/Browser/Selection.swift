import AppKit
import CiceroCore
import SwiftUI

extension AppModel {
    func click(_ family: Family, in families: [Family], anchor: inout SelectionAnchor) {
        FamilySelection.click(family.id, in: families.map(\.id), selection: &selectedIDs, anchor: &anchor)
    }
}

/// Where ⇧-clicks and ⇧-arrows extend the selection from, as in the Finder: the family clicked last, and
/// what else was selected then, which stays while Shift adds the range from the anchor.
struct SelectionAnchor {
    var id: String?
    /// Selected apart from the anchor's range: families ⌘-clicked before it.
    var base: Set<String> = []
    /// The end of the range away from the anchor, which ⇧-arrows move.
    var head: String?
}

/// How clicks and arrow keys select in every list of families, the browser's and the Character Toolbox's.
enum FamilySelection {
    /// Command toggles, Shift extends from the anchor, a plain click selects one.
    static func click(_ id: String, in ids: [String], selection: inout Set<String>, anchor: inout SelectionAnchor) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = SelectionAnchor(id: id, base: selection)
            return
        }
        if modifiers.contains(.shift), extend(to: id, in: ids, selection: &selection, anchor: &anchor) { return }
        selection = [id]
        anchor = SelectionAnchor(id: id)
    }

    /// ↑ and ↓ move the selection a row, Shift extending it from the anchor. Returns the row to scroll to.
    static func step(_ step: Int, in ids: [String], selection: inout Set<String>, anchor: inout SelectionAnchor, extending: Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        if extending, let start = anchor.id, selection.contains(start), let a = ids.firstIndex(of: start) {
            // The end of the range away from the anchor moves, so Shift grows and shrinks it either way.
            let head: Int
            if let id = anchor.head, selection.contains(id), let index = ids.firstIndex(of: id) {
                head = index
            } else {
                let first = ids.firstIndex { selection.contains($0) } ?? a
                head = first < a ? first : ids.lastIndex { selection.contains($0) } ?? a
            }
            let target = ids[min(max(head + step, 0), ids.count - 1)]
            if extend(to: target, in: ids, selection: &selection, anchor: &anchor) { return target }
        }
        let first = ids.firstIndex { selection.contains($0) }
        let current = ids.lastIndex { selection.contains($0) && $0 != anchor.id } ?? first
        let index = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        selection = [ids[index]]
        anchor = SelectionAnchor(id: ids[index])
        return ids[index]
    }

    /// Selects from the anchor to `id` and keeps what was selected besides, so families ⌘-clicked before stay
    /// while a range Shift made before gives way to the new one. False without an anchor in `ids`.
    private static func extend(to id: String, in ids: [String], selection: inout Set<String>, anchor: inout SelectionAnchor) -> Bool {
        guard let start = anchor.id, let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: id) else { return false }
        // Cleared or changed elsewhere since (Escape, a click between families): nothing of it to keep.
        if !anchor.base.isSubset(of: selection) { anchor.base = [] }
        selection = anchor.base.union(ids[min(a, b)...max(a, b)])
        anchor.head = id
        return true
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
/// jumps to the first family starting with it (spaces included while typing), Space opens and closes Quick Look, and the arrow keys as the layout has them.
struct FamilyKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let order: FamilyOrder
    @Binding var anchor: SelectionAnchor
    let proxy: ScrollViewProxy
    var layout = FamilyLayout.list
    /// What's been typed so far, as in Finder: letters typed within a second of each other go together, so E and then d
    /// jump to the first family starting with Ed.
    @State private var typed = ""
    @State private var lastTyped = Date.distantPast
    /// Quick Look, opening unless a letter follows the space just typed.
    @State private var pendingQuickLook: Task<Void, Never>?
    /// The family `jumpTargets` last brought to the top, and when.
    @State private var lastJump: (id: String, date: Date)?

    private var families: [Family] { order.families }

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
                guard press.phase == .down else { return .handled }  // Holding the bar down opens or closes it once.
                // While a name is being typed, a space is part of it ("New York") if a letter follows it at once;
                // otherwise it opens Quick Look a moment later, as it would have straight away.
                if pendingQuickLook == nil, !typed.hasSuffix(" "), !typed.isEmpty, Date.now.timeIntervalSince(lastTyped) <= 1 {
                    typed += " "
                    lastTyped = .now
                    pendingQuickLook = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        pendingQuickLook = nil
                        typed = ""
                        quickLook.toggle(order: families.map(\.id))
                    }
                    return .handled
                }
                pendingQuickLook?.cancel()
                pendingQuickLook = nil
                typed = ""
                quickLook.toggle(order: families.map(\.id))
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
                pendingQuickLook?.cancel()
                pendingQuickLook = nil
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
                anchor = SelectionAnchor(id: target.id)
                scrollToTop(target.id)
                return .handled
            }
            // After installing fonts: the first of them, selected and in view at once (see `AppModel.jumpTargets`).
            .onChange(of: model.jumpTargets, initial: true) { _, targets in
                guard let targets, let first = families.first(where: { targets.contains($0.id) }) else { return }
                model.selectedIDs = [first.id]
                anchor = SelectionAnchor(id: first.id)
                scrollToTop(first.id)
                lastJump = (first.id, .now)
                model.jumpTargets = nil
            }
            // A bar that comes with the jump, as Show Similar Fonts' does, moves the top of the view down a moment
            // later, which would leave the family under it: to the top again.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, _ in
                guard let jump = lastJump, Date.now.timeIntervalSince(jump.date) < 1 else { return }
                scrollToTop(jump.id)
            }
            // Opened from the menu, or open while the view changes: several families go in the order this view shows them.
            .onChange(of: quickLook.isOpen, initial: true) { _, isOpen in
                if isOpen { quickLook.updateOrder(families.map(\.id)) }
            }
    }

    /// Brings a family to the top of the view at once, below the list's column headers.
    private func scrollToTop(_ id: String) {
        proxy.scrollTo(id, anchor: .top)
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

/// The families a browser view shows, in its order, for its keys and for each tile or row to select ranges in.
/// SwiftUI compares a view's inputs whenever it updates, and comparing two arrays of families compares every
/// family in them unless they're the same array: with one in every tile, a list made again with the same
/// families (a classification guessed, coverage worked out, another layout) took most of a second. Equal only when
/// it's the same array, which is enough to keep the views that hold it up to date.
struct FamilyOrder: Equatable {
    let families: [Family]

    init(_ families: [Family]) {
        self.families = families
    }

    static func == (a: Self, b: Self) -> Bool {
        a.families.withUnsafeBufferPointer { x in
            b.families.withUnsafeBufferPointer { $0.baseAddress == x.baseAddress && $0.count == x.count }
        }
    }
}

/// Clicking, double-clicking, dragging, the right-click menu and accessibility for one family's tile or row.
struct FamilyItem: ViewModifier {
    let family: Family
    let order: FamilyOrder
    let model: AppModel
    @Binding var anchor: SelectionAnchor
    let focus: () -> Void

    func body(content: Content) -> some View {
        let isSelected = model.selectedIDs.contains(family.id)
        content
            .id(family.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) { model.openFamilyID = family.id }
            .simultaneousGesture(TapGesture().onEnded {
                focus()
                model.click(family, in: order.families, anchor: &anchor)
            })
            .contextMenu { FamilyMenu(families: model.targets(for: family), model: model) }
            .draggable(family.name)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.openFamilyID = family.id }
            .accessibilityAction(named: "Select") { model.click(family, in: order.families, anchor: &anchor) }
            .accessibilityAction(named: family.hasActive ? "Deactivate" : "Activate") { model.toggle(family) }
    }
}
