import PointCore
import SwiftUI

/// The families of the sidebar selection as a list, a grid or specimens, or the Problems view.
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("browser.mode") private var mode: BrowserMode = .grid

    var body: some View {
        Group {
            if model.selection == .problems {
                ProblemsView()
            } else {
                browser
            }
        }
        .modifier(InfoPanelColumn())
    }

    private var browser: some View {
        @Bindable var model = model
        let families = model.visibleFamilies
        return Group {
            switch mode {
            case .list: FontList(families: families)
            case .grid: FontGrid(families: families)
            case .specimens: SpecimenList(families: families)
            }
        }
        .overlay { EmptyBrowser(isEmpty: families.isEmpty) }
        .overlay(alignment: .bottomTrailing) { ScanCapsule() }
        .navigationTitle(model.selectionTitle)
        .navigationSubtitle(subtitle(families))
        .toolbar { toolbar }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search")
    }

    private func subtitle(_ families: [Family]) -> String {
        let count = families.count == 1 ? "1 family" : "\(families.count.formatted()) families"
        if let progress = model.coverageProgress, dependsOnCoverage {
            return "\(count) · checking characters, \(progress.done.formatted()) of \(progress.total.formatted())"
        }
        return "\(count) · \(families.count(where: \.hasActive).formatted()) activated"
    }

    /// Whether the list can still grow while coverage is being worked out.
    private var dependsOnCoverage: Bool {
        switch model.selection {
        case .characterSet: true
        case .smartSet(let id):
            model.data.smartSets.first { $0.id == id }?.rules.contains { $0.field == .language || $0.field == .characterSet } ?? false
        default: false
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $mode) {
                ForEach(BrowserMode.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Show as a list, a grid or specimens")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem { SlideshowButton() }
        ToolbarItem { PreviewOptionsButton() }
        ToolbarSpacer(.fixed)
        ToolbarItem { InfoButton() }
    }
}

private struct SlideshowButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            model.prepareSlideshow(model.selectedFamilies)
            openWindow(id: WindowID.slideshow)
        } label: {
            Label("Slideshow", systemImage: "play.rectangle")
        }
        .help("Show these fonts one at a time, full screen")
        .disabled(model.library.families.isEmpty)
    }
}

/// The scanning capsule; its own view so progress messages don't re-render the list.
private struct ScanCapsule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let progress = model.scanProgress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text(for: progress)).font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(16)
        }
    }

    private func text(for progress: ScanProgress) -> String {
        switch progress {
        case .finding: "Finding fonts…"
        case .identifying(let done, let total): "Identifying fonts… \(done.formatted()) of \(total.formatted())"
        }
    }
}

private struct EmptyBrowser: View {
    @Environment(AppModel.self) private var model
    let isEmpty: Bool

    var body: some View {
        if isEmpty && model.hasScanned {
            let query = model.appliedSearch.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection ?? .all {
        case .inactive where model.data.folders.isEmpty:
            ContentUnavailableView {
                Label("No Watched Folders", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a folder of fonts to browse them here. Nothing gets installed until you activate it.")
            } actions: {
                Button("Add Folder…") { model.presentAddFolderPanel() }
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
                if let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                    Button("Edit Smart Set…") { model.editingSmartSet = smartSet }
                }
            }
        case .characterSet(let id) where model.coverageProgress != nil:
            ContentUnavailableView("Checking Characters…", systemImage: "character.textbox",
                                   description: Text("Fonts that have every character of \(model.characterSet(id)?.name ?? "this set") will show up here."))
        case .characterSet(let id):
            ContentUnavailableView("No Fonts with Every Character", systemImage: "character.textbox",
                                   description: Text("None of these fonts have all the characters in \(model.characterSet(id)?.name ?? "this set")."))
        default:
            ContentUnavailableView("No Fonts", systemImage: "textformat")
        }
    }
}
