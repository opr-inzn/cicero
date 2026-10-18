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
        addCheckingDuplicates(files) { model, paths in
            model.awaitingScan = OpenedFiles(scan: model.rescan(), paths: paths, set: set)
        }
    }

    /// Adds font files the user picked (see `addFontFiles`), first looking for fonts in them the library has already
    /// from other files, and doing with those as Settings → General says: asking family by family, adding them as
    /// other copies, leaving them out, or using them in place of the library's copies (see `DuplicateHandling`).
    func addCheckingDuplicates(_ paths: [String], then: @escaping (AppModel, Set<String>) -> Void) {
        let new = paths.filter { !isListed($0) }
        guard !new.isEmpty, data.duplicateHandling != .addCopy else { return addFontFiles(paths, then: then) }
        let library = library
        Task {
            let duplicates = await Task.detached(priority: .userInitiated) {
                AddedDuplicates.find(in: AddedDuplicates.faces(of: new), library: library)
            }.value
            guard !duplicates.isEmpty else { return addFontFiles(paths, then: then) }
            let handling = data.duplicateHandling
            guard handling != .ask else {
                duplicatePrompt = DuplicatePrompt(paths: paths, duplicates: duplicates, then: then)
                return
            }
            let choices = Dictionary(uniqueKeysWithValues: duplicates.map { ($0.id, $0.choice(for: handling) ?? $0.suggestion) })
            addFontFiles(paths, resolving: duplicates, choices: choices, then: then)
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
    ///
    /// `duplicates` are families the library has already, from other files, and `choices` what to do with each: a file
    /// only of families left out stays out (`then` gets the library's copies of them instead, to show), and one of
    /// families the added files take over is used in place of the library's copies (see `AddedDuplicates.replacement`).
    func addFontFiles(_ paths: [String], resolving duplicates: [AddedDuplicate] = [], choices: [String: DuplicateChoice] = [:],
                      mayMove: Bool = true, then: ((AppModel, Set<String>) -> Void)? = nil) {
        let skipped = duplicates.filter { choices[$0.id] == .skip }
        let using = duplicates.filter { choices[$0.id] == .useAdded }
        let left = Set(skipped.flatMap(\.paths)).subtracting(duplicates.filter { choices[$0.id] != .skip }.flatMap(\.paths))
        let paths = paths.filter { !left.contains($0) }
        let existing = Set(skipped.flatMap { $0.styles.map(\.face.path) })
        let skipNote = Self.skipNote(skipped)
        let replacement = AddedDuplicates.replacement(of: using, installing: installsAddedFiles, library: library, fontFiles: data.fontFiles)
        let switching = Set(replacement.switches.compactMap(\.target?.face.path))
        let movable = movableFiles(among: paths)
        let installing = !installsAddedFiles ? [] : paths.filter { path in
            !switching.contains(path) && (!isListed(path) || movable.contains(path) && !library.activePaths.contains(path))
        }
        let moving = mayMove && data.installMethod == .move
        // Copied or moved, files the library doesn't list are installed, or take over the library's copies.
        let new = installsAddedFiles ? [] : paths.filter { !isListed($0) }
        if !new.isEmpty {
            data.fontFiles += new
            data.sidebar.hidden.remove(SidebarSection.folders.key)
            data.sidebar.hidden.remove("folder.\(WatchedFolder.addedFilesID)")
        }
        guard !installing.isEmpty || !replacement.isEmpty else {
            let forgotten = Set(replacement.forgotten)
            data.fontFiles.removeAll(where: forgotten.contains)
            if !skipNote.isEmpty { showToast(skipNote) }
            let shown = Set(paths).union(existing)
            if let then, !shown.isEmpty { then(self, shown) } else if !new.isEmpty || !forgotten.isEmpty { rescan() }
            return
        }
        let shown = Set(paths).subtracting(installing).subtracting(installsAddedFiles ? switching : [])
        // Asked each time how to activate, an added font goes where the library's copy was: copied into the Fonts
        // folder in place of one Cicero installed there, else used where it is.
        let method: InstallMethod = switch data.installMethod {
        case .ask: replacement.replacesInstalledCopy ? .copy : .inPlace
        case let method: method
        }
        enqueue { model in
            var messages: [String] = []
            if !installing.isEmpty {
                let result = await model.engine.install(installing, moving: moving, records: model.data.records)
                model.data.records = result.records
                messages.append(result.message)
            }
            if !replacement.isEmpty {
                let result = await model.engine.switchCopies(replacement.switches, method: method, records: model.data.records,
                                                             movable: moving ? switching : [])
                model.data.records = result.records
                let failed = Set(result.failed)
                model.data.fontFiles.removeAll { replacement.forgotten.contains($0) && !failed.contains($0) }
                messages.append(failed.isEmpty ? Self.replacementMessage(replacement) : result.message)
            }
            model.forgetInstalledAddedFiles()
            model.showToast((messages + [skipNote]).filter { !$0.isEmpty }.joined(separator: ". "))
            let originals = Set(installing).union(switching)
            let copies = Set(model.data.records.installedCopies.filter { originals.contains($0.value) }.keys)
            let found = shown.union(copies).union(existing)
            // Nothing to show when nothing went in: the toast says so.
            if let then, !found.isEmpty { then(model, found) } else { model.rescan() }
        }
    }

    /// "Skipped Helvetica, already in your library", or nothing when no family was left out.
    private static func skipNote(_ skipped: [AddedDuplicate]) -> String {
        switch skipped.count {
        case 0: ""
        case 1: "Skipped \(skipped[0].family), already in your library"
        default: "Skipped \(skipped.count) families already in your library"
        }
    }

    /// "Using the added copy of Helvetica", once the library's copies of it went off.
    private static func replacementMessage(_ replacement: DuplicateReplacement) -> String {
        let families = replacement.families
        guard !families.isEmpty else { return "" }
        let using = families.count == 1 ? "Using the added copy of \(families[0])" : "Using the added copies of \(families.count) families"
        return using + (replacement.leavesOtherCopiesOn ? ". Another copy Cicero can’t turn off is still on, so apps may use that one" : "")
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
