import SwiftUI

/// A large, editable sample in one style, for trying a font with your own words.
struct TypeTester: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily
    @AppStorage("typeTester.text") private var text = "Sphinx of black quartz, judge my vow."
    @AppStorage("typeTester.size") private var size = 72.0
    @AppStorage("typeTester.centered") private var centered = true
    /// A style picked by hand; nil follows the preview weight.
    @State private var styleID: String?

    var body: some View {
        let chosen = family.faces.first { $0.id == styleID }
        let face = chosen ?? family.face(nearestWeight: Int(preview.weight))
        let weight = chosen.map { Double($0.face.weightClass) } ?? preview.weight
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if family.faces.count > 1 {
                    Picker("Style", selection: $styleID) {
                        Text("Automatic").tag(String?.none)
                        Divider()
                        ForEach(family.faces) { Text($0.face.styleName).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                    .help("Which style to show; Automatic follows the preview weight")
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("Size").foregroundStyle(.secondary)
                    ValueSlider(value: $size, in: 12...240, round: { $0.rounded() })
                        .frame(width: 160)
                    Text("\(Int(size)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Picker("Alignment", selection: $centered) {
                    Image(systemName: "text.alignleft").tag(false)
                    Image(systemName: "text.aligncenter").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Align left or center")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TextEditor(text: $text)
                .font(Font(FontCache.shared.font(face.face, size: size, weight: weight, features: library.features(for: family))))
                .kerning(preview.kerning(atSize: size))
                .multilineTextAlignment(centered ? .center : .leading)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
    }
}
