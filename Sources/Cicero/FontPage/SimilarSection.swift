import CiceroCore
import SwiftUI

/// The families that look most like the page's, each its name set in itself, under the styles and titled as they are:
/// a click opens one's page, Show All lists as many as Show Similar Fonts does, right there, and Not Similar, on a row
/// the pointer is over, takes one out. Left out for a family Cicero can't measure, like one without Latin letters.
struct SimilarSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family

    /// How many the page shows, until Show All shows `AppModel.similarListed`.
    static let shown = 6
    /// Whether Show All was chosen, on this page only: every page opens with the six, the same family's again too.
    @State private var showsMore = false
    /// The row the pointer is over, which shows Not Similar.
    @State private var hovered: String?

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
            // Measuring the library's letters, the first time: quietly, as it takes a moment.
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

    /// Like the styles' title above, with Show All at the end when there are more than `shown` of `all`.
    private func header(all: Int) -> some View {
        Text("Similar")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            // Over the title's row rather than in it, so that it's as high as the styles'.
            .overlay(alignment: .trailing) {
                if all > Self.shown {
                    // Like the sidebar's Edit: grey text at the title's size, not a bezeled button heavier than the title.
                    Button(showsMore ? "Show Less" : "Show All") { showsMore.toggle() }
                        .buttonStyle(StillButtonStyle())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                        .help(showsMore ? "Show the \(Self.shown) closest" : "Show the \(all) families that look most like \(family.name)")
                }
            }
            // As far from the styles above as the glyphs' title is from this.
            .padding(.top, 50)
    }

    private func row(_ other: Family) -> some View {
        let face = other.face(nearestWeight: preview.weight).face
        let foundry = model.foundryName(of: other)
        return Button {
            model.openFamilyID = other.id
        } label: {
            // Its name, whatever the preview text, so that the row says which family it is.
            FontText(text: other.name, face: face, size: 20, weight: preview.weight, features: model.features(for: other))
                .frame(maxWidth: .infinity, alignment: .leading)
                // One height for every row, whatever each font's line spacing; tall glyphs reach past it, never cut off.
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // In the room the name leaves at the row's end, only while the pointer is over it.
        .overlay(alignment: .trailing) {
            if hovered == other.id {
                Button("Not Similar") { model.markNotSimilar([other], to: family) }
                    .controlSize(.small)
                    .help("Don’t list \(other.name) as similar to \(family.name)")
            }
        }
        .onHover { inside in
            if inside { hovered = other.id } else if hovered == other.id { hovered = nil }
        }
        .accessibilityLabel([other.name, foundry].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAction(named: "Not Similar") { model.markNotSimilar([other], to: family) }
        .help("Open \(other.name)")
        .contextMenu { FamilyMenu(families: [other], model: model, similarTo: family) }
    }
}
