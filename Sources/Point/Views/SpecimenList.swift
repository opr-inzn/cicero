import AppKit
import SwiftUI

/// Full-width specimens: the sample at the chosen size, with the family's styles set in themselves.
struct SpecimenList: View {
    @Environment(LibraryStore.self) private var library
    let families: [FontFamily]
    @State private var anchorID: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(families) { family in
                        row(family, in: families)
                    }
                }
                .padding(.vertical, 10)
            }
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
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

    private func row(_ family: FontFamily, in families: [FontFamily]) -> some View {
        let selected = library.selectedFamilyIDs.contains(family.id)
        return SpecimenRow(family: family, foundry: library.foundryName(of: family), isSelected: selected)
            .id(family.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) { library.detailFamilyID = family.id }
            .simultaneousGesture(TapGesture().onEnded { click(family, in: families) })
            .contextMenu { FontActionsMenu(families: library.targets(for: family)) }
            .draggable(family.name)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { library.detailFamilyID = family.id }
            .accessibilityAction(named: "Select") { click(family, in: families) }
            .accessibilityAction(named: family.hasActiveFaces ? "Deactivate" : "Activate") {
                family.hasActiveFaces ? library.requestDeactivate([family]) : library.requestActivate([family])
            }
    }

    private func click(_ family: FontFamily, in families: [FontFamily]) {
        focused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if library.selectedFamilyIDs.contains(family.id) {
                library.selectedFamilyIDs.remove(family.id)
            } else {
                library.selectedFamilyIDs.insert(family.id)
            }
            anchorID = family.id
        } else if modifiers.contains(.shift), let anchorID,
                  let a = families.firstIndex(where: { $0.id == anchorID }),
                  let b = families.firstIndex(where: { $0.id == family.id }) {
            library.selectedFamilyIDs = Set(families[min(a, b)...max(a, b)].map(\.id))
        } else {
            library.selectedFamilyIDs = [family.id]
            anchorID = family.id
        }
    }
}

struct SpecimenRow: View {
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    let foundry: String?
    let isSelected: Bool

    /// Long families show their first styles and a count, so rows stay a readable height.
    private static let styleLimit = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(family.name)
                    .font(.headline)
                    .lineLimit(1)
                StatusTag(status: family.status)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // The row exposes Activate/Deactivate as accessibility actions instead.
                ActivationSwitch(family: family)
                    .accessibilityHidden(true)
            }
            FontPreviewText(
                text: preview.text(for: family),
                face: family.face(nearestWeight: Int(preview.weight)).face,
                size: preview.size, weight: preview.weight, kerning: preview.kerning(atSize: preview.size)
            )
            if family.faces.count > 1 {
                FlowLayout(spacing: 14, lineSpacing: 4) {
                    ForEach(family.faces.prefix(Self.styleLimit)) { face in
                        Text(face.face.styleName)
                            .font(Font(FontCache.shared.font(face.face, size: 13)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if family.faces.count > Self.styleLimit {
                        Text("+\(family.faces.count - Self.styleLimit) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 10)
    }

    private var details: String {
        [foundry, family.classification.rawValue, family.stylesLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
