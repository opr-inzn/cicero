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
        content.animation(Self.slide) { $0.modifier(Panel(shown: model.isInfoShown ? 1 : 0)) }
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
    static let narrowestPage: CGFloat = 600

    func body(content: Content) -> some View {
        let shown: CGFloat = model.isInfoShown ? 1 : 0
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(InfoPanelOverlay.slide) { $0.modifier(Room(shown: isCovered ? coveredShown ?? shown : shown)) }
            .onChange(of: isCovered, initial: true) { coveredShown = isCovered ? shown : nil }
            .onGeometryChange(for: Bool.self) { proxy in
                let page = proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing
                return page - InfoPanelOverlay.room(shown: 1, scale: 1) >= Self.narrowestPage
            } action: { [isCovered] fits in
                if !isCovered { model.infoFits = fits }
            }
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
    @Environment(AppModel.self) private var model
    // ScrollViewProxy, not .scrollPosition: in a sectioned LazyVGrid, SwiftUI's ScrollPosition jumps to the top when any view inside updates, such as on window resign-key or click.
    let proxy: ScrollViewProxy
    @State private var topID: String?
    @State private var isAtTop = true
    @State private var held: String?
    @State private var settling: Task<Void, Never>?
    @State private var hasAppeared = false
    @State private var beforeSearch: (items: Set<SidebarItem>, id: String?)?
    private static var closedAt: (items: Set<SidebarItem>, id: String)?
    private static var isClosing = false

    func body(content: Content) -> some View {
        content
            // Needs .scrollTargetLayout() on the content.
            .onScrollTargetVisibilityChange(idType: String.self) { if let first = $0.first { topID = first } }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: { isAtTop = $1 }
            // Reported before the visible families update, so `topID` is still the one from before.
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width - $0.contentInsets.leading - $0.contentInsets.trailing } action: { old, new in
                guard old > 0, new > 0, abs(new - old) >= 0.5 else { return }
                keep()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { old, new in
                guard let held, abs(new - old) >= 0.5 else { return }
                proxy.scrollTo(held, anchor: .top)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { clearHeld() }
            }
            .onChange(of: model.selectedItems) { clearHeld() }
            .onChange(of: model.shownSort) { clearHeld() }
            .onChange(of: model.sortsAscending) { clearHeld() }
            .onChange(of: model.scrollsToTop) { clearHeld() }
            .onChange(of: model.jumpTargets) { clearHeld() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let window = note.object as? NSWindow, window === TextEditingKeys.mainWindow else { return }
                Self.closedAt = isAtTop ? nil : topID.map { (model.selectedItems, $0) }
                Self.isClosing = true
            }
            .onAppear {
                Self.isClosing = false
                guard !hasAppeared else { return }
                hasAppeared = true
                guard let place = Self.closedAt, place.items == model.selectedItems else { return }
                restore(place.id)
            }
            .onChange(of: SearchState(model)) { old, new in
                if !old.isActive, new.isActive {
                    beforeSearch = (model.selectedItems, isAtTop ? nil : topID)
                } else if old.isActive, !new.isActive {
                    let before = beforeSearch
                    beforeSearch = nil
                    if let before, before.items == model.selectedItems {
                        if let id = before.id { restore(id) } else { toTop() }
                    }
                    return
                }
                if new.isActive { toTop() }
            }
            // SwiftUI makes the browser twice as the window opens and removes the first only after the second has appeared.
            .onDisappear {
                clearHeld()
                if !Self.isClosing { Self.closedAt = nil }
            }
    }

    private func keep() {
        if settling == nil { held = isAtTop ? nil : topID }
        guard let id = held else { return }
        hold(id)
        // A turn later, after FontGrid's onGeometryChange updates its column count and rows reflow.
        DispatchQueue.main.async {
            guard held == id else { return }
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func restore(_ id: String) {
        guard model.jumpTargets == nil else { return }
        hold(id)
        DispatchQueue.main.async {
            guard held == id, !FamilyKeys.jumpedRecently else { return }
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func toTop() {
        guard model.jumpTargets == nil, !FamilyKeys.jumpedRecently else { return }
        clearHeld()
        proxy.scrollTo(ScrollTop.id, anchor: .top)
    }

    private func hold(_ id: String) {
        held = id
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            held = nil
            settling = nil
        }
    }

    private func clearHeld() {
        settling?.cancel()
        settling = nil
        held = nil
    }
}

private struct SearchState: Equatable {
    let text: String
    let tokens: [SearchToken]

    init(_ model: AppModel) {
        text = model.appliedSearch
        tokens = model.searchTokens
    }

    var isActive: Bool { !text.isEmpty || !tokens.isEmpty }
}

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The same view from one family to the next, so what its rows work out stays until the next family's is ready.
        if let family = model.inspectedFamily {
            FamilyInfo(family: family, face: family.regular)
        } else {
            let count = model.shownSelection.count
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
            Picker("Info Section", selection: tab) {
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
        Binding { model.shownInfoTab } set: { model.infoTab = $0 }
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
            LicensesRow(family: family)
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
                    label("Other Copies")
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
                Text("None").font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            TagDots(dots: [TagDot(name: tag, color: model.data.tagColors[tag])]).accessibilityHidden(true)
                            Text(tag).font(.callout)
                        }
                    }
                }
            }
        }
    }
}

private struct LicensesRow: View {
    @Environment(AppModel.self) private var model
    let family: Family

    var body: some View {
        let licenses = model.licenses(of: family)
        if !licenses.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Licenses").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Vault") { open(nil) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                ForEach(licenses) { license in
                    let covered = model.coveredFaces(of: family, by: license)
                    let isPartial = covered.count < family.faces.count
                    Button { open(license) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(license.owner).font(.callout.weight(.semibold))
                                Spacer(minLength: 4)
                                KindChips(kinds: license.kinds)
                            }
                            Text(detail(license, covered: covered)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
                        .overlay(alignment: .leading) {
                            if isPartial {
                                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(.orange).frame(width: 3)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(isPartial ? "This license covers only some styles" : "Open this license in the Vault")
                }
            }
        }
    }

    private func detail(_ license: VaultLicense, covered: [LibraryFace]) -> String {
        let total = family.faces.count
        let version = license.styles.compactMap { AppModel.versionNumber($0.version) }.first
        var text = covered.count == total ? (total == 1 ? "Its 1 style" : "All \(total.plain) styles")
            : "\(covered.count.plain) of \(total.plain) styles"
        if covered.count < total, !covered.isEmpty, covered.count <= 4 {
            text += ": " + covered.map(\.face.styleName).listed()
        }
        if let version { text += " · \(version)" }
        if !license.name.isEmpty { text += " · \(license.name)" }
        return text
    }

    private func open(_ license: VaultLicense?) {
        model.openFamilyID = nil
        model.selection = .vault
        model.openLicenseID = license?.id
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
                    .help(stars == rating ? "Remove rating" : Rating.description(stars))
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
    @State private var loaded = ""
    @State private var editing: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note").font(.caption).foregroundStyle(.secondary)
            TextField("Note", text: $text, prompt: Text("Add a note"), axis: .vertical)
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
        .onChange(of: model.note(of: family)) { if editing == family.id, !isFocused || text == loaded { load() } }
        .onChange(of: isFocused) { if !isFocused { save() } }
        .onDisappear(perform: save)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { save() }
        }
    }

    private func load() {
        editing = family.id
        loaded = model.note(of: family) ?? ""
        text = loaded
    }

    private func newLine() -> KeyPress.Result {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, !editor.hasMarkedText() else { return .ignored }
        editor.insertNewlineIgnoringFieldEditor(nil)
        return .handled
    }

    private func save() {
        guard text != loaded, let editing, let family = model.family(editing) else { return }
        model.setNote(text, for: family)
        loaded = model.note(of: family) ?? ""
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
                           description: Text("This font has no optional OpenType features."))
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
                guard state.wrappedValue?.id != AnyHashable(id) else { return }
                let value = await work()
                if !Task.isCancelled { state.wrappedValue = Loaded(id: id, value: value) }
            }
            .task(id: id) {
                guard state.wrappedValue?.id != AnyHashable(id) else { return }
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
