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
    @Entry var compareSize: Binding<Double>?
}

struct CompareWindow: View {
    static let sizes: ClosedRange<Double> = 24...720
    static let placeholder = "Hamburgefonstiv"
    static let steps: [Double] = [24, 30, 36, 48, 60, 72, 96, 120, 144, 192, 240, 288, 384, 480, 576, 720]

    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("compare.layout") private var layout: CompareLayout = .stacked
    @AppStorage("compare.size") private var size = 72.0
    @Bindable private var savedText = SavedSoon.compareText
    private var text: String { savedText.value }
    @State private var read: Set<String> = []
    @State private var isAdding = false
    @State private var viewport: CGSize = .zero
    @FocusState private var focused: Bool

    var body: some View {
        let entries = model.compareEntries.compactMap { entry in
            model.family(entry.familyID).map { family in
                (entry: entry, family: family, path: CompareSample.face(for: entry, in: family, preview: preview).face.path)
            }
        }
        let waiting = entries.map(\.path).filter { !read.contains($0) && FontLoader.shared.wouldWait(for: $0) }
        let samples = entries.filter { !waiting.contains($0.path) }.map {
            CompareSample($0.entry, family: $0.family, text: text.isEmpty ? Self.placeholder : text, size: size, model: model, preview: preview)
        }
        Group {
            if entries.isEmpty {
                // In a scroll view, as the samples are: a window draws a line under its toolbar while nothing scrolls under it.
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
                    // As big as the window at least, so samples smaller than it sit at its top left: macOS 15 centres them in a scroll view of both axes, whatever its alignment anchor.
                    .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .topLeading)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
                .onScrollGeometryChange(for: CGSize.self, of: \.containerSize) { _, size in
                    if #unavailable(macOS 26) { viewport = size }
                }
            }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .defaultFocus($focused, true)
        .onChange(of: isAdding) { if !$1 { focused = true } }
        .onDisappear { model.compareEntries = [] }
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
            ToolbarCapsule(spaced: true) {
                ToolbarPicker("Layout", values: CompareLayout.allCases, selection: $layout, title: \.title,
                              help: "One row per font, or every font over each other")
            }
            ToolbarCapsule(spaced: true) {
                PreviewOptionsButton(own: OwnPreviewOptions(text: $savedText.value, placeholder: Self.placeholder, size: $size, sizeRange: Self.sizes))
            }
        }
    }
}

extension CompareWindow {
    static func bigger(than size: Double) -> Double {
        steps.first { $0 > size } ?? sizes.upperBound
    }

    static func smaller(than size: Double) -> Double {
        steps.last { $0 < size } ?? sizes.lowerBound
    }
}

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

private struct AddFamilies: View {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    @State private var text = ""
    @State private var families: [Family] = []
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
                    .id(text)
                    .onChange(of: highlighted) { if let id = $1 { proxy.scrollTo(id) } }
                }
            }
            if isFull {
                Divider()
                Text("Compare holds up to \(AppModel.compareLimit.plain) styles. Take one out to add another.")
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

    private var current: String? {
        highlighted.flatMap { id in families.contains { $0.id == id } ? id : nil } ?? families.first?.id
    }

    private func toggle(_ id: String) {
        guard !model.isCompareFull || model.compareEntries.contains(where: { $0.familyID == id }) else { return }
        model.toggleInCompare(id)
    }

    private func row(_ family: Family, isCompared: Bool, isAvailable: Bool, isHighlighted: Bool) -> some View {
        HStack(spacing: 0) {
            FontText(text: "Aa", face: family.regular.face, size: 14, weight: family.regular.face.styleWeight)
                // Resolved, as the popover's material lightens a colour that changes with the appearance.
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

private struct CompareSample: Identifiable {
    static let tints: [(title: String, color: Color)] = [
        ("Blue", .blue), ("Red", .red), ("Green", .green), ("Orange", .orange), ("Purple", .purple), ("Pink", .pink),
        ("Teal", .teal), ("Indigo", .indigo), ("Brown", .brown), ("Cyan", .cyan), ("Mint", .mint), ("Yellow", .yellow),
    ]

    let family: Family
    let face: LibraryFace
    let style: FaceID?
    let line: TextLine
    // Not the font's ascent, which often keeps room for accents and line spacing far above the ascenders.
    let letterAscent: CGFloat
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
        letterAscent = max(line.inkAscent, (Self.ascenderHeight(of: font) ?? 0).rounded(.up))
        tintIndex = entry.tint % Self.tints.count
    }

    static func topAscent(of samples: [CompareSample]) -> CGFloat {
        samples.map(\.letterAscent).max() ?? 0
    }

    static func ascenderHeight(of font: CTFont) -> CGFloat? {
        var characters = Array("bdhkl".utf16), glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return glyphs.filter { $0 != 0 }.compactMap { glyph -> CGFloat? in
            guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isNull else { return nil }
            return path.boundingBoxOfPath.maxY
        }.max()
    }

    static func chosenStyle(of entry: CompareEntry, in family: Family) -> LibraryFace? {
        entry.style.flatMap { style in family.faces.first { $0.id == style } }
    }

    static func face(for entry: CompareEntry, in family: Family, preview: PreviewSettings) -> LibraryFace {
        chosenStyle(of: entry, in: family) ?? family.face(nearestWeight: preview.weight)
    }
}

private struct StackedLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let overhang = samples.map(\.line.overhang).max() ?? 0
        let width = (samples.map(\.line.width).max() ?? 0) + 2
        let top = CompareSample.topAscent(of: samples)
        Reorderable(samples: samples, layout: AnyLayout(VStackLayout(alignment: .leading, spacing: 20)), axis: .vertical) { sample in
            row(sample, overhang: overhang, width: width, top: top)
        } lifted: { sample in
            row(sample, overhang: overhang, width: width, top: top)
                .background { Color.canvas.padding(-8) }
        }
    }

    private func row(_ sample: CompareSample, overhang: CGFloat, width: CGFloat, top: CGFloat) -> some View {
        let ascent = sample.id == samples.first?.id ? top : sample.line.ascent
        return VStack(alignment: .leading, spacing: 6) {
            Canvas { context, _ in
                let color = Color.ink.resolve(in: context.environment).cgColor
                context.withCGContext { sample.line.draw(in: $0, baselineAt: CGPoint(x: overhang, y: ascent), color: color) }
            }
            .frame(width: overhang + width, height: ascent + sample.line.descent)
            .padding(.leading, -overhang)
            SampleCaption(sample: sample, showsTint: false)
                .help("Drag to change the order")
        }
        .contentShape(.rect)
    }
}

private struct OverlayLayout: View {
    let samples: [CompareSample]

    var body: some View {
        let ascent = CompareSample.topAscent(of: samples)
        let descent = samples.map(\.line.descent).max() ?? 0
        let stems = samples.map { FirstStem.x(in: $0.line.line) ?? 0 }
        let starts = stems.map { (stems.max() ?? 0) - $0 }
        let overhang = zip(samples, starts).map { max(0, $0.line.overhang - $1) }.max() ?? 0
        let width = (zip(samples, starts).map { $0.line.width + $1 }.max() ?? 0) + 2
        VStack(alignment: .leading, spacing: 6 - Self.chipPadding.height) {
            Canvas { context, _ in
                let environment = context.environment
                context.withCGContext { cg in
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

    private static let chipPadding = CGSize(width: 10, height: 5)

    private func chip(_ sample: CompareSample) -> some View {
        SampleCaption(sample: sample, showsTint: true)
            .padding(.horizontal, Self.chipPadding.width)
            .padding(.vertical, Self.chipPadding.height)
            .background(.fill.tertiary, in: .capsule)
    }
}

private struct Reorderable<Item: View, Lifted: View>: View {
    @Environment(AppModel.self) private var model
    let samples: [CompareSample]
    let layout: AnyLayout
    let axis: Axis
    @ViewBuilder let item: (CompareSample) -> Item
    @ViewBuilder let lifted: (CompareSample) -> Lifted
    private static var space: String { "compare.reorderable" }
    @State private var drag: SampleDrag?
    @GestureState private var isDragging = false
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
        // A cancelled drag never ends: without this, its sample stays hidden and its lifted copy stays up.
        .onChange(of: isDragging) { _, now in
            if !now { DispatchQueue.main.async { if drag?.isSettling == false { drag = nil } } }
        }
        .overlay(alignment: .topLeading) {
            if let drag, let sample = samples.first(where: { $0.id == drag.id }) {
                lifted(sample)
                    .offset(x: axis == .vertical ? 0 : drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                    .allowsHitTesting(false)
            }
        }
    }

    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, state, _ in state = true }
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

private struct SampleDrag: Equatable {
    let id: UUID
    let grab: CGSize
    var location: CGPoint
    var isSettling = false
}

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
                Button("Another Style", systemImage: "plus") {
                    let automatic = sample.family.face(nearestWeight: preview.weight).id
                    let shown = model.compareEntries.filter { $0.familyID == sample.family.id }.map { $0.style ?? automatic }
                    model.compareAnotherStyle(of: sample.id, besides: Set(shown))
                }
                .disabled(model.isCompareFull)
            }
        } label: {
            // One text, as a menu's label puts an image of its own first; grey here only, as on the menu the grey would reach its items' icons too.
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

private struct TintMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    let sample: CompareSample

    var body: some View {
        Circle()
            .fill(sample.tint)
            .frame(width: 8, height: 8)
            .padding(3)
            .overlay {
                TintMenuArea(tints: CompareSample.tints.map { (title: $0.title, image: NSImage.menuDot(resolved($0.color))) },
                             chosen: sample.tintIndex) { model.setCompareTint($0, of: sample.id) }
            }
            .padding(-3)
    }

    private func resolved(_ color: Color) -> NSColor {
        // Resolved now, as a menu's images don't change with the appearance.
        NSColor(cgColor: color.resolve(in: environment).cgColor) ?? .gray
    }
}

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
