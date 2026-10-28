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
        .topBar {
            if let id = model.similarFamilyID {
                SimilarBar(familyID: id)
            } else if let list = model.documentList {
                ListBar(symbol: "doc.text.magnifyingglass", message: "The fonts “\(list.name)” uses that are in your library.") {
                    model.endDocumentList()
                }
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
        model.pageContents.prepare(model.previewStyle(of: family, weight: preview.weight).face.face)
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
            .glass(in: .capsule)
            .padding(16)
        }
    }

    private func text(for progress: ScanProgress) -> String {
        switch progress {
        case .finding: "Finding fonts"
        case .identifying(let done, let total): "Identifying fonts, \(done.formatted()) of \(total.formatted())"
        case .updating(let done, let total): "Updating font details, \(done.formatted()) of \(total.formatted())"
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

/// Says whose similar fonts the browser shows, with a button to go back to what the sidebar showed.
private struct SimilarBar: View {
    @Environment(AppModel.self) private var model
    let familyID: String

    var body: some View {
        ListBar(symbol: "sparkle.magnifyingglass", message: message, isWorking: model.measurementProgress != nil) {
            model.endSimilar()
        }
    }

    private var message: String {
        let name = model.family(familyID)?.name ?? familyID
        if let family = model.family(familyID), model.canShowSimilar(family) {
            return "The families that look most like \(name), the closest first."
        }
        if let progress = model.measurementProgress {
            return "Measuring letters, \(progress.done.formatted()) of \(progress.total.formatted())"
        }
        return "Cicero can’t compare \(name) with other fonts: it hasn’t got the Latin letters Cicero measures."
    }
}

/// Above a list the browser shows instead of a sidebar item's (Show Similar Fonts, Show in Library): what it is, and
/// Done, the way back.
private struct ListBar: View {
    let symbol: String
    let message: String
    var isWorking = false
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(message)
                    .lineLimit(1)
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                // Text in the accent colour, as the bar's way back.
                Button("Done", action: done)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Go back to what the sidebar showed")
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
            EmptyState("Cicero Can’t Read “\(name)”", systemImage: "lock",
                       description: Text("macOS hasn’t let Cicero into this folder. Allow it in System Settings → Privacy & Security → Files and Folders, then try again.")) {
                Button("Open Privacy & Security") { model.openFilesAndFoldersSettings() }
                Button("Try Again") { model.rescan() }
            }
        case .disconnected(let volume):
            EmptyState("“\(volume)” Isn’t Connected", systemImage: "externaldrive.badge.questionmark",
                       description: Text("The fonts in “\(name)” are back as soon as you connect it. Their folders and tags stay as they are.")) {
                Button("Try Again") { model.rescan() }
            }
        case .notFound:
            EmptyState("Can’t Find “\(name)”", systemImage: "questionmark.folder",
                       description: Text("Nothing is at \(((folder?.path ?? "") as NSString).abbreviatingWithTildeInPath) now. If it’s on a disk or a server, connect it. If it moved, remove it from the library and add it again.")) {
                Button("Try Again") { model.rescan() }
                Button("Remove Location from Library") { model.removeFolder(folderID) }
            }
        case nil:
            let count = model.onlineOnlyCount(inFolder: folderID)
            EmptyState("Online Only", systemImage: "icloud.and.arrow.down",
                       description: Text(count == 1
                           ? "The font file here is online only: the cloud service keeps it off this Mac. Download it to see it. To keep it on this Mac, make the folder available offline in the Finder."
                           : "The \(count.formatted()) font files here are online only: the cloud service keeps them off this Mac. Download them to see them. To keep them on this Mac, make the folder available offline in the Finder.")) {
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
            EmptyState.search(text: query)
        } else if !model.searchTokens.isEmpty {
            EmptyState.search()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.similarFamilyID != nil {
            // Only when the family is gone, or hidden: it comes first otherwise.
            EmptyState("Font Not Available", systemImage: "textformat",
                       description: Text("This font is no longer in your library."))
        } else if let list = model.documentList {
            EmptyState("No Fonts in Your Library", systemImage: "doc.text.magnifyingglass",
                       description: Text("None of the fonts “\(list.name)” uses are in your library."))
        } else {
            sidebarItemContent
        }
    }

    @ViewBuilder
    private var sidebarItemContent: some View {
        switch model.selection ?? .all {
        case .folder(let id) where model.availability(ofFolder: id) != nil || model.onlineOnlyCount(inFolder: id) > 0:
            FolderOutOfReach(folderID: id)
        case .inactive:
            // With no locations of their own too: what's here is what's on, and Proofing may well be under Locations.
            // The same whatever "When you add font files" says: a location keeps its fonts off with every choice.
            EmptyState("Everything Is Active", systemImage: "checkmark.seal",
                       description: Text("Every font in your library is turned on. Add a folder of fonts to keep more here without activating them.")) {
                Button("Add Location") { model.presentAddFolderPanel() }
            }
        case .active:
            EmptyState("Nothing Active", systemImage: "xmark.seal",
                       description: Text("Turn a font on and it shows up here."))
        case .temporary:
            EmptyState("No Temporary Fonts", systemImage: "clock",
                       description: Text("Fonts you activate temporarily show up here until Cicero quits."))
        case .recent:
            EmptyState("No Recent Fonts", systemImage: "tray.and.arrow.down",
                       description: Text("Fonts that arrive on your Mac show up here for a week."))
        case .set:
            EmptyState("Empty Folder", systemImage: "folder",
                       description: Text("Drag fonts onto the folder in the sidebar, or right-click a font and choose Add to Folder."))
        case .smartSet(let id):
            EmptyState("No Matching Fonts", systemImage: "gearshape",
                       description: Text("No fonts in your library match this smart folder’s rules.")) {
                if let smartSet = model.data.smartSets.first(where: { $0.id == id }) {
                    Button("Edit Smart Folder") { model.editingSmartSet = smartSet }
                }
            }
        case .characterSet(let id) where model.coverageProgress != nil:
            EmptyState("Checking Characters", systemImage: "character.textbox",
                       description: Text("Fonts that have every character of \(model.characterSet(id)?.name ?? "this set") will show up here."))
        case .characterSet(let id):
            EmptyState("No Fonts with Every Character", systemImage: "character.textbox",
                       description: Text("None of these fonts have all the characters in \(model.characterSet(id)?.name ?? "this set")."))
        default:
            EmptyState("No Fonts", systemImage: "textformat")
        }
    }
}
