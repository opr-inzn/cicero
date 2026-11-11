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
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let pinned = model.similarFamilyID.flatMap { id in families.first?.id == id ? families.first : nil }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FontGrid.spacing) {
                    ForEach(pinned == nil ? families[...] : families.dropFirst()) { family in
                        Specimen(family: family, isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                            .onAppear { prefetchStyles(near: family) }
                    }
                }
                .scrollTargetLayout()
                .cardsPadding(infoShown: infoShown, scale: scale, top: pinned == nil)
                .modifier(DeselectsOnEmptyClick(model: model, height: visibleHeight) { focused = true })
            }
            .modifier(PinnedBar(isShown: pinned != nil, infoShown: infoShown, scale: scale) {
                if let pinned {
                    Specimen(family: pinned, isSelected: model.selectedIDs.contains(pinned.id), model: model)
                        .modifier(FamilyItem(family: pinned, order: FamilyOrder(families), model: model, anchor: $anchor) { focused = true })
                }
            })
            .visibleHeight($visibleHeight)
            .modifier(KeepsTopOnResize(position: $position))
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(order: FamilyOrder(families), anchor: $anchor, proxy: proxy, position: $position, layout: .specimens, pinned: pinned?.id))
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
    let isSelected: Bool
    let model: AppModel

    static let styleLimit = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(family.name).font(.headline).lineLimit(1)
                    TagDots(colors: model.tagColors(of: family)).centredOnName()
                    StatusTag(family: family).centredOnName()
                    VariableTag(family: family).centredOnName()
                    NoteMark(note: model.note(of: family)).centredOnName()
                    RatingStars(rating: model.rating(of: family))
                }
                Spacer(minLength: 8)
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            let (style, weight) = model.previewStyle(of: family)
            FontText(
                text: model.scriptSamples.text(preview.text(for: family), for: style.face, long: true), face: style.face,
                size: preview.size, weight: weight, variations: model.variations(for: family, face: style.id), features: model.searchFeatures,
                onCaps: true
            )
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            FlowLayout(spacing: 14, lineSpacing: 4) {
                ForEach(family.faces.prefix(Self.styleLimit)) { face in
                    FontText(text: face.face.styleName, face: face.face, size: 13, weight: face.face.styleWeight, onCaps: true)
                        .foregroundStyle(.secondary)
                }
                if family.faces.count > Self.styleLimit {
                    Text("+\((family.faces.count - Self.styleLimit).plain) more").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FamilyCard(isSelected: isSelected))
    }
}

private extension View {
    func centredOnName() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Self.nameMiddle }
    }

    static var nameMiddle: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .headline)
        return (font.ascender + font.descender) / 2
    }
}
