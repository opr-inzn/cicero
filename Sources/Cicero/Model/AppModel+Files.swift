import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// Font files opened or dropped, waiting for the scan that lists them.
struct OpenedFiles {
    var scan: Int
    var paths: Set<String>
    /// The folder, tag or location the browser showed as they were dropped or pasted (see `AppModel.targetForAddedFiles`).
    var target: SidebarItem?
    /// What adding them did, said as the browser shows them.
    var note: AddNote
}

/// What `AppModel.addFontFiles` did, which `then` says once the browser shows the files, in one toast with joining a
/// folder or tag (see `AppModel.showOpenedFiles`).
struct AddNote {
    /// "Inter Regular installed", "Couldn’t install 2 of 5 files", "Skipped Inter, already in your library"; empty for nothing.
    var message = ""
    /// Every file was installed, as `message` says, with nothing else to say.
    var installedAll = false
}

extension AppModel {
    /// The kinds of font file Cicero reads, for open panels.
    static let fontTypes: [UTType] = FontFormat.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }

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
    /// Dropped or pasted into a folder or a tag, they join it, and into a location, they go into it (see `targetForAddedFiles`).
    /// A document (PDF, IDML, InDesign, Illustrator, Photoshop) shows the fonts it uses.
    /// Several arriving one by one, as from the Finder, are added together.
    func open(_ urls: [URL], into target: SidebarItem? = nil) {
        openQueue.urls += urls
        openQueue.target = openQueue.target ?? target
        openQueue.task?.cancel()
        openQueue.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.openWaitingFiles()
        }
    }

    /// The folder, tag or location the browser shows, which fonts dropped on the window or pasted into it are added to:
    /// they join a folder or get a tag, whatever the install method; copied or moved, they go into a location (see
    /// `dropLocation`), and left where they are, they're under Added Fonts, as they are when dropped on it.
    var targetForAddedFiles: SidebarItem? {
        guard openFamilyID == nil, similarFamilyID == nil, documentList == nil, selectedItems.count == 1, let selection else { return nil }
        switch selection {
        case .set(let id): return data.sets.contains { $0.id == id } ? selection : nil
        case .tag(let name): return data.tags.contains(name) ? selection : nil
        case .folder(let id): return id == WatchedFolder.addedFilesID || dropLocation(id) != nil ? selection : nil
        default: return nil
        }
    }

    /// The location font files dropped on it go into: one of the user's own folders, while it's there and Cicero can write
    /// to it, or for Proofing the first of Adobe's folders it can write to, the one for all users before this account's.
    /// None for Adobe Fonts, whose files Creative Cloud keeps, or Added Fonts, whose files are where they are.
    func dropLocation(_ id: UUID) -> DropLocation? {
        let candidates = id == WatchedFolder.adobeAppsID ? WatchedFolder.appFontFolders() : data.folders.filter { $0.id == id }
        guard library.unavailableFolders[id] == nil,
              let folder = candidates.first(where: { FileManager.default.isWritableFile(atPath: $0.path) }) else { return nil }
        return DropLocation(id: id, name: folderName(id), folder: folder.url, isActive: folder.isActive, app: folder.appName)
    }

    /// Font files and folders copied in the Finder, which ⌘V adds.
    static var pastedFiles: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Edit → Paste in the main window: adds the files copied in the Finder as if dropped on it.
    func pasteFiles() {
        let urls = Self.pastedFiles
        if !urls.isEmpty { open(urls, into: targetForAddedFiles) }
    }

    /// Adds what `open` gathered, once the library has been scanned for the first time.
    func openWaitingFiles() {
        guard started, !openQueue.urls.isEmpty else { return }
        let (urls, target, _) = openQueue
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
            // "Cicero doesn’t use web fonts like WOFF2", or "… like WOFF and WOFF2" for both kinds.
            if !webFonts.isEmpty { return showToast("Cicero doesn’t use web fonts like \(webFonts.sorted().listed())") }
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
        // Dropped on Added Fonts, they're listed where they are; on another location, copied or moved, they go into it.
        var method: InstallMethod?
        var location: DropLocation?
        if case .folder(let id) = target {
            if id == WatchedFolder.addedFilesID { method = .inPlace } else { location = dropLocation(id) }
        }
        addCheckingDuplicates(files, method: method, into: location) { model, paths, note in
            model.awaitingScan = OpenedFiles(scan: model.rescan(), paths: paths, target: target, note: note)
        }
    }

    /// Adds font files the user picked (see `addFontFiles`), first looking for fonts in them the library has already
    /// from other files, and doing with those as Settings → General says: asking family by family, adding them as
    /// other copies, leaving them out, or putting them in place of the library's copies (see `DuplicateHandling`).
    /// Replace asks family by family too where it can't be done, and first warns when it would put a file in more than
    /// one place, or in one of the user's own folders (`replacePrompt`, `warnsBeforeReplacing`).
    /// `method` and `location` say how and where they go, when not as the install method says (see `addFontFiles`).
    func addCheckingDuplicates(_ paths: [String], method: InstallMethod? = nil, into location: DropLocation? = nil,
                               then: @escaping (AppModel, Set<String>, AddNote) -> Void) {
        let new = paths.filter { !isListed($0) }
        guard !new.isEmpty, data.duplicateHandling != .addCopy else { return addFontFiles(paths, method: method, into: location, then: then) }
        let library = library
        Task {
            let duplicates = await Task.detached(priority: .userInitiated) {
                AddedDuplicates.find(in: AddedDuplicates.faces(of: new), library: library)
            }.value
            guard !duplicates.isEmpty else { return addFontFiles(paths, method: method, into: location, then: then) }
            let prompt = DuplicatePrompt(paths: paths, duplicates: duplicates, handling: data.duplicateHandling, method: method,
                                         location: location, then: then)
            let handling = data.duplicateHandling
            let chosen = duplicates.map { $0.choice(for: handling) }
            guard !chosen.contains(nil) else {
                duplicatePrompt = prompt
                return
            }
            if handling == .replace, duplicates.contains(where: warnsBeforeReplacing) {
                replacePrompt = prompt
                return
            }
            addFontFiles(paths, resolving: duplicates, choices: Dictionary(uniqueKeysWithValues: zip(duplicates.map(\.id), chosen.compactMap(\.self))),
                         method: method, into: location, then: then)
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
        addFontFiles(prompt.paths, resolving: prompt.duplicates, choices: choices, method: prompt.method, into: prompt.location,
                     then: prompt.then)
    }

    /// Whether font files the user adds are copied or moved into the Fonts folder (or Cicero's Library), rather than
    /// listed where they are, or asked about.
    var installsAddedFiles: Bool { data.installMethod == .copy || data.installMethod == .move }

    /// Where installed fonts go, for what Cicero says: "your Fonts folder", or "Cicero’s Library".
    var installPlace: String { data.installsIntoFontLibrary ? "Cicero’s Library" : "your Fonts folder" }

    /// Brings in the font files the library doesn't have yet, along with files under Added Fonts that are off, as
    /// `method` says, else the install method: copies or moves them into ~/Library/Fonts, where they're on and in All
    /// Fonts like any installed font, or lists them where they are, under Added Fonts, without turning them on. With
    /// Ask, the user says which first (`installPrompt`), when there are files the library doesn't have. Then
    /// rescans, or `then` does, given the paths the library has the files at: the copies' for files it installed, and
    /// what to say, which it says then rather than in a toast of its own.
    ///
    /// Copied or moved with a `location`, they go into its folder instead, nothing turning on there but what its fonts
    /// are (see `ActivationEngine.place`).
    ///
    /// `duplicates` are families the library has already, from other files, and `choices` what to do with each: a file
    /// only of families left out stays out (`then` gets the library's copies of them instead, to show), and one that
    /// replaces the library's copies goes in their places, which `then` gets (see `ActivationEngine.replace`).
    func addFontFiles(_ paths: [String], resolving duplicates: [AddedDuplicate] = [], choices: [String: DuplicateChoice] = [:],
                      method: InstallMethod? = nil, into location: DropLocation? = nil, then: ((AppModel, Set<String>, AddNote) -> Void)? = nil,
                      askedAboutOpenApps: Bool = false) {
        let skipped = duplicates.filter { choices[$0.id] == .skip }
        let replacements = duplicates.filter { choices[$0.id] == .replace && $0.canReplace }.flatMap(\.replacements)
        // InDesign, Illustrator and Photoshop keep a font's old version until they restart, so open documents can show
        // wrong letters once its file is replaced: the user says first. Once the alert or sheet before has gone.
        if !replacements.isEmpty, !askedAboutOpenApps, case let apps = openAppsKeepingFonts, !apps.isEmpty {
            let prompt = OpenAppsReplacePrompt(apps: apps) { model in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, into: location, then: then,
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
            let prompt = InstallPrompt(files: asked, offersMove: asked.contains { !isInReadFolder($0) }, location: location) { model, method in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, into: location, then: then,
                                   askedAboutOpenApps: true)
            }
            Task {
                guard let shown = installPrompt else { return installPrompt = prompt }
                // Into one place, the sheet names it; files for several are copied or moved into each of theirs.
                installPrompt = InstallPrompt(files: shown.files + prompt.files.filter { !shown.files.contains($0) },
                                              offersMove: shown.offersMove || prompt.offersMove,
                                              location: shown.location == prompt.location ? shown.location : nil) { model, method in
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
        let moving = method == .move
        // Copied or moved, files the library doesn't list are installed, or take over the library's copies.
        let new = installs ? [] : paths.filter { !isListed($0) }
        if !new.isEmpty {
            data.fontFiles += new
            data.sidebar.hidden.remove(SidebarSection.folders.key)
            data.sidebar.hidden.remove("folder.\(WatchedFolder.addedFilesID)")
        }
        guard !installing.isEmpty || !replacements.isEmpty else {
            let shown = Set(paths).union(existing)
            if let then, !shown.isEmpty { return then(self, shown, AddNote(message: skipNote)) }
            if !skipNote.isEmpty { showToast(skipNote) }
            if !new.isEmpty { rescan() }
            return
        }
        let shown = Set(paths).subtracting(installing)
        enqueue { model in
            var messages: [String] = []
            var failed = false
            var replaced = replacements.map(\.old)
            // Each file installed → its copy.
            var copies: [String: String] = [:]
            if !installing.isEmpty {
                let result = if let location {
                    await model.engine.place(installing, into: location.folder, named: location.name, moving: moving, records: model.data.records)
                } else {
                    await model.engine.install(installing, moving: moving, records: model.data.records)
                }
                model.data.records = result.records
                messages.append(result.message)
                failed = !result.failed.isEmpty
                copies = result.placed
            }
            if !replacements.isEmpty {
                let result = await model.engine.replace(replacements, moving: moving, records: model.data.records)
                model.data.records = result.records
                messages.append(result.message)
                replaced = replaced.map { result.placed[$0] ?? $0 }
                if !result.renameLater.isEmpty { model.renameBackLater(result.renameLater) }
            }
            // An added file Cicero installed leaves Added Fonts: the copy is the font now.
            model.data.fontFiles.removeAll { copies[$0] != nil }
            model.forgetInstalledAddedFiles()
            let message = (messages + [skipNote]).filter { !$0.isEmpty }.joined(separator: ". ")
            let found = shown.union(copies.values).union(existing).union(replaced)
            // Nothing to show when nothing went in: the toast says so.
            guard let then, !found.isEmpty else {
                model.showToast(message)
                model.rescan()
                return
            }
            then(model, found, AddNote(message: message, installedAll: location == nil && !installing.isEmpty && !failed
                                                                       && replacements.isEmpty && skipNote.isEmpty))
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

    /// Added files an earlier version installed a copy of leave Added Fonts: the copy in ~/Library/Fonts is the font in
    /// the library now, in All Fonts like any installed font, and what Reveal in Finder shows. For the records earlier
    /// versions wrote, before the scan after an operation.
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
    func libraryPath(of path: String, folders: [String]) -> String {
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

    /// Shows the families of files `open` added, once scan `id` has listed them: in Added Fonts, or the sidebar item shown
    /// when it has them all, else in All Fonts (where installed ones go). Dropped on a folder, tag or location, they join it,
    /// and the browser stays there rather than going to All Fonts (see `targetForAddedFiles`).
    /// The browser goes to the first of them, selected, rather than a font page opening.
    func showOpenedFiles(after id: Int) {
        guard let opened = awaitingScan, id >= opened.scan else { return }
        awaitingScan = nil
        let paths = opened.paths
        let found = library.families.filter { family in
            family.faces.contains { paths.contains($0.face.path) || $0.otherCopies.contains(where: paths.contains) }
        }
        // What adding them did first, then what else there is to say: one toast.
        let say = { (more: String) in
            let message = [opened.note.message, more].filter { !$0.isEmpty }.joined(separator: ". ")
            if !message.isEmpty { self.showToast(message) }
        }
        guard !found.isEmpty else {
            let name = paths.count == 1 ? URL(fileURLWithPath: paths.first!).lastPathComponent : nil
            return say(name.map { "Couldn’t read “\($0)”" } ?? "Couldn’t read these fonts")
        }
        // With system fonts hidden, a font that comes with macOS is nowhere to show; so is one from Creative Cloud.
        let families = found.filter(data.lists)
        guard !families.isEmpty else {
            return say(found[0].state == .system
                ? "That font comes with macOS, and system fonts are hidden (Preferences → General)"
                : "That font is from Adobe Fonts, which are hidden (Preferences → General)")
        }
        // Joining a folder or tag: "Inter installed and added to “Client”", or "Inter added to “Client”" after what else
        // adding them did.
        let names = FontNames.describe(families: families.map(\.name)) ?? ""
        let joins = { (place: String) in
            opened.note.installedAll ? self.showToast("\(names) installed and added to “\(place)”") : say("\(names) added to “\(place)”")
        }
        switch opened.target {
        case .set(let id) where data.sets.contains { $0.id == id }:
            setMembership(true, for: families, in: id)
            joins(data.sets.first { $0.id == id }!.name)
        case .tag(let tag) where data.tags.contains(tag):
            setTag(tag, true, for: families)
            joins(tag)
        default:
            say("")
        }
        let ids = Set(families.map(\.id))
        let isShown = { (families: [Family]) in Set(families.map(\.id)).isSubset(of: Set(self.visibleFamilies.map(\.id))) }
        // Added files in Added Fonts; others where the browser shows them, else in All Fonts. Dropped on a folder, tag or
        // location, the browser stays there with the ones that went in, the search cleared if it hides them; added files
        // that stayed out of a location are in Added Fonts, and others, in another place, aren't shown.
        let added = families.allSatisfy { $0.folderIDs.contains(WatchedFolder.addedFilesID) }
        var first = families[0]
        if let target = opened.target {
            let joined = if case .folder(let id) = target { families.filter { $0.folderIDs.contains(id) } } else { families }
            if let shown = joined.first {
                first = shown
                if !isShown(joined) { clearSearch() }
            } else if added {
                clearSearch()
                selection = .folder(WatchedFolder.addedFilesID)
            } else {
                return
            }
        } else if added {
            clearSearch()
            selection = .folder(WatchedFolder.addedFilesID)
        } else if !isShown(families) {
            clearSearch()
            selection = .all
        }
        selectedIDs = [first.id]
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
