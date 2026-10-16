import CiceroCore
import SwiftUI

/// Full-width specimens on cards like the grid's: the sample at the preview size, with the family's styles set
/// in themselves.
struct SpecimenList: View {
    @Environment(AppModel.self) private var model
    let families: [Family]
    @State private var anchor = SelectionAnchor()
    @FocusState private var focused: Bool
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FontGrid.spacing) {
                    ForEach(families) { family in
                        Specimen(family: family, foundry: model.foundryName(of: family), isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                    }
                }
                .scrollTargetLayout()
                .cardsPadding(infoPresented: model.isInfoPresented)
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .visibleHeight($visibleHeight)
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy, layout: .specimens))
        }
    }
}

private struct Specimen: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let foundry: String?
    let isSelected: Bool
    let model: AppModel

    /// Long families show their first styles and a count, so rows stay a readable height.
    private static let styleLimit = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(family.name).font(.headline).lineLimit(1)
                TagDots(colors: model.tagColors(of: family))
                StatusTag(family: family)
                Text([foundry, family.stylesLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            FontText(
                text: preview.text(for: family), face: family.face(nearestWeight: preview.weight).face,
                size: preview.size, weight: preview.weight,
                features: model.features(for: family), kerning: preview.kerning(at: preview.size)
            )
            .frame(maxWidth: .infinity, alignment: preview.alignment.frame)
            if family.faces.count > 1 {
                FlowLayout(spacing: 14, lineSpacing: 4) {
                    ForEach(family.faces.prefix(Self.styleLimit)) { face in
                        FontText(text: face.face.styleName, face: face.face, size: 13, weight: face.face.styleWeight)
                            .foregroundStyle(.secondary)
                    }
                    if family.faces.count > Self.styleLimit {
                        Text("+\(family.faces.count - Self.styleLimit) more").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FamilyCard(isSelected: isSelected))
    }
}
