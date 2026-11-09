import CiceroCore
import SwiftUI

struct SpecimenList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.infoPanelShown) private var infoShown
    @Environment(\.displayScale) private var scale
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
                            .onAppear { prefetchStyles(near: family) }
                    }
                }
                .scrollTargetLayout()
                .cardsPadding(infoShown: infoShown, scale: scale)
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

    private func prefetchStyles(near family: Family) {
        guard let index = families.firstIndex(where: { $0.id == family.id }) else { return }
        let near = families[max(0, index - 4) ..< min(families.count, index + 12)]
        FontLoader.shared.prefetch(near.flatMap { $0.faces.prefix(Specimen.styleLimit).map(\.face) })
    }
}

private struct Specimen: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let foundry: String?
    let isSelected: Bool
    let model: AppModel

    static let styleLimit = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(family.name).font(.headline).lineLimit(1)
                TagDots(colors: model.tagColors(of: family))
                StatusTag(family: family)
                VariableTag(family: family)
                Text([foundry, family.stylesLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                NoteMark(note: model.note(of: family))
                RatingStars(rating: model.rating(of: family))
                Spacer(minLength: 8)
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            let (style, weight) = model.previewStyle(of: family, weight: preview.weight)
            FontText(
                text: model.scriptSamples.text(preview.text(for: family), for: style.face, long: true), face: style.face,
                size: preview.size, weight: weight, variations: model.variations(for: family, face: style.id), features: model.searchFeatures
            )
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if family.faces.count > 1 {
                FlowLayout(spacing: 14, lineSpacing: 4) {
                    ForEach(family.faces.prefix(Self.styleLimit)) { face in
                        FontText(text: face.face.styleName, face: face.face, size: 13, weight: face.face.styleWeight)
                            .foregroundStyle(.secondary)
                    }
                    if family.faces.count > Self.styleLimit {
                        Text("+\((family.faces.count - Self.styleLimit).plain) more").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FamilyCard(isSelected: isSelected))
    }
}
