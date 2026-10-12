import AppKit
import SwiftUI

/// Tiles with a short sample in each family, for scanning many fonts at once.
struct FontGrid: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let families: [FontFamily]
    @State private var anchorID: String?
    @FocusState private var focused: Bool

    var body: some View {
        let minWidth = max(240, preview.size * 8)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.6), spacing: 12)], spacing: 12) {
                    ForEach(families) { family in
                        tile(family)
                    }
                }
                .padding(16)
            }
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyListKeys(families: families, anchorID: $anchorID, proxy: proxy))
        }
    }

    private func tile(_ family: FontFamily) -> some View {
        let selected = library.selectedFamilyIDs.contains(family.id)
        return FontTile(family: family, foundry: library.foundryName(of: family), isSelected: selected)
            .id(family.id)
            .contentShape(.rect(cornerRadius: 14))
            .onTapGesture(count: 2) { library.detailFamilyID = family.id }
            .simultaneousGesture(TapGesture().onEnded {
                focused = true
                library.click(family, in: families, anchor: &anchorID)
            })
            .contextMenu { FontActionsMenu(families: library.targets(for: family)) }
            .draggable(family.name)
            .familyAccessibility(family, isSelected: selected) {
                library.click(family, in: families, anchor: &anchorID)
            }
    }
}

struct FontTile: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    let foundry: String?
    let isSelected: Bool
    @State private var isHovered = false

    /// Shows case, a descender and figures when no sample text is set.
    static let defaultSample = "Aa Gg 123"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusTag(status: family.status)
                Spacer()
                ActivationSwitch(family: family)
                    .accessibilityHidden(true)
            }
            FontPreviewText(
                text: preview.sampleText.isEmpty ? Self.defaultSample : preview.sampleText,
                face: family.face(nearestWeight: Int(preview.weight)).face,
                size: preview.size, weight: preview.weight, features: library.features(for: family),
                kerning: preview.kerning(atSize: preview.size)
            )
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: preview.size * 3.4)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text([family.stylesLabel, foundry].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(background, in: .rect(cornerRadius: 14))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.14)) }
        return AnyShapeStyle(.quaternary.opacity(isHovered ? 0.7 : 0.4))
    }
}

// MARK: - Shared by the grid and the specimen list

extension LibraryStore {
    /// Click selection: Command toggles, Shift extends from the anchor, a plain click selects one.
    func click(_ family: FontFamily, in families: [FontFamily], anchor: inout String?) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedFamilyIDs.contains(family.id) {
                selectedFamilyIDs.remove(family.id)
            } else {
                selectedFamilyIDs.insert(family.id)
            }
            anchor = family.id
        } else if modifiers.contains(.shift), let anchorID = anchor,
                  let a = families.firstIndex(where: { $0.id == anchorID }),
                  let b = families.firstIndex(where: { $0.id == family.id }) {
            selectedFamilyIDs = Set(families[min(a, b)...max(a, b)].map(\.id))
        } else {
            selectedFamilyIDs = [family.id]
            anchor = family.id
        }
    }
}

/// Return opens, Escape deselects, ⌘A selects all, and typing a letter jumps to the first family starting with it.
struct FamilyListKeys: ViewModifier {
    @Environment(LibraryStore.self) private var library
    let families: [FontFamily]
    @Binding var anchorID: String?
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return) {
                guard library.selectedFamilyIDs.count == 1 else { return .ignored }
                library.detailFamilyID = library.selectedFamilyIDs.first
                return .handled
            }
            .onKeyPress(.escape) {
                library.selectedFamilyIDs = []
                return .handled
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    guard press.characters == "a" else { return .ignored }
                    library.selectedFamilyIDs = Set(families.map(\.id))
                    return .handled
                }
                guard press.modifiers.isEmpty || press.modifiers == .shift,
                      let target = families.first(where: { $0.name.lowercased().hasPrefix(press.characters.lowercased()) }) else {
                    return .ignored
                }
                library.selectedFamilyIDs = [target.id]
                anchorID = target.id
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                return .handled
            }
    }
}

extension View {
    /// One accessibility element per family: pressing opens it, with named actions to select and to turn it on or off.
    func familyAccessibility(_ family: FontFamily, isSelected: Bool, select: @escaping () -> Void) -> some View {
        modifier(FamilyAccessibility(family: family, isSelected: isSelected, select: select))
    }
}

private struct FamilyAccessibility: ViewModifier {
    @Environment(LibraryStore.self) private var library
    let family: FontFamily
    let isSelected: Bool
    let select: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { library.detailFamilyID = family.id }
            .accessibilityAction(named: "Select", select)
            .accessibilityAction(named: family.hasActiveFaces ? "Deactivate" : "Activate") {
                family.hasActiveFaces ? library.requestDeactivate([family]) : library.requestActivate([family])
            }
    }
}
