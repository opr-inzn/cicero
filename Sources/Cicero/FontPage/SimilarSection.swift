import CiceroCore
import SwiftUI

struct SimilarSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    static let shown = 6
    @State private var showsMore = false

    var body: some View {
        if model.canShowSimilar(family) {
            let similar = model.similarFamilies(to: family, limit: AppModel.similarListed)
            if !similar.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header(all: similar.count)
                    ForEach(similar.prefix(showsMore ? similar.count : Self.shown)) { other in
                        Divider()
                        row(other)
                    }
                    Divider()
                }
                .padding(.horizontal, 24)
            }
        } else if model.measurementProgress != nil {
            VStack(alignment: .leading, spacing: 0) {
                header(all: 0)
                Divider()
                Text("Comparing this family’s letters with the others’")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 24)
        }
    }

    private func header(all: Int) -> some View {
        Text("Similar")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .overlay(alignment: .trailing) {
                if all > Self.shown {
                    Button(showsMore ? "Show Less" : "Show All") { showsMore.toggle() }
                        .buttonStyle(StillButtonStyle())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                        .help(showsMore ? "Show the \(Self.shown.plain) closest" : "Show the \(all.plain) families that look most like \(family.name)")
                }
            }
            .padding(.top, 50)
    }

    private func row(_ other: Family) -> some View {
        let face = other.face(nearestWeight: preview.weight).face
        let foundry = model.foundryName(of: other)
        return Button {
            model.openFamilyID = other.id
        } label: {
            FontText(text: other.name, face: face, size: 20, weight: preview.weight, features: model.features(for: other))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([other.name, foundry].compactMap { $0 }.joined(separator: ", "))
        .help("Open \(other.name)")
        .contextMenu { FamilyMenu(families: [other], model: model) }
    }
}
