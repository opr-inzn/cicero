import CiceroCore
import SwiftUI

enum CompareLayout: String, CaseIterable {
    case stacked, overlay

    var title: String {
        switch self {
        case .stacked: "Stacked"
        case .overlay: "Overlay"
        }
    }
}

extension FocusedValues {
    /// Compare's size, for View → Zoom In and Zoom Out while its window is in front.
    @Entry var compareSize: Binding<Double>?
}

/// Families next to each other, each in a style of its choosing: one row each on a shared baseline, or drawn over
/// each other in tints, in a text and at a size of the window's own.
struct CompareWindow: View {
    static let sizes: ClosedRange<Double> = 24...720
    /// What the samples show while the window's text is empty.
    static let placeholder = "Hamburgefonstiv"
    /// What View → Zoom In and Zoom Out step through, each a fifth to a third bigger than the one before; a size set in
    /// between goes to the next one either way.
    static let steps: [Double] = [24, 30, 36, 48, 60, 72, 96, 120, 144, 192, 240, 288, 384, 480, 576, 720]

    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("compare.layout") private var layout: CompareLayout = .stacked
    @AppStorage("compare.size") private var size = 72.0
    /// Its own, so typing here leaves the previews in the main window as they are.
    @AppStorage("compare.text") private var text = ""
    /// Files on a server read off the main thread for the samples (see `FontLoader.wouldWait`).
    @State private var read: Set<String> = []
    @State private var isAdding = false
    @FocusState private var focused: Bool

    var body: some View {
        let entries = model.compareEntries.compactMap { entry in
            model.family(entry.familyID).map { family in
                (entry: entry, family: family, path: CompareSample.face(for: entry, in: family, preview: preview).face.path)
            }
        }
        // A family whose file is on a server joins the others once it's been read in the background.
        let waiting = entries.map(\.path).filter { !read.contains($0) && FontLoader.shared.wouldWait(for: $0) }
        let samples = entries.filter { !waiting.contains($0.path) }.map {
            CompareSample($0.entry, family: $0.family, text: text.isEmpty ? Self.placeholder : text, size: size, model: model, preview: preview)
        }
        Group {
            if entries.isEmpty {
                // In a scroll view, as the samples are: a window draws a line under its toolbar while nothing scrolls
                // under it.
                ScrollView {
                    EmptyState("Nothing to Compare", systemImage: "square.on.square",
                               description: Text("Add families from anywhere in your library, choose Fonts → Compare with families selected, or drop families here.")) {
                        Button("Add Families") { isAdding = true }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        switch layout {
                        case .stacked: StackedLayout(samples: samples)
                        case .overlay: OverlayLayout(samples: samples)
                        }
                    }
                    .padding(24)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
            }
        }
        // Filling the window when there's nothing to compare too, on the canvas.
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        // The window takes focus, as it comes to the front and once Add Families closes, rather than the size field
        // in its toolbar.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .defaultFocus($focused, true)
        .onChange(of: isAdding) { if !$1 { focused = true } }
        .background(Color.canvas)
        .background(FontDropTarget { drags in _ = model.addToCompare(drags.flatMap(\.families)) })
        .task(id: waiting) {
            guard !waiting.isEmpty else { return }
            await FontLoader.shared.read(waiting)
            read.formUnion(waiting)
        }
        .focusedSceneValue(\.compareSize, $size)
        .toolbar {
            ToolbarCapsule { AddFamiliesButton(isPresented: $isAdding) }
            ToolbarCapsule {
                ToolbarPicker("Layout", values: CompareLayout.allCases, selection: $layout, title: \.title,
                              help: "One row per font, or every font over each other")
            }
            ToolbarCapsule {
                PreviewOptionsButton(own: OwnPreviewOptions(text: $text, placeholder: Self.placeholder, size: $size, sizeRange: Self.sizes))
            }
        }
    }
}

extension CompareWindow {
    /// The next of `steps` up from `size`.
    static func bigger(than size: Double) -> Double {
        steps.first { $0 > size } ?? sizes.upperBound
    }

    /// The next of `steps` down from `size`.
    static func smaller(than size: Double) -> Double {
        steps.last { $0 < size } ?? sizes.lowerBound
    }
}

/// The toolbar button with Add Families.
private struct AddFamiliesButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Add Families", systemImage: "plus")
        }
        .toolbarButtonStyle()
        .help("Add families from anywhere in your library")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { AddFamilies() }
    }
}

/// Every family the library lists, wherever it is in the library and whatever the main window shows, or those what's
/// typed finds, as the main window's search does. Clicking one, or Return on the highlighted one, adds it to Compare,
/// or takes it out when it's checked, there already; ↑ and ↓ move the highlight. It stays open for the next. While
/// Compare is full, the families not in it are dimmed, and a line under them says why.
private struct AddFamilies: View {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    @State private var text = ""
    @State private var families: [Family] = []
    /// nil: the first family listed.
    @State private var highlighted: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let compared = Set(model.compareEntries.map(\.familyID))
        let isFull = model.isCompareFull
        VStack(spacing: 0) {
            TextField("Search", text: $text, prompt: Text("Search"))
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                // The field can keep an action from before the last search: `current` is read when it's pressed.
                .onSubmit { if let current { toggle(current) } }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard let current, let index = families.firstIndex(where: { $0.id == current }) else { return .ignored }
                    highlighted = families[min(max(index + (press.key == .downArrow ? 1 : -1), 0), families.count - 1)].id
                    return .handled
                }
                .padding(10)
            Divider()
            if families.isEmpty {
                Text("No Families Found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let current = current
                            ForEach(families) { family in
                                let isCompared = compared.contains(family.id)
                                row(family, isCompared: isCompared, isAvailable: isCompared || !isFull, isHighlighted: family.id == current)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Back at the top for each search, where the first family found is highlighted.
                    .id(text)
                    .onChange(of: highlighted) { if let id = $1 { proxy.scrollTo(id) } }
                }
            }
            if isFull {
                Divider()
                Text("Compare holds up to \(AppModel.compareLimit) fonts. Take one out to add another.")
                    .font(.callout)
                    .foregroundStyle(Color(Color.secondary.resolve(in: environment)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(width: 320, height: 400)
        .defaultFocus($isFocused, true)
        .onChange(of: text, initial: true) {
            families = model.compareCandidates(for: text)
            highlighted = nil
        }
    }

    /// The family highlighted, or else the first one found.
    private var current: String? {
        highlighted.flatMap { id in families.contains { $0.id == id } ? id : nil } ?? families.first?.id
    }

    /// Adds the family, or takes it out; one not in Compare stays out while it's full.
    private func toggle(_ id: String) {
        guard !model.isCompareFull || model.compareEntries.contains(where: { $0.familyID == id }) else { return }
        model.toggleInCompare(id)
    }

    /// "Aa" in its regular style, its name and a check while it's in Compare, as the search field's suggestions show
    /// a family: the name in the label colour and "Aa" in the secondary one, resolved, as the popover's material
    /// lightens a colour that changes with the appearance, and the highlighted one in white on the selection colour.
    private func row(_ family: Family, isCompared: Bool, isAvailable: Bool, isHighlighted: Bool) -> some View {
        HStack(spacing: 0) {
            // A fixed width keeps the names lined up however wide each family's letters are, as in the suggestions.
            FontText(text: "Aa", face: family.regular.face, size: 14, weight: family.regular.face.styleWeight)
                .foregroundStyle(isHighlighted ? Color.white : Color(Color.secondary.resolve(in: environment)))
                .frame(width: 28)
                .padding(.trailing, 3)
                .opacity(isAvailable ? 1 : 0.4)
            Text(family.name)
                .foregroundStyle(isHighlighted ? Color.white : Color(Color.primary.resolve(in: environment)))
                .lineLimit(1)
                .opacity(isAvailable ? 1 : 0.4)
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                .opacity(isCompared ? 1 : 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .selectedContentBackgroundColor)).padding(.horizontal, 5)
            }
        }
        .id(family.id)
        .contentShape(.rect)
        .onTapGesture {
            highlighted = family.id
            toggle(family.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCompared ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { toggle(family.id) }
    }
}

/// One family's sample, set in the style chosen for it, else the one nearest the preview weight.
private struct CompareSample: Identifiable {
    /// The tints the fonts get in turn, as they join, and that each font's colour menu offers: one for each font
    /// Compare holds (`AppModel.compareLimit`).
    static let tints: [(title: String, color: Color)] = [
        ("Blue", .blue), ("Red", .red), ("Green", .green), ("Orange", .orange), ("Purple", .purple), ("Pink", .pink),
        ("Teal", .teal), ("Indigo", .indigo), ("Brown", .brown), ("Cyan", .cyan), ("Mint", .mint), ("Yellow", .yellow),
    ]

    let family: Family
    let face: LibraryFace
    /// The style chosen; nil when it follows the preview weight.
    let style: FaceID?
    let line: TextLine
    /// Its place in `tints`.
    let tintIndex: Int
    let id: UUID

    var tint: Color { Self.tints[tintIndex].color }

    init(_ entry: CompareEntry, family: Family, text: String, size: Double, model: AppModel, preview: PreviewSettings) {
        self.family = family
        id = entry.id
        let chosen = Self.chosenStyle(of: entry, in: family)
        style = chosen?.id
        face = Self.face(for: entry, in: family, preview: preview)
        let weight = chosen.map(\.face.styleWeight) ?? preview.weight
        let font = FontLoader.shared.font(face.face, size: size, weight: weight, variations: model.variations(for: family, face: face.id))
        line = TextLine(text, font: font, kerning: 0)
        tintIndex = entry.tint % Self.tints.count
    }

    /// The style chosen for the family, if one was.
    static func chosenStyle(of entry: CompareEntry, in family: Family) -> LibraryFace? {
        entry.style.flatMap { style in family.faces.first { $0.id == style } }
    }

    /// The style its sample is set in: the one chosen, else the one nearest the preview weight.
    static func face(for entry: CompareEntry, in family: Family, preview: PreviewSettings) -> LibraryFace {
        chosenStyle(of: entry, in: family) ?? family.face(nearestWeight: preview.weight)
    }
}

/// One row per font, as tall as its own sample reaches above and below its baseline, so a row stays where it is as
/// fonts that reach further join or leave below it. Dragging a row changes the order.
private struct StackedLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let overhang = samples.map(\.line.overhang).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + 2
        Reorderable(samples: samples, layout: AnyLayout(VStackLayout(alignment: .leading, spacing: 20)), axis: .vertical) { sample in
            row(sample, overhang: overhang, width: width)
        } lifted: { sample in
            // Opaque, so the rows it passes don't show through.
            row(sample, overhang: overhang, width: width)
                .background { Color.canvas.padding(-8) }
        }
    }

    private func row(_ sample: CompareSample, overhang: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Glyphs reaching left of the start go into the margin, so the lines start level with the names.
            Canvas { context, _ in
                let color = Color.ink.resolve(in: context.environment).cgColor
                context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: overhang, y: sample.line.ascent), color: color) }
            }
            .frame(width: overhang + width, height: sample.line.ascent + sample.line.descent)
            .padding(.leading, -overhang)
            SampleCaption(sample: sample, showsTint: false)
                .help("Drag to change the order")
        }
        .contentShape(.rect)
    }
}

/// Every sample over the others, each in its tint, on a shared baseline, their first letters' first stems on each other
/// (see `FirstStem`). Dragging a chip in the legend below changes the order; its dot changes the colour.
private struct OverlayLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let ascent = samples.map(\.line.ascent).max() ?? 0
        let descent = samples.map(\.line.descent).max() ?? 0
        // Where each line starts: the one whose stem is furthest from its start level with the legend, the others
        // further in, so their stems stand on its. Started together, a serif font's stem stood right of a sans one's.
        let stems = samples.map { FirstStem.x(in: $0.line.line) ?? 0 }
        let starts = stems.map { (stems.max() ?? 0) - $0 }
        // Glyphs reaching left of that go into the margin, as in the stacked rows.
        let overhang = zip(samples, starts).map { max(0, $0.line.overhang - $1) }.max() ?? 0
        let width = (zip(samples, starts).map { $0.line.width + $1 }.max() ?? 0) + 2
        VStack(alignment: .leading, spacing: 16) {
            Canvas { context, _ in
                let environment = context.environment
                context.withCGContext { cg in
                    // Over each other as inks on paper, or as lights in Dark Mode, so every font shows through those
                    // drawn over it. Simply laid over each other at 70 %, a few stems hid the serifs of a font below.
                    cg.setBlendMode(environment.colorScheme == .dark ? .screen : .multiply)
                    for (sample, start) in zip(samples, starts) {
                        let color = sample.tint.opacity(0.7).resolve(in: environment).cgColor
                        sample.line.draw(in: cg, baselineAt: CGPoint(x: overhang + start, y: ascent), color: color)
                    }
                }
            }
            .frame(width: overhang + width, height: ascent + descent)
            .padding(.leading, -overhang)
            Reorderable(samples: samples, layout: AnyLayout(FlowLayout(spacing: 8, lineSpacing: 8)), axis: .horizontal) { sample in
                chip(sample)
                    .help("Drag to change the order")
            } lifted: { sample in
                chip(sample)
                    .background(Color.canvas, in: .capsule)
            }
            .frame(width: max(width, 480), alignment: .leading)
        }
    }

    private func chip(_ sample: CompareSample) -> some View {
        SampleCaption(sample: sample, showsTint: true)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary, in: .capsule)
    }

}

/// Samples laid out by `layout` that can be dragged to new places among each other. The dragged one follows
/// the pointer, leaving a gap where it will land, and the others make way as it passes their middle.
private struct Reorderable<Item: View, Lifted: View>: View {
    @Environment(AppModel.self) private var model
    let samples: [CompareSample]
    let layout: AnyLayout
    /// The way samples pass each other: down a column of rows, or along lines of chips.
    let axis: Axis
    /// A sample in its place.
    @ViewBuilder let item: (CompareSample) -> Item
    /// The sample under the pointer while it's dragged.
    @ViewBuilder let lifted: (CompareSample) -> Lifted
    private static var space: String { "compare.reorderable" }
    @State private var drag: SampleDrag?
    /// Where each sample is laid out, in this view's coordinates.
    @State private var frames: [UUID: CGRect] = [:]

    var body: some View {
        layout {
            ForEach(samples) { sample in
                item(sample)
                    .opacity(drag?.id == sample.id ? 0 : 1)
                    // Keeps the gap hit-testable, so the drag that started on it carries on.
                    .background { Color.clear.contentShape(.rect) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[sample.id] = $0 }
                    .gesture(reorder(sample.id))
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) {
            if let drag, let sample = samples.first(where: { $0.id == drag.id }) {
                // Rows stay in their column, as in a list; chips go wherever the pointer does.
                lifted(sample)
                    .offset(x: axis == .vertical ? 0 : drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Picks the sample up and carries it under the pointer, moving it in Compare as it passes the others.
    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag?.id != id || drag?.isSettling == true, let frame = frames[id] {
                    drag = SampleDrag(id: id, grab: CGSize(width: value.startLocation.x - frame.minX, height: value.startLocation.y - frame.minY),
                                      location: value.location)
                }
                drag?.location = value.location
                if let target = target(at: value.location, dragging: id) {
                    withAnimation(.snappy) { model.moveInCompare(id, to: target) }
                }
            }
            .onEnded { _ in settle() }
    }

    /// The sample under `point` the dragged one should take the place of. Only once the pointer is past its
    /// middle, coming from the dragged one's side, so a wide chip and a narrow one don't keep trading places.
    /// A row counts all the way across.
    private func target(at point: CGPoint, dragging id: UUID) -> UUID? {
        let ids = model.compareEntries.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return nil }
        for (index, other) in ids.enumerated() where index != from {
            guard let frame = frames[other] else { continue }
            switch axis {
            case .vertical:
                guard (frame.minY..<frame.maxY).contains(point.y) else { continue }
                return (index < from ? point.y < frame.midY : point.y > frame.midY) ? other : nil
            case .horizontal:
                guard frame.contains(point) else { continue }
                return (index < from ? point.x < frame.midX : point.x > frame.midX) ? other : nil
            }
        }
        return nil
    }

    /// Glides the dropped sample into its place, then shows it there.
    private func settle() {
        guard let drag, let frame = frames[drag.id] else {
            self.drag = nil
            return
        }
        let settled = SampleDrag(id: drag.id, grab: drag.grab, location: CGPoint(x: frame.minX + drag.grab.width, y: frame.minY + drag.grab.height),
                                 isSettling: true)
        withAnimation(.snappy(duration: 0.25)) {
            self.drag = settled
        } completion: {
            if self.drag == settled { self.drag = nil }
        }
    }
}

/// A row or chip being dragged.
private struct SampleDrag: Equatable {
    let id: UUID
    /// Where the pointer took hold of the sample, from its top-left corner.
    let grab: CGSize
    /// The pointer, in the Reorderable's coordinates.
    var location: CGPoint
    /// Dropped, and on its way into its place.
    var isSettling = false
}

/// Name, a menu of styles and a remove button, as a row caption or a legend chip.
private struct SampleCaption: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let sample: CompareSample
    let showsTint: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsTint {
                TintMenu(sample: sample)
            }
            Text(sample.family.name).fontWeight(.semibold)
            styleMenu
            Button("Remove", systemImage: "xmark.circle.fill") { model.removeFromCompare(sample.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from Compare")
        }
    }

    /// The style shown, which opens the family's styles; Automatic follows the preview weight. Another of its styles
    /// can join Compare too, to set them against each other.
    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: Binding(get: { sample.style }, set: { model.setCompareStyle($0, of: sample.id) })) {
                Text("Automatic").tag(FaceID?.none)
                Divider()
                ForEach(sample.family.faces) { Text($0.face.styleName).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if sample.family.faces.count > 1 {
                Divider()
                Button("Compare Another Style", systemImage: "plus") {
                    let automatic = sample.family.face(nearestWeight: preview.weight).id
                    let shown = model.compareEntries.filter { $0.familyID == sample.family.id }.map { $0.style ?? automatic }
                    model.compareAnotherStyle(of: sample.id, besides: Set(shown))
                }
                .disabled(model.isCompareFull)
            }
        } label: {
            // One text, as a menu's label puts an image of its own first. Grey here only: on the menu, the grey
            // would reach its items' icons too.
            Text("\(sample.face.face.styleName) \(Image(systemName: "chevron.down"))")
                .foregroundStyle(.secondary)
                .tint(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the style to compare")
    }
}

/// A legend chip's dot, which opens the tints to choose the font's colour from: an AppKit menu, from a view of its own
/// over the dot. As the button of a SwiftUI menu, the dot lit up while the menu was open.
private struct TintMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    let sample: CompareSample

    var body: some View {
        Circle()
            .fill(sample.tint)
            .frame(width: 8, height: 8)
            // A larger target, the dot where it is.
            .padding(3)
            .overlay {
                TintMenuArea(tints: CompareSample.tints.map { (title: $0.title, image: NSImage.menuDot(resolved($0.color))) },
                             chosen: sample.tintIndex) { model.setCompareTint($0, of: sample.id) }
            }
            .padding(-3)
    }

    /// A tint as this appearance shows it, as a menu's images don't change with it.
    private func resolved(_ color: Color) -> NSColor {
        NSColor(cgColor: color.resolve(in: environment).cgColor) ?? .gray
    }
}

/// Opens the tints under the dot as the mouse goes down, as a pop-up button does, the one chosen checked.
private struct TintMenuArea: NSViewRepresentable {
    let tints: [(title: String, image: NSImage)]
    let chosen: Int
    let choose: (Int) -> Void

    func makeNSView(context: Context) -> TintMenuView { TintMenuView() }

    func updateNSView(_ view: TintMenuView, context: Context) {
        view.tints = tints
        view.chosen = chosen
        view.choose = choose
    }
}

private final class TintMenuView: NSView {
    var tints: [(title: String, image: NSImage)] = []
    var chosen = 0
    var choose: (Int) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Choose a color"
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        for (index, tint) in tints.enumerated() {
            let item = NSMenuItem(title: tint.title, action: #selector(chooseTint(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = tint.image
            item.state = index == chosen ? .on : .off
            menu.addItem(item)
        }
        // Its top-left corner just under the dot's.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
    }

    @objc private func chooseTint(_ item: NSMenuItem) {
        choose(item.tag)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityLabel() -> String? { "Color" }
    override func accessibilityValue() -> Any? { tints.indices.contains(chosen) ? tints[chosen].title : nil }

    override func accessibilityPerformPress() -> Bool {
        showMenu()
        return true
    }
}
