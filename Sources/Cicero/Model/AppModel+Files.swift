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

    /// File → Add Fonts…: font files to install as the install method says, or as the user chooses with Ask.
    func presentAddFontsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.fontTypes
        panel.prompt = installsAddedFiles ? "Install" : "Add"
        panel.message = switch data.installMethod {
        case .copy: "Choose font files. They’re copied into \(installPlace) and turned on. The originals stay where they are."
        case .move: "Choose font files. They’re moved into \(installPlace) and turned on."
        case .inPlace: "Choose font files. They’re listed in your library where they are, without being activated."
        case .ask: "Choose font files. Cicero asks whether to copy them into \(installPlace), move them there or leave them where they are."
        }
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Font files, folders and documents opened from the Finder, dropped on or pasted into the window, or chosen in Add Fonts….
    /// Folders are added as folders; font files the library doesn't have yet are installed as the install method
    /// says (see `addFontFiles`). Once a scan has read them, the browser
    /// goes to the first of their families, selected (see `showOpenedFiles`).
    /// Dropped or pasted into a set, they join it. A document (PDF, IDML, InDesign, Illustrator, Photoshop) shows the fonts it uses.
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

    /// The set the browser shows, which fonts dropped on the window or pasted into it join.
    var setForAddedFiles: UUID? {
        guard openFamilyID == nil, selectedItems.count == 1, case .set(let id) = selection else { return nil }
        return id
    }

    /// Font files and folders copied in the Finder, which ⌘V adds.
    static var pastedFiles: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Edit → Paste in the main window: adds the files copied in the Finder as if dropped on it.
    func pasteFiles() {
        let urls = Self.pastedFiles
        if !urls.isEmpty { open(urls, into: setForAddedFiles) }
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
        // Web fonts are left out: Adobe apps don't see them in a Fonts folder, and set blank text in them used in place.
        var webFonts: Set<String> = []
        // Another font manager's library or collections open the Import sheet.
        let imports = importFiles(among: urls.filter(\.isFileURL).map(\.standardizedFileURL))
        let readFolders = readFolders
        for url in urls where url.isFileURL && !imports.contains(url.standardizedFileURL) {
            let url = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let pathExtension = url.pathExtension.lowercased()
            if isDirectory.boolValue {
                if !NSWorkspace.shared.isFilePackage(atPath: url.path) { folders.append(url) }
            } else if FontFormat.fileExtensions.contains(pathExtension), case let path = libraryPath(of: url.path, folders: readFolders), !files.contains(path) {
                files.append(path)
            } else if DocumentFonts.fileExtensions.contains(pathExtension) {
                documents.append(url)
            } else if ["woff", "woff2"].contains(pathExtension) {
                webFonts.insert(pathExtension.uppercased())
            }
        }
        // One document at a time: the sheet shows one.
        if let document = documents.first { findFonts(in: document) }
        guard !folders.isEmpty || !files.isEmpty else {
            guard documents.isEmpty, imports.isEmpty else { return }
            // "WOFF2 can’t be installed", or "Web fonts can’t be installed" for both kinds.
            if !webFonts.isEmpty { return showToast("\(webFonts.count == 1 ? webFonts.first! : "Web fonts") can’t be installed") }
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
    /// other copies, leaving them out, or putting them in place of the library's copies (see `DuplicateHandling`).
    /// Replace asks family by family too where it can't be done, and first warns when it would put a file in more than
    /// one place (`replacePrompt`).
    func addCheckingDuplicates(_ paths: [String], then: @escaping (AppModel, Set<String>) -> Void) {
        let new = paths.filter { !isListed($0) }
        guard !new.isEmpty, data.duplicateHandling != .addCopy else { return addFontFiles(paths, then: then) }
        let library = library
        Task {
            let duplicates = await Task.detached(priority: .userInitiated) {
                AddedDuplicates.find(in: AddedDuplicates.faces(of: new), library: library)
            }.value
            guard !duplicates.isEmpty else { return addFontFiles(paths, then: then) }
            let prompt = DuplicatePrompt(paths: paths, duplicates: duplicates, handling: data.duplicateHandling, then: then)
            let handling = data.duplicateHandling
            let chosen = duplicates.map { $0.choice(for: handling) }
            guard !chosen.contains(nil) else {
                duplicatePrompt = prompt
                return
            }
            if handling == .replace, duplicates.contains(where: \.replacesSeveralCopies) {
                replacePrompt = prompt
                return
            }
            addFontFiles(paths, resolving: duplicates, choices: Dictionary(uniqueKeysWithValues: zip(duplicates.map(\.id), chosen.compactMap(\.self))),
                         then: then)
        }
    }

    /// The apps open now that keep a font's old version once its file is replaced, until they restart, in this order. Tested
    /// with InDesign 2026, which drew the new file with the old one's glyphs: "Hamburg" came out as "Ibncvsh". Neither
    /// recomposing nor a new modification date helps; a restart does.
    var openAppsKeepingFonts: [String] {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [("com.adobe.InDesign", "InDesign"), ("com.adobe.illustrator", "Illustrator"), ("com.adobe.Photoshop", "Photoshop")]
            .filter { open.contains($0.0) }.map(\.1)
    }

    /// Replace, in every place the warning named (see `replacePrompt`).
    func replaceEverywhere(_ prompt: DuplicatePrompt) {
        let choices = Dictionary(uniqueKeysWithValues: prompt.duplicates.map { ($0.id, $0.choice(for: .replace) ?? $0.suggestion) })
        addFontFiles(prompt.paths, resolving: prompt.duplicates, choices: choices, then: prompt.then)
    }

    /// Whether font files the user adds are copied or moved into the Fonts folder (or Cicero's Library), rather than
    /// listed where they are, or asked about.
    var installsAddedFiles: Bool { data.installMethod == .copy || data.installMethod == .move }

    /// Where installed fonts go, for what Cicero says: "your Fonts folder", or "Cicero’s Library".
    var installPlace: String { data.installsIntoFontLibrary ? "Cicero’s Library" : "your Fonts folder" }

    /// Brings in the font files the library doesn't have yet, along with files under Added Fonts that are off, as
    /// `method` says, else the install method: copies or moves them into ~/Library/Fonts, where they're on and in All
    /// Fonts like any installed font, or lists them where they are, under Added Fonts, without turning them on. With
    /// Ask, the user says which first (`installPrompt`), when there are files the library doesn't have. `mayMove`
    /// false copies them rather than moving them, for files the user didn't pick, like one Spotlight found. Then
    /// rescans, or `then` does, given the paths the library has the files at: the copies' for files it installed.
    ///
    /// `duplicates` are families the library has already, from other files, and `choices` what to do with each: a file
    /// only of families left out stays out (`then` gets the library's copies of them instead, to show), and one that
    /// replaces the library's copies goes in their places, which `then` gets (see `ActivationEngine.replace`).
    func addFontFiles(_ paths: [String], resolving duplicates: [AddedDuplicate] = [], choices: [String: DuplicateChoice] = [:],
                      method: InstallMethod? = nil, mayMove: Bool = true, then: ((AppModel, Set<String>) -> Void)? = nil,
                      askedAboutOpenApps: Bool = false) {
        let skipped = duplicates.filter { choices[$0.id] == .skip }
        let replacements = duplicates.filter { choices[$0.id] == .replace && $0.canReplace }.flatMap(\.replacements)
        // InDesign, Illustrator and Photoshop keep a font's old version until they restart, so open documents can show
        // wrong letters once its file is replaced: the user says first. Once the alert or sheet before has gone.
        if !replacements.isEmpty, !askedAboutOpenApps, case let apps = openAppsKeepingFonts, !apps.isEmpty {
            let prompt = OpenAppsReplacePrompt(apps: apps) { model in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, mayMove: mayMove, then: then,
                                   askedAboutOpenApps: true)
            }
            Task { openAppsReplacePrompt = prompt }
            return
        }
        // A file only of skipped families stays out, and one that takes the library's copies' places is in as those.
        let left = Set(skipped.flatMap(\.paths)).subtracting(duplicates.filter { choices[$0.id] != .skip }.flatMap(\.paths))
            .union(replacements.map(\.added))
        // With Ask, how to bring in files the library doesn't have yet, and added ones that are off; once the sheet or
        // alert before has gone. Files added while it's up join it.
        let offAdded = movableFiles(among: paths).filter { !library.activePaths.contains($0) }
        if method == nil, data.installMethod == .ask,
           case let asked = paths.filter({ !left.contains($0) && (!isListed($0) || offAdded.contains($0)) }), !asked.isEmpty {
            let prompt = InstallPrompt(files: asked, offersMove: mayMove && asked.contains { !isInReadFolder($0) }) { model, method in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, mayMove: mayMove, then: then,
                                   askedAboutOpenApps: true)
            }
            Task {
                guard let shown = installPrompt else { return installPrompt = prompt }
                installPrompt = InstallPrompt(files: shown.files + prompt.files.filter { !shown.files.contains($0) },
                                              offersMove: shown.offersMove || prompt.offersMove) { model, method in
                    shown.add(model, method)
                    prompt.add(model, method)
                }
            }
            return
        }
        let method = method ?? data.installMethod
        let installs = method == .copy || method == .move
        let paths = paths.filter { !left.contains($0) }
        let existing = Set(skipped.flatMap { $0.styles.map(\.face.path) })
        let skipNote = Self.skipNote(skipped)
        let movable = movableFiles(among: paths)
        // Files the library doesn't list, and added ones that are off.
        let installing = !installs ? [] : paths.filter { path in
            !isListed(path) || movable.contains(path) && !library.activePaths.contains(path)
        }
        let moving = mayMove && method == .move
        // Copied or moved, files the library doesn't list are installed, or take over the library's copies.
        let new = installs ? [] : paths.filter { !isListed($0) }
        if !new.isEmpty {
            data.fontFiles += new
            data.sidebar.hidden.remove(SidebarSection.folders.key)
            data.sidebar.hidden.remove("folder.\(WatchedFolder.addedFilesID)")
        }
        guard !installing.isEmpty || !replacements.isEmpty else {
            if !skipNote.isEmpty { showToast(skipNote) }
            let shown = Set(paths).union(existing)
            if let then, !shown.isEmpty { then(self, shown) } else if !new.isEmpty { rescan() }
            return
        }
        let shown = Set(paths).subtracting(installing)
        enqueue { model in
            var messages: [String] = []
            var replaced = replacements.map(\.old)
            if !installing.isEmpty {
                let result = await model.engine.install(installing, moving: moving, records: model.data.records)
                model.data.records = result.records
                messages.append(result.message)
            }
            if !replacements.isEmpty {
                let result = await model.engine.replace(replacements, moving: moving, records: model.data.records)
                model.data.records = result.records
                messages.append(result.message)
                replaced = replaced.map { result.placed[$0] ?? $0 }
                if !result.renameLater.isEmpty { model.renameBackLater(result.renameLater) }
            }
            model.forgetInstalledAddedFiles()
            model.showToast((messages + [skipNote]).filter { !$0.isEmpty }.joined(separator: ". "))
            let originals = Set(installing)
            let copies = Set(model.data.records.installedCopies.filter { originals.contains($0.value) }.keys)
            let found = shown.union(copies).union(existing).union(replaced)
            // Nothing to show when nothing went in: the toast says so.
            if let then, !found.isEmpty { then(model, found) } else { model.rescan() }
        }
    }

    /// Files Replace put in as "Name 2.otf", as macOS hadn't let go of the old file yet, take their name once it has, within
    /// `ActivationEngine.renameBackWait` (see `ActivationEngine.renameBack`). Other operations go on meanwhile; one that
    /// comes too late, after Cicero quits say, leaves the file as it is.
    func renameBackLater(_ pending: [String: String]) {
        let engine = engine
        Task { [weak self] in
            let remembered = await engine.waitUntilForgotten(Array(pending.values), timeout: engine.renameBackWait, every: .seconds(1))
            let ready = pending.filter { !remembered.contains($0.value) }
            guard !ready.isEmpty, let self else { return }
            self.enqueue { model in
                let renamed = await model.engine.renameBack(ready, records: model.data.records)
                if !renamed.isEmpty { model.rescan() }
            }
        }
    }

    /// "Skipped Helvetica, already in your library", "Skipped 3 families already in your library", or nothing when no
    /// family was left out.
    private static func skipNote(_ skipped: [AddedDuplicate]) -> String {
        guard let names = FontNames.describe(families: skipped.map(\.family)) else { return "" }
        return skipped.count > 2 ? "Skipped \(names) already in your library" : "Skipped \(names), already in your library"
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

    /// In a Fonts folder, the Inactive folder or a watched folder, also when the path reaches it another way (see
    /// `libraryPath`): moving such a file would take it out of the folder.
    private func isInReadFolder(_ path: String) -> Bool {
        let folders = readFolders
        let path = libraryPath(of: path, folders: folders)
        return folders.contains { path.hasPrefix($0 + "/") }
    }

    /// The Fonts folders, the Inactive folder and the watched folders.
    private var readFolders: [String] {
        [locations.userFonts.path, locations.allUsersFonts.path] + locations.inactiveFolders.map(\.path) + data.scannedFolders().map(\.path)
    }

    /// The path the way the library has it: through the folder it reads, when `path` reaches a file in it another way,
    /// through a symbolic link, like a shortcut to a synced folder, or in other letter case.
    func libraryPath(of path: String, folders: [String]? = nil) -> String {
        let folders = folders ?? readFolders
        guard !folders.contains(where: { path.hasPrefix($0 + "/") }), let real = Self.realPath(path) else { return path }
        for folder in folders {
            guard let realFolder = Self.realPath(folder), real.hasPrefix(realFolder + "/") else { continue }
            return folder + real.dropFirst(realFolder.count)
        }
        return path
    }

    /// The path as the disk has it, symbolic links resolved and each name in its own letter case; nil when there's
    /// nothing there.
    private static func realPath(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
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
                ? "That font comes with macOS, and system fonts are hidden (Preferences → General)"
                : "That font is from Adobe Fonts, which are hidden (Preferences → General)")
        }
        if let set = opened.set, let name = data.sets.first(where: { $0.id == set })?.name {
            setMembership(true, for: families, in: set)
            showToast("Added \(FontNames.describe(families: families.map(\.name)) ?? "") to “\(name)”")
        }
        let ids = Set(families.map(\.id))
        // Added files in Added Fonts, unless they joined the set shown; others where the browser shows them, else
        // in All Fonts.
        let added = families.allSatisfy { $0.folderIDs.contains(WatchedFolder.addedFilesID) }
        if added && opened.set == nil {
            clearSearch()
            selection = .folder(WatchedFolder.addedFilesID)
        } else if !ids.isSubset(of: Set(visibleFamilies.map(\.id))) {
            clearSearch()
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
