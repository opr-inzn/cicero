import SwiftUI

// Temporary: only the old font page uses this; delete once the new font page is merged.
struct SliderMenuControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let presets: [Double]
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $value, in: range)
                .controlSize(.mini)
                .frame(width: 84)
            Menu("\(Int(value.rounded()))\(unit)") {
                ForEach(presets, id: \.self) { preset in
                    Button("\(Int(preset))\(unit)") { value = preset }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 6)
    }
}
