import CiceroCore
import SwiftUI

/// Tiles with a short sample in each family, for scanning many fonts at once.
struct FontGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let families: [Family]
    @State private var anchor: String?
    @FocusState private var focused: Bool

    var body: some View {
        let width = max(240, preview.size * 8)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width * 1.6), spacing: 12)], spacing: 12) {
                    ForEach(families) { family in
                        Tile(family: family, isSelected: model.selectedIDs.contains(family.id), model: model)
                            .modifier(FamilyItem(family: family, families: families, model: model, anchor: $anchor) { focused = true })
                    }
                }
                .scrollTargetLayout()
                .padding(16)
            }
            .modifier(KeepsTopOnResize())
            .background(Color.canvas)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(FamilyKeys(families: families, anchor: $anchor, proxy: proxy))
        }
    }
}

private struct Tile: View {
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    let isSelected: Bool
    let model: AppModel
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusTag(family: family)
                Spacer()
                ActivationSwitch(family: family, model: model)
                    .accessibilityHidden(true)
            }
            FontText(
                text: preview.sampleText.isEmpty ? PreviewSettings.tileSample : preview.sampleText,
                face: family.face(nearestWeight: preview.weight).face,
                size: preview.size, weight: preview.weight,
                features: model.features(for: family), kerning: preview.kerning(at: preview.size)
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
                Text(family.rangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(family.rangeLabel)
            }
        }
        .padding(14)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(isHovered ? 0.7 : 0.4)), in: .rect(cornerRadius: 14))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .onHover { isHovered = $0 }
    }
}
