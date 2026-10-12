import AppKit
import SwiftUI

enum BrowserViewMode: String {
    case grid, list
}

struct BrowserView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(Prefs.pointSize) private var pointSize = 36.0
    @AppStorage(Prefs.weight) private var weight = 400.0
    @AppStorage(Prefs.sampleText) private var sampleText = "Aa 123"
    @AppStorage(Prefs.viewMode) private var viewMode: BrowserViewMode = .grid
    @AppStorage(Prefs.colorMode) private var colorMode: PreviewColorMode = .light
    @AppStorage(Prefs.customForeground) private var customForeground = "#FFFFFF"
    @AppStorage(Prefs.customBackground) private var customBackground = "#F04000"
    @State private var anchorID: String?
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var library = library
        let families = library.visibleFamilies
        let colors = PreviewColors(mode: colorMode, foregroundHex: customForeground, backgroundHex: customBackground)
        ScrollViewReader { proxy in
            ScrollView {
                if viewMode == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 0)], spacing: 0) {
                        ForEach(families) { family in
                            cell(family, families: families, colors: colors)
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(families) { family in
                            cell(family, families: families, colors: colors)
                        }
                    }
                }
            }
            .background(colors.background)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.return) {
                guard library.selectedFamilyIDs.count == 1, let id = library.selectedFamilyIDs.first else { return .ignored }
                library.detailFamilyID = id
                return .handled
            }
            .onKeyPress(.escape) {
                library.selectedFamilyIDs = []
                return .handled
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    guard press.characters == "a" else { return .ignored }
                    library.selectedFamilyIDs = Set(families.map(\.id))
                    return .handled
                }
                guard press.modifiers.isEmpty || press.modifiers == .shift,
                      let target = families.first(where: { $0.name.lowercased().hasPrefix(press.characters.lowercased()) }) else {
                    return .ignored
                }
                library.selectedFamilyIDs = [target.id]
                anchorID = target.id
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                return .handled
            }
        }
        .overlay { emptyState(isEmpty: families.isEmpty) }
        .overlay(alignment: .bottomTrailing) {
            if library.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(library.scanStatus.isEmpty ? "Scanning fonts…" : library.scanStatus)
                        .font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(16)
            }
        }
        .navigationTitle(Text(verbatim: families.count == 1 ? "1 Font" : "\(families.count) Fonts"))
        .toolbar { toolbar }
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search")
    }

    // MARK: Cells

    @ViewBuilder
    private func cell(_ family: FontFamily, families: [FontFamily], colors: PreviewColors) -> some View {
        let selected = library.selectedFamilyIDs.contains(family.id)
        Group {
            if viewMode == .grid {
                FontCard(family: family, sample: sampleText, pointSize: pointSize, weight: weight, colors: colors, isSelected: selected)
            } else {
                FontListRow(family: family, sample: sampleText, pointSize: pointSize, weight: weight, colors: colors, isSelected: selected)
            }
        }
        .id(family.id)
        .contentShape(.rect)
        .onTapGesture(count: 2) { library.detailFamilyID = family.id }
        .simultaneousGesture(TapGesture().onEnded { click(family, in: families) })
        .contextMenu { FontActionsMenu(families: library.targets(for: family)) }
        .draggable(family.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { library.detailFamilyID = family.id }
        .accessibilityAction(named: "Select") { click(family, in: families) }
    }

    private func click(_ family: FontFamily, in families: [FontFamily]) {
        focused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if library.selectedFamilyIDs.contains(family.id) {
                library.selectedFamilyIDs.remove(family.id)
            } else {
                library.selectedFamilyIDs.insert(family.id)
            }
            anchorID = family.id
        } else if modifiers.contains(.shift), let anchorID,
                  let a = families.firstIndex(where: { $0.id == anchorID }),
                  let b = families.firstIndex(where: { $0.id == family.id }) {
            library.selectedFamilyIDs = Set(families[min(a, b)...max(a, b)].map(\.id))
        } else {
            library.selectedFamilyIDs = [family.id]
            anchorID = family.id
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty && library.hasScanned {
            let query = library.searchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                switch library.sidebarSelection ?? .all {
                case .inactive where library.data.watchedFolders.isEmpty:
                    ContentUnavailableView {
                        Label("No Watched Folders", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Add a folder of fonts to browse them here. Nothing gets installed until you activate it.")
                    } actions: {
                        Button("Add Folder…") { library.presentAddFolderPanel() }
                    }
                case .inactive:
                    ContentUnavailableView("Nothing Inactive", systemImage: "checkmark.circle",
                                           description: Text("Every font in your library is turned on."))
                case .active:
                    ContentUnavailableView("Nothing Active", systemImage: "circle.dashed",
                                           description: Text("Turn a font on and it shows up here."))
                case .collection:
                    ContentUnavailableView("Empty Collection", systemImage: "rectangle.stack",
                                           description: Text("Drag fonts onto the collection in the sidebar, or right-click a font and choose Collections."))
                case .style:
                    ContentUnavailableView("No Fonts in This Style", systemImage: "textformat",
                                           description: Text("Right-click a font and choose Style to put it here."))
                default:
                    ContentUnavailableView("No Fonts", systemImage: "textformat")
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                viewMode = viewMode == .grid ? .list : .grid
            } label: {
                Image(systemName: viewMode == .grid ? "rectangle.grid.1x3" : "square.grid.2x2")
            }
            .help(viewMode == .grid ? "Show as List" : "Show as Grid")
        }
        ToolbarItem {
            SliderMenuControl(value: $pointSize, range: 8...200, presets: [12, 18, 24, 36, 48, 64, 96, 144], unit: " pt")
                .help("Preview size")
        }
        ToolbarItem {
            SliderMenuControl(value: $weight, range: 100...900, presets: [100, 200, 300, 400, 500, 600, 700, 800, 900], unit: "")
                .help("Preview weight")
        }
        ToolbarItem {
            SampleTextControl(text: $sampleText)
        }
        ToolbarItem {
            ColorChips(mode: $colorMode, foregroundHex: $customForeground, backgroundHex: $customBackground)
        }
        ToolbarItem { InfoToolbarButton() }
            .sharedBackgroundVisibility(.hidden)
    }
}

// MARK: - Cards

struct FontPreviewText: View {
    let text: String
    let face: FontFace
    let size: Double
    let weight: Double
    var features: [FeatureSetting] = []
    let color: Color

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(Font(FontCache.shared.font(face, size: size, weight: weight, features: features)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct FontCard: View {
    let family: FontFamily
    let sample: String
    let pointSize: Double
    let weight: Double
    let colors: PreviewColors
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FontPreviewText(text: sample, face: family.face(nearestWeight: Int(weight)).face, size: pointSize, weight: weight, color: colors.foreground)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: max(130, pointSize * 2.6))
            FamilyCaption(family: family, color: colors.foreground)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .background(colors.background)
        .overlay(alignment: .trailing) { Rectangle().fill(colors.foreground.opacity(0.08)).frame(width: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(colors.foreground.opacity(0.08)).frame(height: 1) }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .padding(3)
            }
        }
    }
}

struct FontListRow: View {
    let family: FontFamily
    let sample: String
    let pointSize: Double
    let weight: Double
    let colors: PreviewColors
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            FamilyCaption(family: family, color: colors.foreground)
                .frame(width: 220, alignment: .leading)
            FontPreviewText(text: sample, face: family.face(nearestWeight: Int(weight)).face, size: pointSize, weight: weight, color: colors.foreground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: max(56, pointSize * 1.7))
        .background(isSelected ? Color.accentColor.opacity(0.15) : colors.background)
        .overlay(alignment: .bottom) { Rectangle().fill(colors.foreground.opacity(0.08)).frame(height: 1) }
    }
}

/// Family name, status tag and style count under a preview.
struct FamilyCaption: View {
    let family: FontFamily
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(family.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                StatusTag(status: family.status)
            }
            Text(family.stylesLabel)
                .font(.system(size: 10))
                .opacity(0.6)
        }
        .foregroundStyle(color.opacity(0.7))
    }
}

struct StatusTag: View {
    let status: FamilyStatus

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(tint.opacity(0.12), in: .capsule)
                .foregroundStyle(tint.opacity(0.85))
        }
    }

    private var text: String? {
        switch status {
        case .system: "System"
        case .partial: "Partly active"
        case .appOnly(let app): app
        case .active, .inactive: nil
        }
    }

    private var tint: Color {
        switch status {
        case .appOnly: .red
        case .partial: .orange
        default: .secondary
        }
    }
}

// MARK: - Toolbar controls

/// Shows or hides the inspector (Info and, inside a font, Features). Drawn as its own glass
/// capsule so it doesn't merge into the neighbouring toolbar group.
struct InfoToolbarButton: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button {
            library.isInspectorPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help("Info")
    }
}

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

struct SampleTextControl: View {
    @Binding var text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "character.cursor.ibeam")
        }
        .help("Sample text")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample Text").font(.headline)
                TextField("Sample text", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    ForEach(["Aa 123", "Hamburgefonstiv", "The quick brown fox"], id: \.self) { preset in
                        Button(preset) { text = preset }
                            .controlSize(.small)
                    }
                }
            }
            .padding(14)
        }
    }
}

struct ColorChips: View {
    @Binding var mode: PreviewColorMode
    @Binding var foregroundHex: String
    @Binding var backgroundHex: String
    @State private var editingCustom = false

    var body: some View {
        HStack(spacing: 4) {
            chip(.light, fill: AnyShapeStyle(Color.white))
            chip(.dark, fill: AnyShapeStyle(Color.black))
            chip(.custom, fill: AnyShapeStyle(LinearGradient(colors: [.red, .orange, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .popover(isPresented: $editingCustom, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ColorPicker("Text", selection: hexBinding($foregroundHex), supportsOpacity: false)
                        ColorPicker("Background", selection: hexBinding($backgroundHex), supportsOpacity: false)
                    }
                    .padding(14)
                    .frame(width: 200)
                }
        }
        .padding(.horizontal, 4)
    }

    private func chip(_ chipMode: PreviewColorMode, fill: AnyShapeStyle) -> some View {
        Button {
            if chipMode == .custom && mode == .custom { editingCustom.toggle() }
            mode = chipMode
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(fill)
                .frame(width: 26, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .padding(2)
                .overlay {
                    if mode == chipMode {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(chipMode == .custom ? "Custom colors (click again to edit)" : chipMode == .light ? "Light" : "Dark")
    }

    private func hexBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) ?? .white }, set: { hex.wrappedValue = $0.hexString })
    }
}
