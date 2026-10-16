import CiceroCore
import SwiftUI

/// The families of the sidebar selection as a list, a grid or specimens, or the Problems view.
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("browser.mode") private var mode: BrowserMode = .grid

    var body: some View {
        if model.selection == .problems {
            ProblemsView()
        } else {
            browser
        }
    }

    private var browser: some View {
        @Bindable var model = model
        let families = model.visibleFamilies
        return Group {
            if families.isEmpty && model.hasScanned {
                // Just the message on the plain background; an empty table would still draw its rows.
                EmptyBrowser()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.canvas)
            } else {
                switch mode {
                case .list: FontList()
                case .grid: FontGrid(families: families)
                case .specimens: SpecimenList(families: families)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // With nothing listed, the empty view says it instead.
            if case .folder(let id) = model.selection, !families.isEmpty, model.onlineOnlyCount(inFolder: id) > 0 {
                OnlineOnlyBar(folderID: id)
            }
        }
        .overlay(alignment: .bottomTrailing) { ScanCapsule() }
        .onChange(of: model.selectedIDs, initial: true) { preparePage() }
        .navigationTitle(model.selectionTitle)
        .navigationSubtitle(subtitle(families))
        .toolbar { toolbar }
    }

    /// A family selected on its own is the one a double-click or Return opens: its page's ligatures and characters
    /// are worked out now, so the page has them as it opens.
    private func preparePage() {
        guard model.selectedIDs.count == 1, let id = model.selectedIDs.first, let family = model.family(id) else { return }
        model.pageContents.prepare(family.face(nearestWeight: preview.weight).face)
    }

    private func subtitle(_ families: [Family]) -> String {
        let count = families.count == 1 ? "1 family" : "\(families.count.formatted()) families"
        if let progress = model.coverageProgress, dependsOnCoverage {
            return "\(count) · checking characters, \(progress.done.formatted()) of \(progress.total.formatted())"
        }
        var parts = [count, "\(families.count(where: \.hasActive).formatted()) active"]
        // On in one app only (like Adobe's fonts folder): neither active nor inactive, so counted apart.
        let apps = families.compactMap { if case .appOnly(let app) = $0.state { app } else { nil } }
        if !apps.isEmpty {
            let place = Set(apps).count == 1 ? FaceState.appDescription(apps[0]) : "one app only"
            parts.append("\(apps.count.formatted()) in \(place)")
        }
        return parts.joined(separator: " · ")
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
        ToolbarCapsule {
            ToolbarPicker("View", values: BrowserMode.allCases, selection: $mode, title: \.title, symbol: \.icon,
                          help: "Show as a list, a grid or specimens")
        }
        ToolbarCapsule { PreviewOptionsButton() }
        ToolbarCapsule { InfoButton() }
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
        case .finding: "Finding fonts"
        case .identifying(let done, let total): "Identifying fonts, \(done.formatted()) of \(total.formatted())"
        }
    }
}

/// Says that some of a folder's fonts are online only, so they aren't listed, with a button to download them.
private struct OnlineOnlyBar: View {
    @Environment(AppModel.self) private var model
    let folderID: UUID

    var body: some View {
        let count = model.onlineOnlyCount(inFolder: folderID)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
                if let progress = model.downloads[folderID] {
                    Text("Downloading \(progress.done.formatted()) of \(progress.total.formatted())")
                    Spacer()
                    ProgressView().controlSize(.small)
                } else {
                    Text(count == 1 ? "1 font file here is online only, so it isn’t listed." : "\(count.formatted()) font files here are online only, so they aren’t listed.")
                    Spacer()
                    Button("Download") { model.downloadOnlineOnlyFonts(inFolder: folderID) }
                        .controlSize(.small)
                        .help("Download them from the cloud service so they’re listed. To keep them on this Mac, make the folder available offline in the Finder.")
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}

/// A watched folder Cicero can't read now, or one whose fonts are all online only.
private struct FolderOutOfReach: View {
    @Environment(AppModel.self) private var model
    let folderID: UUID

    var body: some View {
        let folder = model.folder(folderID)
        let name = folder?.displayName ?? "This folder"
        switch model.availability(ofFolder: folderID) {
        case .noAccess:
            ContentUnavailableView {
                Label("Cicero Can’t Read “\(name)”", systemImage: "lock")
            } description: {
                Text("macOS hasn’t let Cicero into this folder. Allow it in System Settings → Privacy & Security → Files and Folders, then try again.")
            } actions: {
                Button("Open Privacy & Security") { model.openFilesAndFoldersSettings() }
                Button("Try Again") { model.rescan() }
            }
        case .notFound:
            if let volume = folder.flatMap({ Reachability.disconnectedVolume(of: $0.path) }) {
                ContentUnavailableView {
                    Label("“\(volume)” Isn’t Connected", systemImage: "externaldrive.badge.questionmark")
                } description: {
                    Text("The fonts in “\(name)” are back as soon as you connect it. Their sets and tags stay as they are.")
                } actions: {
                    Button("Try Again") { model.rescan() }
                }
            } else {
                ContentUnavailableView {
                    Label("Can’t Find “\(name)”", systemImage: "questionmark.folder")
                } description: {
                    Text("Nothing is at \(((folder?.path ?? "") as NSString).abbreviatingWithTildeInPath) now. If it’s on a disk or a server, connect it. If it moved, remove it from the library and add it again.")
                } actions: {
                    Button("Try Again") { model.rescan() }
                    Button("Remove Folder from Library") { model.removeFolder(folderID) }
                }
            }
        case nil:
            let count = model.onlineOnlyCount(inFolder: folderID)
            ContentUnavailableView {
                Label("Online Only", systemImage: "icloud.and.arrow.down")
            } description: {
                Text(count == 1
                    ? "The font file here is online only: the cloud service keeps it off this Mac. Download it to see it. To keep it on this Mac, make the folder available offline in the Finder."
                    : "The \(count.formatted()) font files here are online only: the cloud service keeps them off this Mac. Download them to see them. To keep them on this Mac, make the folder available offline in the Finder.")
            } actions: {
                if let progress = model.downloads[folderID] {
                    ProgressView("Downloading \(progress.done.formatted()) of \(progress.total.formatted())")
                        .controlSize(.small)
                } else {
                    Button("Download") { model.downloadOnlineOnlyFonts(inFolder: folderID) }
                }
            }
        }
    }
}

private struct EmptyBrowser: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let query = model.appliedSearch.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection ?? .all {
        case .folder(let id) where model.availability(ofFolder: id) != nil || model.onlineOnlyCount(inFolder: id) > 0:
            FolderOutOfReach(folderID: id)
        case .inactive where model.data.folders.isEmpty && model.data.fontFiles.isEmpty:
            ContentUnavailableView {
                Label("No Watched Folders", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a folder of fonts, or font files, to browse them here. Nothing gets installed until you activate it.")
            } actions: {
                Button("Add Folder") { model.presentAddFolderPanel() }
                Button("Add Fonts") { model.presentAddFontsPanel() }
            }
        case .inactive:
            ContentUnavailableView {
                Label("Everything Is Active", systemImage: "checkmark.circle")
            } description: {
                Text("Every font in your library is turned on. Add a folder of fonts to keep more here without activating them.")
            } actions: {
                Button("Add Folder") { model.presentAddFolderPanel() }
            }
        case .active:
            ContentUnavailableView("Nothing Active", systemImage: "circle.dashed",
                                   description: Text("Turn a font on and it shows up here."))
        case .set:
            ContentUnavailableView("Empty Set", systemImage: "square.stack",
                                   description: Text("Drag fonts onto the set in the sidebar, or right-click a font and choose Add to Set."))
        case .smartSet(let id):
            ContentUnavailableView {
                Label("No Matching Fonts", systemImage: "gearshape")
            } description: {
                Text("No fonts in your library match this smart set’s rules.")
            } actions: {
                if let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                    Button("Edit Smart Set") { model.editingSmartSet = smartSet }
                }
            }
        case .characterSet(let id) where model.coverageProgress != nil:
            ContentUnavailableView("Checking Characters", systemImage: "character.textbox",
                                   description: Text("Fonts that have every character of \(model.characterSet(id)?.name ?? "this set") will show up here."))
        case .characterSet(let id):
            ContentUnavailableView("No Fonts with Every Character", systemImage: "character.textbox",
                                   description: Text("None of these fonts have all the characters in \(model.characterSet(id)?.name ?? "this set")."))
        default:
            ContentUnavailableView("No Fonts", systemImage: "textformat")
        }
    }
}
