import CiceroCore
import SwiftUI

/// The families that look most like the page's, each set in itself, under the styles: a click opens one's page,
/// Show All fills the browser with more of them. Left out for a family Cicero can't measure, like one without
/// Latin letters.
struct SimilarSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    /// How many the page shows.
    static let shown = 6

    var body: some View {
        if model.canShowSimilar(family) {
            let similar = model.similarFamilies(to: family, limit: Self.shown)
            if !similar.isEmpty {
                VStack(spacing: 0) {
                    header
                    ForEach(similar) { other in
                        row(other)
                        Divider()
                    }
                }
                .padding(.horizontal, 24)
            }
        } else if model.measurementProgress != nil {
            // Measuring the library's letters, the first time: quietly, as it takes a moment.
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("Comparing this family’s letters with the others’")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Similar").font(.title2.weight(.semibold))
            Spacer()
            if model.canShowSimilar(family) {
                Button("Show All") { model.showSimilar(to: family) }
                    .help("Show the \(AppModel.similarListed) families that look most like \(family.name), the closest first")
            }
        }
        // As far from the styles above as the glyphs' title is from this.
        .padding(.top, 56)
        .padding(.bottom, 8)
    }

    private func row(_ other: Family) -> some View {
        let face = other.face(nearestWeight: preview.weight).face
        let foundry = model.foundryName(of: other)
        return Button {
            model.openFamilyID = other.id
        } label: {
            HStack(spacing: 12) {
                FontText(text: preview.text(for: other), face: face, size: 20, weight: preview.weight, features: model.features(for: other))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(other.name)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
                Text(foundry ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)
            }
            // One height for every row, whatever each font's line spacing; tall glyphs reach past it, never cut off.
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([other.name, foundry].compactMap { $0 }.joined(separator: ", "))
        .help("Open \(other.name)")
        .contextMenu { FamilyMenu(families: [other], model: model) }
    }
}
