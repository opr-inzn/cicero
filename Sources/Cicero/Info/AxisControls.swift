import CiceroCore
import SwiftUI

/// The Info panel's Axes tab: a slider for each axis of the variable style a family's previews show, which moves them
/// along it, in the browser as on its font page, its text and glyphs. The axes the font hides come last.
struct AxisControls: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    /// Closed to begin with, as the font asks apps not to show them; open or closed for every family after.
    @AppStorage("axes.showsHidden") private var showsHidden = false
    let family: Family

    var body: some View {
        let (style, weight) = model.previewStyle(of: family, weight: preview.weight)
        // A style on a server is read off the main thread first.
        ReadingFonts(paths: [style.face.path]) {
            let axes = FontLoader.shared.axes(of: style.face)
            if axes.isEmpty {
                EmptyState("No Axes", systemImage: "slider.horizontal.3",
                           description: Text("\(style.face.styleName) isn’t a variable style."))
            } else {
                form(axes, style: style, weight: weight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func form(_ axes: [AxisRange], style: LibraryFace, weight: Double) -> some View {
        let moved = model.variations(for: family, face: style.id)
        let drawn = FontLoader.variation(of: FontLoader.shared.font(style.face, size: preview.size, weight: weight, variations: moved))
        let shown = axes.filter { !$0.isHidden }
        let hidden = axes.filter(\.isHidden)
        return Form {
            if !shown.isEmpty {
                Section {
                    ForEach(shown) { row($0, axes: axes, style: style, weight: weight, moved: moved, drawn: drawn) }
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
                // Open when they're all the font has.
                let isOpen = showsHidden || shown.isEmpty
                Section {
                    if isOpen {
                        ForEach(hidden) { row($0, axes: axes, style: style, weight: weight, moved: moved, drawn: drawn) }
                    }
                } header: {
                    hiddenHeader(count: hidden.count, moved: hidden.count { moved[$0.tag] != nil }, isOpen: isOpen)
                        .disabled(shown.isEmpty)
                } footer: {
                    if isOpen {
                        Text("The font asks apps not to show these, but they change its letters too.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// Hidden Axes and how many, which opens and closes them without sliding, and how many of them are moved, which
    /// a closed section would otherwise keep out of sight.
    private func hiddenHeader(count: Int, moved: Int, isOpen: Bool) -> some View {
        Button {
            showsHidden.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Text("Hidden Axes")
                Text(moved > 0 ? "\(count) · \(moved) moved" : "\(count)").foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .help(isOpen ? "Hide the axes the font hides" : "Show the axes the font hides")
    }

    /// The axis's name and tag, and the value, then a slider the panel's width.
    private func row(_ axis: AxisRange, axes: [AxisRange], style: LibraryFace, weight: Double, moved: [String: Double],
                     drawn: [String: Double]) -> some View {
        let value = Binding { moved[axis.tag] ?? drawn[axis.tag] ?? axis.defaultValue } set: {
            set(axis.tag, to: $0, axes: axes, on: style, weight: weight, moved: moved)
        }
        let range = axis.minimum...axis.maximum
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(axis.name).lineLimit(1)
                Text(axis.tag).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ValueField(axis.name, value: value, range: range, step: axis.step)
            }
            ValueSlider(value: value, range: range, step: axis.step)
                .accessibilityLabel(axis.name)
        }
        // Without a thousands separator, as fonts write axis values: 1000, not 1,000 or 1.000.
        .help("\(axis.name) (\(axis.tag)), from \(Self.number(axis.minimum)) to \(Self.number(axis.maximum)), \(Self.number(axis.defaultValue)) by default")
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never))
    }

    /// Moves an axis of the style; the family's other axes stay where they were moved. Moved back to where the style
    /// sits on every axis, it's the style again, and the Style menu says so; moved to where another of the file's styles
    /// sits, on the open font page, that style is shown instead, as if chosen in the menu.
    private func set(_ tag: String, to value: Double, axes: [AxisRange], on style: LibraryFace, weight: Double, moved: [String: Double]) {
        var values = moved
        values[tag] = value
        let own = place(of: style, weight: weight)
        let position = axes.reduce(into: [String: Double]()) { $0[$1.tag] = values[$1.tag] ?? own[$1.tag] ?? $1.defaultValue }
        if Self.isSame(position, own, on: axes) {
            model.familyAxes[family.id] = nil
            return
        }
        if model.openFamilyID == family.id, let other = otherStyle(at: position, axes: axes, besides: style) {
            // Automatic while that's the style it shows: back to it without a style chosen.
            let automatic = model.automaticStyle(of: family, weight: preview.weight)
            let isAutomatic = automatic.face.id == other.id && Self.isSame(place(of: automatic.face, weight: automatic.weight), position, on: axes)
            model.pageStyleID = isAutomatic ? nil : other.id
            model.familyAxes[family.id] = nil
            return
        }
        model.familyAxes[family.id] = AdjustedAxes(face: style.id, values: values)
    }

    /// Where a style is drawn on each of its axes, unmoved.
    private func place(of style: LibraryFace, weight: Double) -> [String: Double] {
        FontLoader.variation(of: FontLoader.shared.font(style.face, size: preview.size, weight: weight))
    }

    /// Another of the family's styles from the same font that sits at `position` on every axis: first by the axes the
    /// library knows the styles' places on, then, for those, the hidden ones too, as the font draws them.
    private func otherStyle(at position: [String: Double], axes: [AxisRange], besides style: LibraryFace) -> LibraryFace? {
        let known = axes.filter { axis in style.face.axes.contains { $0.tag == axis.tag } }
        return family.faces.first { other in
            guard other.id != style.id, other.id.path == style.id.path,
                  Self.isSame(position, other.face.axes.reduce(into: [:]) { $0[$1.tag] = $1.value }, on: known)
            else { return false }
            return Self.isSame(position, place(of: other, weight: other.face.styleWeight), on: axes)
        }
    }

    /// Whether two places are the same on these axes: less than half a slider step apart on each, so a value the slider
    /// rounded, like 0.30000000000000004, is the style's 0.3. An axis a place leaves out is at its default.
    private static func isSame(_ a: [String: Double], _ b: [String: Double], on axes: [AxisRange]) -> Bool {
        axes.allSatisfy { axis in
            abs((a[axis.tag] ?? axis.defaultValue) - (b[axis.tag] ?? axis.defaultValue)) < axis.step / 2
        }
    }
}

extension AxisRange {
    /// Whole units, or tenths or hundredths on an axis that spans 20 or less, like a slant from −12 to 0.
    var step: Double {
        let span = maximum - minimum
        return span > 20 ? 1 : span > 2 ? 0.1 : 0.01
    }
}
