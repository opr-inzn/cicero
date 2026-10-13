import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// Font files opened or dropped, waiting for the scan that lists them.
struct OpenedFiles {
    var scan: Int
    var paths: Set<String>
    /// The set they were dropped into, which they join.
    var set: UUID?
    /// One family opened from the Finder opens on its font page.
    var showsPage: Bool
}

extension AppModel {
    /// The kinds of font file Cicero reads, for open panels.
    static var fontTypes: [UTType] {
        FontFormat.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    // MARK: Adding

    /// File → Add Fonts…: font files to list where they are, without installing them.
    func presentAddFontsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.fontTypes
        panel.prompt = "Add"
        panel.message = "Choose font files. They’re listed in your library where they are, without being installed."
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Font files, folders and documents opened from the Finder, dropped on the window or chosen in Add Fonts….
    /// Folders are added as folders; font files the library doesn't have yet are listed where they are. Once a
    /// scan has read them, the browser shows their families, selected, or with `showsPage` one family's page.
    /// Dropped into a set, they join it. A document (PDF, IDML, InDesign, Illustrator) shows the fonts it uses.
    /// Several arriving one by one, as from the Finder, are added together.
    func open(_ urls: [URL], into set: UUID? = nil, showsPage: Bool = false) {
        openQueue.urls += urls
        openQueue.set = openQueue.set ?? set
        openQueue.showsPage = openQueue.showsPage || showsPage
        openQueue.task?.cancel()
        openQueue.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.openWaitingFiles()
        }
    }

    /// Adds what `open` gathered, once the library has been scanned for the first time.
    func openWaitingFiles() {
        guard started, !openQueue.urls.isEmpty else { return }
        let (urls, set, showsPage, _) = openQueue
        openQueue = ([], nil, false, nil)
        let fm = FileManager.default
        var folders: [URL] = []
        var files: [String] = []
        var documents: [URL] = []
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let pathExtension = url.pathExtension.lowercased()
            if isDirectory.boolValue {
                if !NSWorkspace.shared.isFilePackage(atPath: url.path) { folders.append(url) }
            } else if FontFormat.fileExtensions.contains(pathExtension), !files.contains(url.path) {
                files.append(url.path)
            } else if DocumentFonts.fileExtensions.contains(pathExtension) {
                documents.append(url)
            }
        }
        // One document at a time: the sheet shows one.
        if let document = documents.first { findFonts(in: document) }
        guard !folders.isEmpty || !files.isEmpty else {
            guard documents.isEmpty else { return }
            return showToast(urls.count == 1 ? "That isn’t a font Cicero can read." : "Those aren’t fonts Cicero can read.")
        }
        if !folders.isEmpty {
            let before = Set(data.folders.map(\.id))
            addFolders(folders)
            // One folder alone: show its fonts.
            let added = data.folders.filter { !before.contains($0.id) }
            if files.isEmpty, added.count == 1 { selection = .folder(added[0].id) }
        }
        guard !files.isEmpty else { return }
        addFontFiles(files, rescanning: false)
        awaitingScan = OpenedFiles(scan: rescan(), paths: Set(files), set: set, showsPage: showsPage)
    }

    /// Lists the font files the library doesn't have yet where they are, under Added Fonts.
    func addFontFiles(_ paths: [String], rescanning: Bool = true) {
        let new = paths.filter { !isListed($0) }
        guard !new.isEmpty else { return }
        data.fontFiles += new
        data.sidebar.hidden.remove(SidebarSection.folders.key)
        data.sidebar.hidden.remove("folder.\(WatchedFolder.addedFilesID)")
        if rescanning { rescan() }
    }

    /// Whether the library lists a file already, or will by itself: one of its faces or their other copies is
    /// the file, or it's in a folder Cicero reads anyway.
    private func isListed(_ path: String) -> Bool {
        if data.fontFiles.contains(path) { return true }
        let folders = [locations.userFonts.path, locations.allUsersFonts.path, locations.deactivated.path] + data.scannedFolders().map(\.path)
        if folders.contains(where: { path.hasPrefix($0 + "/") }) { return true }
        return library.families.contains { $0.faces.contains { $0.face.path == path || $0.otherCopies.contains(path) } }
    }

    /// Shows the families of files `open` added, once scan `id` has listed them: in Added Fonts, or the set
    /// they joined, or the sidebar item shown when it has them all, else in All Fonts.
    func showOpenedFiles(after id: Int) {
        guard let opened = awaitingScan, id >= opened.scan else { return }
        awaitingScan = nil
        let paths = opened.paths
        let found = library.families.filter { family in
            family.faces.contains { paths.contains($0.face.path) || $0.otherCopies.contains(where: paths.contains) }
        }
        guard !found.isEmpty else {
            let name = paths.count == 1 ? URL(fileURLWithPath: paths.first!).lastPathComponent : nil
            return showToast(name.map { "Couldn’t read “\($0)”." } ?? "Couldn’t read these fonts.")
        }
        // With system fonts hidden, a font that comes with macOS is nowhere to show.
        let families = found.filter { data.showSystemFonts || $0.state != .system }
        guard !families.isEmpty else {
            return showToast("That font comes with macOS, and system fonts are hidden (Settings → General).")
        }
        if let set = opened.set, let name = data.sets.first(where: { $0.id == set })?.name {
            setMembership(true, for: families, in: set)
            showToast(families.count == 1 ? "Added \(families[0].name) to “\(name)”." : "Added \(families.count) families to “\(name)”.")
        }
        let ids = Set(families.map(\.id))
        // Added files in Added Fonts, a short list where they're in view (the browser doesn't scroll to a
        // selection), unless they joined the set shown; others where the browser shows them, else in All Fonts.
        let added = families.allSatisfy { $0.folderIDs.contains(WatchedFolder.addedFilesID) }
        if added && opened.set == nil {
            searchText = ""
            selection = .folder(WatchedFolder.addedFilesID)
        } else if !ids.isSubset(of: Set(visibleFamilies.map(\.id))) {
            searchText = ""
            selection = .all
        }
        selectedIDs = ids
        if opened.showsPage && families.count == 1 { openFamilyID = families[0].id }
    }

    // MARK: Removing

    /// Families whose every file was added one at a time, which can leave the library again.
    func canRemoveFromLibrary(_ families: [Family]) -> Bool {
        let added = Set(data.fontFiles)
        return !families.isEmpty && families.allSatisfy { $0.faces.allSatisfy { added.contains($0.face.path) } }
    }

    /// Stops listing the families' added files. The files stay where they are; an active font stays listed.
    func removeFromLibrary(_ families: [Family]) {
        let paths = Set(families.flatMap(\.faces).flatMap { [$0.face.path] + $0.otherCopies })
        data.fontFiles.removeAll(where: paths.contains)
        rescan()
    }
}
