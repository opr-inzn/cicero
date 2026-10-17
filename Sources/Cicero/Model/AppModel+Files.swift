import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// Font files opened or dropped, waiting for the scan that lists them.
struct OpenedFiles {
    var scan: Int
    var paths: Set<String>
    /// The set they were dropped into, which they join.
    var set: UUID?
}

extension AppModel {
    /// The kinds of font file Cicero reads, for open panels.
    static var fontTypes: [UTType] {
        FontFormat.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    // MARK: Adding

    /// File → Add Fonts…: font files to list where they are, without installing them, or to install with fonts
    /// activated by copying or moving.
    func presentAddFontsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.fontTypes
        panel.prompt = installsAddedFiles ? "Install" : "Add"
        panel.message = switch data.installMethod {
        case .copy: "Choose font files. They’re copied into your Fonts folder and turned on. The originals stay where they are."
        case .move: "Choose font files. They’re moved into your Fonts folder and turned on. A folder they leave empty goes to the Trash."
        case .ask, .inPlace: "Choose font files. They’re listed in your library where they are, without being activated."
        }
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Font files, folders and documents opened from the Finder, dropped on the window or chosen in Add Fonts….
    /// Folders are added as folders; font files the library doesn't have yet are listed where they are, or
    /// installed with fonts activated by copying or moving (see `addFontFiles`). Once a scan has read them, the browser
    /// goes to the first of their families, selected (see `showOpenedFiles`).
    /// Dropped into a set, they join it. A document (PDF, IDML, InDesign, Illustrator) shows the fonts it uses.
    /// Several arriving one by one, as from the Finder, are added together.
    func open(_ urls: [URL], into set: UUID? = nil) {
        openQueue.urls += urls
        openQueue.set = openQueue.set ?? set
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
        let (urls, set, _) = openQueue
        openQueue = ([], nil, nil)
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
            return showToast(urls.count == 1 ? "That isn’t a font Cicero can read" : "Those aren’t fonts Cicero can read")
        }
        if !folders.isEmpty {
            let before = Set(data.folders.map(\.id))
            addFolders(folders)
            // One folder alone: show its fonts.
            let added = data.folders.filter { !before.contains($0.id) }
            if files.isEmpty, added.count == 1 { selection = .folder(added[0].id) }
        }
        guard !files.isEmpty else { return }
        addFontFiles(files) { model, paths in
            model.awaitingScan = OpenedFiles(scan: model.rescan(), paths: paths, set: set)
        }
    }

    /// Whether font files the user adds are installed rather than listed where they are: with fonts activated by
    /// copying or moving.
    var installsAddedFiles: Bool { data.installMethod == .copy || data.installMethod == .move }

    /// Brings in the font files the library doesn't have yet: lists them where they are, under Added Fonts, or with
    /// fonts activated by copying or moving, copies or moves them into ~/Library/Fonts, where they're on and in All
    /// Fonts like any installed font, along with files under Added Fonts that are off. `mayMove` false copies them
    /// even then, for files the user didn't pick, like one Spotlight found. Then rescans, or `then` does, given
    /// the paths the library has the files at: the copies' for files it installed.
    func addFontFiles(_ paths: [String], mayMove: Bool = true, then: ((AppModel, Set<String>) -> Void)? = nil) {
        let movable = movableFiles(among: paths)
        let installing = !installsAddedFiles ? [] : paths.filter { path in
            !isListed(path) || movable.contains(path) && !library.activePaths.contains(path)
        }
        let moving = mayMove && data.installMethod == .move
        guard !installing.isEmpty else {
            let new = paths.filter { !isListed($0) }
            if !new.isEmpty {
                data.fontFiles += new
                data.sidebar.hidden.remove(SidebarSection.folders.key)
                data.sidebar.hidden.remove("folder.\(WatchedFolder.addedFilesID)")
            }
            if let then { then(self, Set(paths)) } else if !new.isEmpty { rescan() }
            return
        }
        let shown = Set(paths).subtracting(installing)
        enqueue { model in
            let result = await model.engine.install(installing, moving: moving, records: model.data.records)
            model.data.records = result.records
            model.forgetInstalledAddedFiles()
            model.showToast(result.message)
            let originals = Set(installing)
            let copies = Set(result.records.installedCopies.filter { originals.contains($0.value) }.keys)
            // Nothing to show when nothing went in: the toast says so.
            if let then, !copies.isEmpty || !shown.isEmpty { then(model, shown.union(copies)) } else { model.rescan() }
        }
    }

    /// Added files Cicero installed a copy of leave Added Fonts: the copy in ~/Library/Fonts is the font in the
    /// library now, in All Fonts like any installed font, and what Reveal in Finder shows. For the records an
    /// operation leaves, before the scan after it.
    func forgetInstalledAddedFiles() {
        let installed = Set(data.records.installedCopies.values)
        guard data.fontFiles.contains(where: installed.contains) else { return }
        data.fontFiles.removeAll(where: installed.contains)
    }

    /// Whether the library lists a file already, or will by itself: one of its faces or their other copies is
    /// the file, or it's in a folder Cicero reads anyway.
    private func isListed(_ path: String) -> Bool {
        if data.fontFiles.contains(path) || isInReadFolder(path) { return true }
        return library.families.contains { $0.faces.contains { $0.face.path == path || $0.otherCopies.contains(path) } }
    }

    /// In a Fonts folder, the Deactivated folder or a watched folder.
    private func isInReadFolder(_ path: String) -> Bool {
        let folders = [locations.userFonts.path, locations.allUsersFonts.path, locations.deactivated.path] + data.scannedFolders().map(\.path)
        return folders.contains { path.hasPrefix($0 + "/") }
    }

    /// The files among `paths` added one at a time and in no folder the library reads: activating by moving moves
    /// them, where it copies a folder's fonts, so the user's folders stay as they are.
    func movableFiles(among paths: [String]) -> Set<String> {
        let added = Set(data.fontFiles)
        return Set(paths.filter { added.contains($0) && !isInReadFolder($0) })
    }

    /// Shows the families of files `open` added, once scan `id` has listed them: in Added Fonts, or the set
    /// they joined, or the sidebar item shown when it has them all, else in All Fonts (where installed ones go).
    /// The browser goes to the first of them, selected, rather than a font page opening.
    func showOpenedFiles(after id: Int) {
        guard let opened = awaitingScan, id >= opened.scan else { return }
        awaitingScan = nil
        let paths = opened.paths
        let found = library.families.filter { family in
            family.faces.contains { paths.contains($0.face.path) || $0.otherCopies.contains(where: paths.contains) }
        }
        guard !found.isEmpty else {
            let name = paths.count == 1 ? URL(fileURLWithPath: paths.first!).lastPathComponent : nil
            return showToast(name.map { "Couldn’t read “\($0)”" } ?? "Couldn’t read these fonts")
        }
        // With system fonts hidden, a font that comes with macOS is nowhere to show; so is one from Creative Cloud.
        let families = found.filter(data.lists)
        guard !families.isEmpty else {
            return showToast(found[0].state == .system
                ? "That font comes with macOS, and system fonts are hidden (Settings → General)"
                : "That font is from Adobe Fonts, which are hidden (Settings → General)")
        }
        if let set = opened.set, let name = data.sets.first(where: { $0.id == set })?.name {
            setMembership(true, for: families, in: set)
            showToast(families.count == 1 ? "Added \(families[0].name) to “\(name)”" : "Added \(families.count) families to “\(name)”")
        }
        let ids = Set(families.map(\.id))
        // Added files in Added Fonts, unless they joined the set shown; others where the browser shows them, else
        // in All Fonts.
        let added = families.allSatisfy { $0.folderIDs.contains(WatchedFolder.addedFilesID) }
        if added && opened.set == nil {
            searchText = ""
            selection = .folder(WatchedFolder.addedFilesID)
        } else if !ids.isSubset(of: Set(visibleFamilies.map(\.id))) {
            searchText = ""
            selection = .all
        }
        selectedIDs = [families[0].id]
        openFamilyID = nil
        jumpTargets = ids
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
