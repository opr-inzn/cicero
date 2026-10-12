import SwiftUI

/// The sample text at every waterfall size, one truncated line per size with a point-size gutter.
struct WaterfallView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    /// A style picked by hand; nil follows the preview weight.
    @State private var styleID: String?

    var body: some View {
        let chosen = family.faces.first { $0.id == styleID }
        let face = chosen ?? family.face(nearestWeight: Int(preview.weight))
        let weight = chosen.map { Double($0.face.weightClass) } ?? preview.weight
        let text = preview.text(for: family)
        let features = library.detailFeatures
        VStack(spacing: 0) {
            if family.faces.count > 1 {
                HStack {
                    Spacer()
                    Picker("Style", selection: $styleID) {
                        Text("Automatic").tag(String?.none)
                        Divider()
                        ForEach(family.faces) { Text($0.face.styleName).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                    .help("Which style to show; Automatic follows the preview weight")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PreviewSettings.waterfallSizes, id: \.self) { size in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("\(Int(size)) pt")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(text)
                                .font(Font(FontCache.shared.font(face.face, size: size, weight: weight, features: features)))
                                .kerning(preview.kerning(atSize: size))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }
}
