import AppKit
import CiceroCore
import SwiftUI

extension AppModel {
    func click(_ family: Family, in families: [Family], anchor: inout SelectionAnchor) {
        FamilySelection.click(family.id, in: families.map(\.id), selection: &selectedIDs, anchor: &anchor)
    }
}

struct SelectionAnchor {
    var id: String?
    var base: Set<String> = []
    var head: String?
}

enum FamilySelection {
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

    static func step(_ step: Int, in ids: [String], selection: inout Set<String>, anchor: inout SelectionAnchor, extending: Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        if extending, let start = anchor.id, selection.contains(start), let a = ids.firstIndex(of: start) {
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

    private static func extend(to id: String, in ids: [String], selection: inout Set<String>, anchor: inout SelectionAnchor) -> Bool {
        guard !selection.isEmpty, let start = anchor.id, let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: id) else { return false }
        if !anchor.base.isSubset(of: selection) { anchor.base = [] }
        selection = anchor.base.union(ids[min(a, b)...max(a, b)])
        anchor.head = id
        return true
    }
}

enum FamilyLayout {
    case list
    case specimens
    case grid(columns: Int)
}

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
    func visibleHeight(_ height: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { height.wrappedValue = $1 }
    }
}

struct FamilyKeys: ViewModifier {
    @Environment(AppModel.self) private var model
    let order: FamilyOrder
    @Binding var anchor: SelectionAnchor
    let proxy: ScrollViewProxy
    @Binding var position: ScrollPosition
    var layout = FamilyLayout.list
    var pinned: String?
    @State private var typed = ""
    @State private var lastTyped = Date.distantPast
    @State private var pendingQuickLook: Task<Void, Never>?
    @State private var lastJump: (id: String, date: Date)?

    private var families: [Family] { order.families }

    func body(content: Content) -> some View {
        let quickLook = model.quickLook
        content
            .onKeyPress(.return) {
                guard model.openFamilyID == nil else { return .ignored }
                stopTyping()
                return open()
            }
            .onKeyPress(.escape) {
                guard model.openFamilyID == nil else { return .ignored }
                stopTyping()
                if quickLook.isOpen { quickLook.close() } else { model.selectedIDs = [] }
                return .handled
            }
            .onKeyPress(.space, phases: [.down, .repeat]) { press in
                guard model.openFamilyID == nil else { return .ignored }
                guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
                guard press.phase == .down else { return .handled }
                if pendingQuickLook == nil, !typed.hasSuffix(" "), !typed.isEmpty, Date.now.timeIntervalSince(lastTyped) <= 1,
                   families.contains(where: {
                       $0.name.range(of: typed + " ", options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                   }) {
                    typed += " "
                    lastTyped = .now
                    pendingQuickLook = Task {
                        try? await Task.sleep(for: .milliseconds(500))
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
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard model.openFamilyID == nil else { return .ignored }
                stopTyping()
                return arrow(press)
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                guard model.openFamilyID == nil else { return .ignored }
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
                    if typed.count == 1 { typed = ""; return .ignored }
                    return .handled
                }
                model.selectedIDs = [target.id]
                anchor = SelectionAnchor(id: target.id)
                scrollToTop(target.id)
                return .handled
            }
            .onChange(of: model.jumpTargets, initial: true) { _, targets in
                guard let targets, let first = families.first(where: { targets.contains($0.id) }) else { return }
                model.selectedIDs = [first.id]
                anchor = SelectionAnchor(id: first.id)
                scrollToTop(first.id)
                lastJump = (first.id, .now)
                model.jumpTargets = nil
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, _ in
                guard let jump = lastJump, Date.now.timeIntervalSince(jump.date) < 1 else { return }
                scrollToTop(jump.id)
            }
            .onChange(of: quickLook.isOpen, initial: true) { _, isOpen in
                if isOpen { quickLook.updateOrder(families.map(\.id)) }
            }
    }

    private func stopTyping() {
        pendingQuickLook?.cancel()
        pendingQuickLook = nil
        typed = ""
    }

    private func scrollToTop(_ id: String) {
        if id == families.first?.id { position.scrollTo(edge: .top) } else { proxy.scrollTo(id, anchor: .top) }
    }

    private func select(_ id: String) {
        model.selectedIDs = [id]
        anchor = SelectionAnchor(id: id)
    }

    private func open() -> KeyPress.Result {
        if model.quickLook.isOpen, let shown = model.quickLook.shown {
            model.openFamilyID = shown.family.id
            return .handled
        }
        let shown = model.shownSelection
        guard shown.count == 1 else { return .ignored }
        model.openFamilyID = shown.first
        return .handled
    }

    private func arrow(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .downArrow, press.modifiers.contains(.command), press.modifiers.isDisjoint(with: [.shift, .option, .control]) {
            return open()
        }
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let vertical = press.key == .upArrow || press.key == .downArrow
        let forward = press.key == .downArrow || press.key == .rightArrow
        var step = 1
        switch layout {
        case .grid(let columns):
            if vertical { step = columns }
        case .list, .specimens:
            guard vertical else {
                guard model.quickLook.isOpen, !press.modifiers.contains(.shift) else { return .ignored }
                model.quickLook.updateOrder(families.map(\.id))
                return model.quickLook.step(forward ? 1 : -1) ? .handled : .ignored
            }
            if case .list = layout { return .ignored }
        }
        var ids = families.map(\.id)
        if let pinned, ids.first == pinned {
            ids.removeFirst()
            if !press.modifiers.contains(.shift), model.selectedIDs.count == 1, let selected = model.selectedIDs.first {
                if selected == pinned {
                    guard forward, let first = ids.first else { return .handled }
                    select(first)
                    proxy.scrollTo(first)
                    return .handled
                }
                if !forward, let index = ids.firstIndex(of: selected), index < step {
                    select(pinned)
                    return .handled
                }
            }
        }
        guard let target = FamilySelection.step(forward ? step : -step, in: ids, selection: &model.selectedIDs,
                                                anchor: &anchor, extending: press.modifiers.contains(.shift)) else {
            return .ignored
        }
        proxy.scrollTo(target)
        return .handled
    }
}

struct PinnedBar<Bar: View>: ViewModifier {
    let isShown: Bool
    let infoShown: CGFloat
    let scale: CGFloat
    @ViewBuilder let bar: () -> Bar
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top >= 1 } action: { isScrolled = $1 }
            .topBar {
                if isShown {
                    bar()
                        // Never as wide as the bar asks: its width would hold the browser at least that wide and push the window's panes aside.
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, InfoPanelOverlay.top)
                        .padding(.leading, InfoPanelOverlay.top)
                        .padding(.trailing, FontGrid.cardsTrailing(infoShown: infoShown, scale: scale))
                        .background(Color.canvas)
                        .overlay(alignment: .bottom) {
                            if isScrolled { Divider() }
                        }
                }
            }
    }
}

struct FamilyOrder: Equatable {
    let families: [Family]

    init(_ families: [Family]) {
        self.families = families
    }

    // The same array only: SwiftUI compares a view's inputs whenever it updates, and comparing every family in every tile held up each new list.
    static func == (a: Self, b: Self) -> Bool {
        a.families.withUnsafeBufferPointer { x in
            b.families.withUnsafeBufferPointer { $0.baseAddress == x.baseAddress && $0.count == x.count }
        }
    }
}

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
            // One tap gesture, which the switch's own takes precedence over: a gesture for two taps would hold every click back until it knew there was no second.
            .onTapGesture {
                focus()
                model.click(family, in: order.families, anchor: &anchor)
                if NSApp.currentEvent?.clickCount == 2 { model.openFamilyID = family.id }
            }
            .contextMenu {
                FamilyMenu(families: model.targets(for: family), model: model)
            }
            .fontDrag { FontDrag(families: model.targets(for: family).map(\.id)) } preview: {
                FamilyDragPreview(family: family, count: model.targets(for: family).count)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.openFamilyID = family.id }
            .accessibilityAction(named: "Select") { model.click(family, in: order.families, anchor: &anchor) }
            .accessibilityAction(named: family.hasActive ? "Deactivate" : "Activate") { model.toggle(family) }
    }
}

enum ReadAhead {
    static let before = 20
    static let after = 80

    private static var last: (order: FamilyOrder, index: Int)?

    static func around(_ family: Family, in families: [Family]) {
        let order = FamilyOrder(families)
        let start = last?.order == order ? min(last!.index, families.count - 1) : 0
        guard let index = place(of: family.id, in: families, from: start) else { return }
        last = (order, index)
        let near = families[max(0, index - before) ..< min(families.count, index + after)]
        FontLoader.shared.prefetch(near.map(\.regular.face))
    }

    private static func place(of id: String, in families: [Family], from start: Int) -> Int? {
        guard !families.isEmpty, start >= 0 else { return nil }
        var step = 0
        while start - step >= 0 || start + step < families.count {
            if start + step < families.count, families[start + step].id == id { return start + step }
            if step > 0, start - step >= 0, families[start - step].id == id { return start - step }
            step += 1
        }
        return nil
    }
}
