import AppKit
import CiceroCore
import SwiftUI

struct InfoPanelOverlay: ViewModifier {
    @Environment(AppModel.self) private var model
    static let width: CGFloat = 300
    static let gap: CGFloat = 8
    static let top: CGFloat = 16
    static let slide = Animation.easeInOut(duration: 0.25)

    static func room(shown: CGFloat, scale: CGFloat) -> CGFloat {
        ((width + gap * 2) * shown * scale).rounded() / scale
    }

    func body(content: Content) -> some View {
        content.animation(Self.slide) { $0.modifier(Panel(shown: model.isInfoPresented ? 1 : 0)) }
    }

    private struct Panel: ViewModifier, Animatable {
        var shown: CGFloat

        var animatableData: CGFloat {
            get { shown }
            set { shown = newValue }
        }

        func body(content: Content) -> some View {
            content.overlay(alignment: .trailing) {
                if shown > 0 {
                    let shape = InfoPanelOverlay.shape
                    InfoPanel()
                        // Under the slide, the rows filled in as the panel opened faded in with it, and took as long.
                        .transaction { if $0.animation == InfoPanelOverlay.slide { $0.animation = nil } }
                        .frame(width: InfoPanelOverlay.width)
                        .frame(maxHeight: .infinity)
                        .background {
                            shape.fill(Color.canvas)
                            shape.fill(.quaternary.opacity(0.5))
                        }
                        .clipShape(shape)
                        .padding([.horizontal, .bottom], InfoPanelOverlay.gap)
                        .padding(.top, InfoPanelOverlay.top)
                        .offset(x: (1 - shown) * (InfoPanelOverlay.width + InfoPanelOverlay.gap))
                        .transition(.identity)
                }
            }
        }
    }

    private static var shape: AnyShape {
        if #available(macOS 27, *) {
            AnyShape(ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct InfoPanelInset: ViewModifier {
    @Environment(AppModel.self) private var model
    var isCovered = false
    @State private var coveredShown: CGFloat?

    func body(content: Content) -> some View {
        let shown: CGFloat = model.isInfoPresented ? 1 : 0
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(InfoPanelOverlay.slide) { $0.modifier(Room(shown: isCovered ? coveredShown ?? shown : shown)) }
            .onChange(of: isCovered, initial: true) { coveredShown = isCovered ? shown : nil }
            .background(Color.canvas)
    }

    private struct Room: ViewModifier, Animatable {
        @Environment(\.displayScale) private var scale
        var shown: CGFloat

        var animatableData: CGFloat {
            get { shown }
            set { shown = newValue }
        }

        func body(content: Content) -> some View {
            content
                // Safe area, not padding, so the page still runs under the toolbar from edge to edge and the search field keeps the look it has over the page.
                .safeAreaPadding(.trailing, InfoPanelOverlay.room(shown: shown, scale: scale))
                .environment(\.infoPanelShown, shown)
        }
    }
}

extension EnvironmentValues {
    @Entry var infoPanelShown: CGFloat = 0
}

struct KeepsTopOnResize: ViewModifier {
    // Applied by the scroll view as it lays out, so after the rows have reflowed (a proxy can jump too early).
    @State private var position = ScrollPosition(idType: String.self)
    @State private var topID: String?
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .scrollPosition($position, anchor: .top)
            // Needs .scrollTargetLayout() on the content.
            .onScrollTargetVisibilityChange(idType: String.self) { if let first = $0.first { topID = first } }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: { isAtTop = $1 }
            // Reported before the visible families update, so `topID` is still the one from before.
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width } action: { _, _ in
                if !isAtTop, let topID { position.scrollTo(id: topID, anchor: .top) }
            }
    }
}

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview

    var body: some View {
        // The same view from one family to the next, so what its rows work out stays until the next family's is ready.
        if let family = model.inspectedFamily {
            FamilyInfo(family: family, face: family.face(nearestWeight: preview.weight))
        } else {
            let count = model.selectedIDs.count
            EmptyState(count > 1 ? "\(count.plain) Families Selected" : "No Selection", systemImage: "info.circle",
                       description: Text("Select a single family to see its info."))
        }
    }
}

private struct FamilyInfo: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let face: LibraryFace

    var body: some View {
        VStack(spacing: 0) {
            Text(family.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 16)
            Picker("Tab", selection: tab) {
                ForEach(tabs, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .tabsPickerStyle()
            .labelsHidden()
            .padding(12)
            Divider()
            switch tab.wrappedValue {
            case .info: ScrollView { InfoRows(family: family, face: face) }
            case .features: FeatureControls(family: family, face: face.face)
            case .axes: AxisControls(family: family)
            }
        }
    }

    private var tabs: [InfoTab] { family.isVariable ? InfoTab.allCases : InfoTab.allCases.filter { $0 != .axes } }

    private var tab: Binding<InfoTab> {
        Binding { model.infoTab == .axes && !family.isVariable ? .info : model.infoTab } set: { model.infoTab = $0 }
    }
}

private struct InfoRows: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let face: LibraryFace
    @State private var info: Loaded<CiceroCore.FontInfo>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoteRow(family: family)
            row("Status", face.state.label)
            TagsRow(family: family)
            RatingRow(family: family)
            ClassificationRow(family: family)
            if let info = info?.value {
                ForEach(Array(info.rows.enumerated()), id: \.offset) { _, row in
                    self.row(row.label, row.value)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            LanguagesRow(face: face.face)
            CharacterSetsRow(face: face.face)
            UnicodeBlocksRow(face: face.face)
            VStack(alignment: .leading, spacing: 4) {
                label("Location")
                Text(face.face.path).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Reveal in Finder") { model.reveal(path: face.face.path) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            if !face.otherCopies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    label("Other copies")
                    ForEach(face.otherCopies, id: \.self) { path in
                        Button(path) { model.reveal(path: path) }
                            .buttonStyle(.link)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loading($info, for: FileFace(face.face), cached: { [face = face.face] in
            CiceroCore.FontInfo.cached(face) ?? (FontLoader.shared.wouldWait(for: face.path) ? nil : CiceroCore.FontInfo.read(face))
        }) { [face = face.face] in
            await Task.detached(priority: .userInitiated) { CiceroCore.FontInfo.read(face) }.value
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ClassificationRow: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Classification").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Change") { ClassificationMenuItems(families: [family], model: model) }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .fixedSize()
            }
            Text(model.classificationName(of: family)).font(.callout)
            if model.data.classificationOverrides[family.id] == nil, let guess = model.guessedClassification(of: family) {
                Text(guess.source == .name ? "Recognized from its name by Apple Intelligence" : "Recognized from the shapes of its letters")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagsRow: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        let tags = model.data.tags(of: family.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tags").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Change") { TagMenuItems(families: [family], model: model) }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .fixedSize()
            }
            if tags.isEmpty {
                Text("No Tags").font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            TagDots(colors: model.data.tagColors[tag].map { [$0] } ?? [])
                            Text(tag).font(.callout)
                        }
                    }
                }
            }
        }
    }
}

private struct RatingRow: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        let rating = model.rating(of: family) ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Text("Rating").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        model.setRating(stars == rating ? nil : stars, for: [family])
                    } label: {
                        Image(systemName: stars <= rating ? "star.fill" : "star")
                            .foregroundStyle(stars <= rating ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .help(stars == rating ? "Remove Rating" : Rating.description(stars))
                }
            }
            .font(.callout)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rating")
            .accessibilityValue(rating == 0 ? "No rating" : Rating.description(rating))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.setRating(min(rating + 1, 5), for: [family])
                case .decrement: model.setRating(rating > 1 ? rating - 1 : nil, for: [family])
                @unknown default: break
                }
            }
        }
    }
}

private struct NoteRow: View {
    @Environment(AppModel.self) private var model
    let family: Family
    @State private var text = ""
    @State private var editing: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note").font(.caption).foregroundStyle(.secondary)
            TextField("Note", text: $text, prompt: Text("Add a Note"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...12)
                .focused($isFocused)
                .labelsHidden()
                .onKeyPress(.return, action: newLine)
        }
        .onAppear(perform: load)
        .onChange(of: family.id) {
            save()
            load()
        }
        .onChange(of: model.note(of: family)) { if !isFocused { load() } }
        .onChange(of: isFocused) { if !isFocused { save() } }
        .onDisappear(perform: save)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { save() }
        }
    }

    private func load() {
        editing = family.id
        text = model.note(of: family) ?? ""
    }

    private func newLine() -> KeyPress.Result {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, !editor.hasMarkedText() else { return .ignored }
        editor.insertNewlineIgnoringFieldEditor(nil)
        return .handled
    }

    private func save() {
        guard let editing, let family = model.family(editing) else { return }
        model.setNote(text, for: family)
    }
}

// MARK: - Features

private struct FeatureControls: View {
    @Environment(AppModel.self) private var model
    let family: Family
    let face: FontFace
    @State private var loaded: Loaded<[FontFeatureGroup]>?

    var body: some View {
        let groups = loaded?.value
        Group {
            if let groups, groups.isEmpty {
                EmptyState("No Features", systemImage: "textformat.abc",
                           description: Text("This font has no optional OpenType features to switch on or off."))
            } else if let groups {
                Form {
                    ForEach(groups) { group in
                        Section(group.name) {
                            ForEach(group.options) { option in
                                Toggle(option.name, isOn: group.isExclusive ? choice(group, option) : toggle(group, option))
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .loading($loaded, for: FileFace(face), cached: { [model, face] in model.pageFeatures.features(of: face) }) { [model, face] in
            if model.openFamilyID == family.id { return await model.pageFeatures.features(loading: face) }
            return await Task.detached(priority: .userInitiated) { FontFeatureGroup.load(for: face) }.value
        }
    }

    private var settings: [FeatureSetting] { model.familyFeatures[family.id] ?? [] }

    private func set(_ settings: [FeatureSetting]) {
        model.familyFeatures[family.id] = settings.isEmpty ? nil : settings
    }

    private func exclusive(_ group: FontFeatureGroup) -> Binding<Int> {
        Binding(
            get: { settings.first { $0.type == group.type }?.selector ?? group.options.first(where: \.isDefault)?.selector ?? group.options[0].selector },
            set: { selector in
                var list = settings.filter { $0.type != group.type }
                if selector != group.options.first(where: \.isDefault)?.selector { list.append(FeatureSetting(type: group.type, selector: selector)) }
                set(list)
            }
        )
    }

    private func choice(_ group: FontFeatureGroup, _ option: FontFeatureGroup.Option) -> Binding<Bool> {
        let picked = exclusive(group)
        let fallback = group.options.first(where: \.isDefault)?.selector ?? group.options[0].selector
        return Binding(
            get: { picked.wrappedValue == option.selector },
            set: { on in
                if on { picked.wrappedValue = option.selector } else if picked.wrappedValue == option.selector { picked.wrappedValue = fallback }
            }
        )
    }

    private func toggle(_ group: FontFeatureGroup, _ option: FontFeatureGroup.Option) -> Binding<Bool> {
        // The selector after an option's turns it off, as CoreText numbers them.
        let off = option.selector + 1
        return Binding(
            get: {
                if let chosen = settings.first(where: { $0.type == group.type && ($0.selector == option.selector || $0.selector == off) }) {
                    return chosen.selector == option.selector
                }
                return option.isDefault
            },
            set: { on in
                var list = settings.filter { !($0.type == group.type && ($0.selector == option.selector || $0.selector == off)) }
                if on != option.isDefault { list.append(FeatureSetting(type: group.type, selector: on ? option.selector : off)) }
                set(list)
            }
        )
    }
}

struct FileFace: Hashable {
    let id: FaceID
    let generation: Int

    init(_ face: FontFace) {
        id = face.id
        generation = FontLoader.shared.generation(of: face.path)
    }
}

struct Loaded<Value> {
    let id: AnyHashable
    let value: Value
}

extension View {
    func loading<ID: Hashable, Value>(_ state: Binding<Loaded<Value>?>, for id: ID, cached: @escaping @MainActor () -> Value? = { nil },
                                      _ work: @escaping @MainActor () async -> Value) -> some View {
        let useCached = {
            if state.wrappedValue?.id != AnyHashable(id), let value = cached() { state.wrappedValue = Loaded(id: id, value: value) }
        }
        return onAppear(perform: useCached)
            .onChange(of: id) { useCached() }
            .task(id: id) {
                let value = await work()
                if !Task.isCancelled { state.wrappedValue = Loaded(id: id, value: value) }
            }
            .task(id: id) {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled, state.wrappedValue?.id != AnyHashable(id) { state.wrappedValue = nil }
            }
    }
}

private extension View {
    @ViewBuilder func tabsPickerStyle() -> some View {
        if #available(macOS 27, *) { pickerStyle(.tabs) } else { pickerStyle(.segmented) }
    }
}
