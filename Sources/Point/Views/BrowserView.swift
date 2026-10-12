import AppKit
import SwiftUI

enum BrowserMode: String {
    case list, grid, specimens
}

/// The font browser: a sortable table, or full-width specimens, of the families in the sidebar selection.
struct BrowserView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("browser.mode") private var mode: BrowserMode = .list

    var body: some View {
        Group {
            if library.sidebarSelection == .problems {
                ProblemsView()
            } else {
                browser
            }
        }
        .modifier(LibraryInspector())
    }

    private var browser: some View {
        @Bindable var library = library
        let families = library.visibleFamilies
        return Group {
            switch mode {
            case .list: FontTable(families: families)
            case .grid: FontGrid(families: families)
            case .specimens: SpecimenList(families: families)
            }
        }
        .overlay { emptyState(isEmpty: families.isEmpty) }
        .overlay(alignment: .bottomTrailing) { ScanStatus() }
        .navigationTitle(library.selectionTitle)
        .navigationSubtitle(subtitle(for: families))
        .toolbar { toolbar }
        .searchable(text: $library.searchText, placement: .toolbar, prompt: "Search")
    }

    private func subtitle(for families: [FontFamily]) -> String {
        let activated = families.filter(\.hasActiveFaces).count
        let count = families.count == 1 ? "1 family" : "\(families.count.formatted()) families"
        let coverage = CharacterCoverage.shared
        if coverage.isIndexing && dependsOnCoverage {
            return "\(count) · checking characters, \(coverage.indexedCount.formatted()) of \(coverage.totalCount.formatted())"
        }
        return "\(count) · \(activated.formatted()) activated"
    }

    /// Whether the list can still grow while character coverage is being worked out.
    private var dependsOnCoverage: Bool {
        switch library.sidebarSelection {
        case .characterSet: true
        case .smartSet(let id): library.smartSet(id)?.rules.contains { $0.field == .language || $0.field == .characterSet } ?? false
        default: false
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty && library.hasScanned {
            let query = library.appliedSearch.trimmingCharacters(in: .whitespaces)
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
                    ContentUnavailableView("Everything Is Activated", systemImage: "circle.inset.filled",
                                           description: Text("Every font in your library is turned on."))
                case .active:
                    ContentUnavailableView("Nothing Activated", systemImage: "circle",
                                           description: Text("Turn a font on and it shows up here."))
                case .set:
                    ContentUnavailableView("Empty Set", systemImage: "square.stack",
                                           description: Text("Drag fonts onto the set in the sidebar, or right-click a font and choose Add to Set."))
                case .tag:
                    ContentUnavailableView("No Fonts with This Tag", systemImage: "tag",
                                           description: Text("Right-click a font and choose Tags to add it here."))
                case .smartSet(let id):
                    ContentUnavailableView {
                        Label("No Matching Fonts", systemImage: "gearshape")
                    } description: {
                        Text("No fonts in your library match this smart set’s rules.")
                    } actions: {
                        if let smartSet = library.smartSet(id) {
                            Button("Edit Smart Set…") { library.editingSmartSet = smartSet }
                        }
                    }
                case .characterSet(let id) where CharacterCoverage.shared.isIndexing:
                    ContentUnavailableView("Checking Characters…", systemImage: "character.textbox",
                                           description: Text("Fonts that have every character of \(library.characterSet(id)?.name ?? "this set") will show up here."))
                case .characterSet(let id):
                    ContentUnavailableView("No Fonts with Every Character", systemImage: "character.textbox",
                                           description: Text("None of these fonts have all the characters in \(library.characterSet(id)?.name ?? "this set")."))
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
            Picker("View", selection: $mode) {
                Label("List", systemImage: "list.bullet").tag(BrowserMode.list)
                Label("Grid", systemImage: "square.grid.2x2").tag(BrowserMode.grid)
                Label("Specimens", systemImage: "rectangle.grid.1x2").tag(BrowserMode.specimens)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Show as a list, a grid or specimens")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem { SlideshowToolbarButton() }
        ToolbarItem { PreviewOptionsButton() }
        ToolbarSpacer(.fixed)
        ToolbarItem { InfoToolbarButton() }
    }
}

// MARK: - Shared pieces

struct FontPreviewText: View {
    let text: String
    let face: FontFace
    let size: Double
    let weight: Double
    var features: [FeatureSetting] = []
    var kerning: Double = 0

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(Font(FontCache.shared.font(face, size: size, weight: weight, features: features)))
            .kerning(kerning)
            .lineLimit(1)
    }
}

/// On/off switch for a whole family. Off deactivates every style Point can control. The library
/// is passed in rather than read from the environment: AppKit can build table cells outside
/// SwiftUI's update, where the environment isn't available yet.
struct ActivationSwitch: View {
    let family: FontFamily
    let library: LibraryStore

    var body: some View {
        let isOn = family.hasActiveFaces
        let isEnabled = family.hasActivatableFaces || family.hasDeactivatableFaces
        MiniSwitch(isOn: isOn, isEnabled: isEnabled) { toggle(isOn) }
            .help(helpText)
            .accessibilityElement()
            .accessibilityLabel("Activated")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { if isEnabled { toggle(isOn) } }
    }

    private func toggle(_ isOn: Bool) {
        isOn ? library.requestDeactivate([family]) : library.requestActivate([family])
    }

    private var helpText: String {
        switch family.status {
        case .system: "Installed with macOS"
        case .appOnly(let app): "On in \(app) apps only. Turn on to use it in every app."
        default: family.hasActiveFaces ? "Deactivate" : "Activate"
        }
    }
}

struct StatusTag: View {
    let status: FamilyStatus
    /// Set when every active style is on for this session only, e.g. "Active until Point quits".
    var temporaryLabel: String?

    init(status: FamilyStatus) {
        self.status = status
    }

    init(family: FontFamily) {
        status = family.status
        if family.isTemporarilyActive { temporaryLabel = family.faces.first(where: \.isTemporary)?.status.label }
    }

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(tint.opacity(0.12), in: .capsule)
                .foregroundStyle(tint.opacity(0.85))
                .help(temporaryLabel ?? "")
        }
    }

    private var text: String? {
        switch status {
        case .system: "System"
        case .partial: "Partly active"
        case .appOnly(let app): app
        case .active: temporaryLabel == nil ? nil : "Temporary"
        case .inactive: nil
        }
    }

    private var tint: Color {
        switch status {
        case .appOnly: .red
        case .partial: .orange
        case .active: .blue
        default: .secondary
        }
    }
}

/// Shows or hides the inspector (Info and, inside a font, Features). Toolbars give it a group of
/// its own with a fixed spacer.
struct InfoToolbarButton: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button {
            library.isInspectorPresented.toggle()
        } label: {
            Label("Info", systemImage: "info.circle")
        }
        .help("Info")
    }
}

/// A small switch drawn in SwiftUI. Lists show one per family, and a native switch per row made
/// building the font list about a third slower.
struct MiniSwitch: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
            .onTapGesture { if isEnabled { action() } }
            .animation(.snappy(duration: 0.15), value: isOn)
    }
}

/// The scanning capsule. Its own view, so progress messages don't re-render the whole browser.
private struct ScanStatus: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
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
}
