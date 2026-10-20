import CiceroCore
import SwiftUI

/// The families that look most like the page's, each set in itself, under the styles and titled as they are: a click
/// opens one's page, Show More lists as many as Show Similar Fonts does, right there. Left out for a family Cicero
/// can't measure, like one without Latin letters.
struct SimilarSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    /// How many the page shows, until Show More shows `AppModel.similarListed`.
    static let shown = 6
    /// Whether Show More was chosen; kept for every page from then on.
    @AppStorage("fontPage.similarShowsMore") private var showsMore = false

    var body: some View {
        if model.canShowSimilar(family) {
            let similar = model.similarFamilies(to: family, limit: AppModel.similarListed)
            if !similar.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header(columns: true)
                    ForEach(similar.prefix(showsMore ? similar.count : Self.shown)) { other in
                        Divider()
                        row(other)
                    }
                    Divider()
                    if similar.count > Self.shown {
                        Button(showsMore ? "Show Fewer" : "Show More") { showsMore.toggle() }
                            .controlSize(.small)
                            .padding(.top, 8)
                            .help(showsMore ? "Show the \(Self.shown) closest" : "Show the \(similar.count) families that look most like \(family.name)")
                    }
                }
                .padding(.horizontal, 24)
            }
        } else if model.measurementProgress != nil {
            // Measuring the library's letters, the first time: quietly, as it takes a moment.
            VStack(alignment: .leading, spacing: 0) {
                header(columns: false)
                Divider()
                Text("Comparing this family’s letters with the others’")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 24)
        }
    }

    /// Like the styles' titles above: the section's, then the columns', when there are rows under them.
    private func header(columns: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Similar").frame(maxWidth: .infinity, alignment: .leading)
            if columns {
                Text("Family").frame(width: Self.nameWidth, alignment: .leading)
                Text("Foundry").frame(width: Self.foundryWidth, alignment: .leading)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        // As far from the styles above as the glyphs' title is from this.
        .padding(.top, 50)
    }

    private static let nameWidth: CGFloat = 220
    private static let foundryWidth: CGFloat = 180

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
                    .frame(width: Self.nameWidth, alignment: .leading)
                Text(foundry ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.foundryWidth, alignment: .leading)
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
