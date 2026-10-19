import CiceroCore
import SwiftUI

/// The Info panel's Axes tab: a slider for each axis of the variable style a family's previews show, which moves them
/// along it, in the browser as on its font page, its text and glyphs. The axes the font hides come last.
struct AxisControls: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    /// The font page's text size, for the optical size its text is drawn at.
    @AppStorage("typeTester.size") private var testerSize = 72.0
    let family: Family

    var body: some View {
        let (style, weight) = model.previewStyle(of: family, weight: preview.weight)
        // A style on a server is read off the main thread first.
        ReadingFonts(paths: [style.face.path]) {
            let axes = FontLoader.shared.axes(of: style.face)
            if axes.isEmpty {
                ContentUnavailableView("No Axes", systemImage: "slider.horizontal.3",
                                       description: Text("\(style.face.styleName) isn’t a variable style."))
            } else {
                form(axes, style: style, weight: weight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func form(_ axes: [AxisRange], style: LibraryFace, weight: Double) -> some View {
        let moved = model.variations(for: family, face: style.id)
        // Where the previews draw it: the optical size follows the size of the page's text, or of the browser's.
        let size = model.openFamilyID == family.id ? testerSize : preview.size
        let drawn = FontLoader.variation(of: FontLoader.shared.font(style.face, size: size, weight: weight, variations: moved))
        let shown = axes.filter { !$0.isHidden }
        let hidden = axes.filter(\.isHidden)
        return Form {
            if !shown.isEmpty {
                Section {
                    ForEach(shown) { row($0, style: style.id, moved: moved, drawn: drawn) }
                } header: {
                    HStack {
                        Text("Axes")
                        Spacer()
                        Button("Reset All") { model.familyAxes[family.id] = nil }
                            .buttonStyle(.borderless)
                            .disabled(moved.isEmpty)
                            .help("Back to the style’s own place on every axis")
                    }
                }
            }
            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { row($0, style: style.id, moved: moved, drawn: drawn) }
                } header: {
                    Text("Hidden Axes")
                } footer: {
                    Text("The font asks apps not to show these, but they change its letters too.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// The axis's name and tag, the value and a button to put it back once it's moved, and a slider the panel's width.
    private func row(_ axis: AxisRange, style: FaceID, moved: [String: Double], drawn: [String: Double]) -> some View {
        let value = Binding { moved[axis.tag] ?? drawn[axis.tag] ?? axis.defaultValue } set: { set(axis.tag, to: $0, on: style, moved: moved) }
        let range = axis.minimum...axis.maximum
        let isMoved = moved[axis.tag] != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(axis.name).lineLimit(1)
                Text(axis.tag).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                // There but invisible until the axis is moved, so the value beside it stays put.
                Button {
                    set(axis.tag, to: nil, on: style, moved: moved)
                } label: {
                    Label("Reset \(axis.name)", systemImage: "arrow.counterclockwise").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .opacity(isMoved ? 1 : 0)
                .disabled(!isMoved)
                .help("Back to the style’s own place on it")
                ValueField(axis.name, value: value, range: range, step: axis.step)
            }
            ValueSlider(value: value, range: range, step: axis.step)
                .accessibilityLabel(axis.name)
        }
        .help("\(axis.name) (\(axis.tag)), from \(axis.minimum.formatted()) to \(axis.maximum.formatted()), \(axis.defaultValue.formatted()) by default")
    }

    /// Moves an axis of the style, or with nil puts it back; the family's other axes stay where they were moved.
    private func set(_ tag: String, to value: Double?, on style: FaceID, moved: [String: Double]) {
        var values = moved
        values[tag] = value
        model.familyAxes[family.id] = values.isEmpty ? nil : AdjustedAxes(face: style, values: values)
    }
}

extension AxisRange {
    /// Whole units, or tenths or hundredths on an axis that spans 20 or less, like a slant from −12 to 0.
    var step: Double {
        let span = maximum - minimum
        return span > 20 ? 1 : span > 2 ? 0.1 : 0.01
    }
}
