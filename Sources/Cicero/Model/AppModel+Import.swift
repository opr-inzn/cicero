import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// Another font manager's library, read for the Import sheet, and where it was read from.
struct ImportPrompt: Identifiable {
    let id = UUID()
    let library: ImportedLibrary
    /// "FontExplorer X’s library on this Mac", or the file's name.
    let origin: String
    /// What it was read from, to read it again.
    var urls: [URL] = []
    /// The other app keeps writing to it while it's open: it can't be imported until the app has quit, and is read
    /// again then. FontBase's own library on this Mac.
    var waitsForQuit = false

    var source: ImportedLibrary.Source { library.source }
}

/// Where an import is, for the sheet.
enum ImportStage: Equatable {
    case copying(done: Int, total: Int)
    /// Cancelled while copying: the copies made so far are being settled (turned off, or left on) before the sheet closes.
    case stopping
    case reading(done: Int, total: Int)
    case starting
}

extension AppModel {
    // MARK: Finding a library

    /// File → Import from FontExplorer X: its library on this Mac, else a database or backup the user picks.
    func importFromFontExplorer() {
        guard let database = FontExplorerImport.database() else { return chooseImportFile(for: .fontExplorer) }
        readImport([database], source: .fontExplorer, origin: "FontExplorer X’s library on this Mac")
    }

    /// File → Import from Font Book: the collections on this Mac, else collection files the user picks.
    func importFromFontBook() {
        let collections = FontBookImport.collections()
        guard !collections.isEmpty else { return chooseImportFile(for: .fontBook) }
        readImport(collections, source: .fontBook, origin: "Font Book’s collections on this Mac")
    }

    /// File → Import from FontBase: its library on this Mac, else its folder from another Mac, which the user picks.
    func importFromFontBase() {
        guard let folder = FontBaseImport.folder() else { return chooseImportFile(for: .fontBase) }
        readImport([folder], source: .fontBase, origin: "FontBase’s library on this Mac")
    }

    /// Asks for FontExplorer X's database or a backup of it (a `.fexconfig` is a folder), or Font Book collections.
    func chooseImportFile(for source: ImportedLibrary.Source) {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        switch source {
        case .fontExplorer:
            // With FontExplorer X installed, a .fexconfig is a package rather than a file.
            panel.allowedContentTypes = FontExplorerImport.fileExtensions.sorted().flatMap { ext in
                [UTType(filenameExtension: ext), UTType(filenameExtension: ext, conformingTo: .package)].compactMap { $0 }
            }
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose FontExplorer X’s library (FontExplorer X.fexdb), or a backup made with File → Local Backup (.fexconfig or .fexbackup)."
        case .fontBook:
            panel.allowedContentTypes = [UTType(filenameExtension: FontBookImport.fileExtension)].compactMap { $0 }
            panel.allowsMultipleSelection = true
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/FontCollections", isDirectory: true)
            panel.message = "Choose Font Book collections (.collection files), like those in Library/FontCollections in a home folder."
        case .fontBase:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose FontBase’s folder from another Mac, the one in Library/Application Support in a home folder."
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let origin = panel.urls.count == 1 ? "“\(panel.urls[0].lastPathComponent)”" : "\(panel.urls.count) collections"
        readImport(panel.urls, source: source, origin: origin)
    }

    /// Files dropped on the window or opened from the Finder: FontExplorer X's database or backups, or Font Book
    /// collections. Returns the ones that were.
    func importFiles(among urls: [URL]) -> Set<URL> {
        let fontExplorer = urls.filter { FontExplorerImport.fileExtensions.contains($0.pathExtension.lowercased()) }
        let fontBook = urls.filter { $0.pathExtension.lowercased() == FontBookImport.fileExtension }
        // One library at a time: the sheet shows one.
        if let file = fontExplorer.first {
            readImport([file], source: .fontExplorer, origin: "“\(file.lastPathComponent)”")
        } else if !fontBook.isEmpty {
            readImport(fontBook, source: .fontBook, origin: fontBook.count == 1 ? "“\(fontBook[0].lastPathComponent)”" : "\(fontBook.count) collections")
        }
        return Set(fontExplorer + fontBook)
    }

    /// Reads the library off the main thread and shows the Import sheet, or says why it can't.
    private func readImport(_ urls: [URL], source: ImportedLibrary.Source, origin: String) {
        Task {
            let read = await Self.read(urls, source: source)
            switch read {
            case .success(let library) where isImporting:
                library.discard()
                showToast("Wait for the import to finish first")
            case .success(let library) where library.isEmpty:
                library.discard()
                showToast(source == .fontBook ? "No collections Cicero can import" : "Nothing in it Cicero can import")
            case .success(let library):
                let waits = source == .fontBase && urls == [FontBaseImport.folder()].compactMap { $0 }
                importing = ImportPrompt(library: library, origin: origin, urls: urls, waitsForQuit: waits)
            case .failure:
                switch source {
                case .fontExplorer: showToast("That isn’t a FontExplorer X library or backup")
                case .fontBook: showToast("Couldn’t read the collections")
                case .fontBase: showToast("That isn’t FontBase’s folder")
                }
            }
        }
    }

    /// The library read again, as the other app left it on quitting; nil when it can't be read now.
    func reread(_ prompt: ImportPrompt) async -> ImportPrompt? {
        guard case .success(let library) = await Self.read(prompt.urls, source: prompt.source) else { return nil }
        return ImportPrompt(library: library, origin: prompt.origin, urls: prompt.urls, waitsForQuit: prompt.waitsForQuit)
    }

    private nonisolated static func read(_ urls: [URL], source: ImportedLibrary.Source) async -> Result<ImportedLibrary, Error> {
        await Task.detached(priority: .userInitiated) { () async -> Result<ImportedLibrary, Error> in
            switch source {
            case .fontExplorer:
                do { return .success(try await FontExplorerImport.read(urls[0])) } catch { return .failure(error) }
            case .fontBook:
                return .success(FontBookImport.read(urls))
            case .fontBase:
                do { return .success(try FontBaseImport.read(urls[0])) } catch { return .failure(error) }
            }
        }.value
    }

    // MARK: Importing

    /// The toast once copying is cancelled with `count` files copied in, which stay: off, but for `on` of them, on as they
    /// were in `appName`.
    static func stoppedCopying(_ count: Int, on: Int = 0, appName: String = "", again: String) -> String {
        let files = count == 1 ? "font file" : "\(count.formatted()) font files"
        guard on > 0 else { return "Stopped. The \(files) copied in so far stay, off: \(again)" }
        return "Stopped. The \(files) copied in so far stay, \(on.formatted()) of them on, as in \(appName): \(again)"
    }

    /// Saves the current setup to the Backups folder; copies the other app's fonts in, off, where installing puts them
    /// (the long part, in the caller's task so it can be cancelled: the copies made so far stay, off, and importing again
    /// takes them as they are); reads them in one queued operation; brings in the rest, matched against the copies; then turns on the fonts that were on. Nil when
    /// nothing was done.
    func performImport(_ prompt: ImportPrompt, choices: ImportChoices, stage: @escaping @Sendable (ImportStage) -> Void) async -> ImportSummary? {
        let imported = prompt.library
        isImporting = true
        defer { isImporting = false }
        guard await saveSetupSnapshot(named: "Before Import", nothingWas: "imported") else { return nil }
        // The other app's copies go first, so they aren't on beside Cicero's.
        let removed = choices.removeCopies ? LibraryImport.removeCopies(imported) : 0
        var data = data
        let files = LibraryImport.fontFiles(imported, choices: choices, data: &data, locations: locations)
        self.data.showAdobeAppFolders = data.showAdobeAppFolders
        // The copies are read in one go once they're all in, rather than with each batch.
        holdScans()
        defer { releaseScans() }
        // The files with fonts that were on go in on, as they'd be turned on at the end (see `installOff`).
        let activePaths = choices.activate ? Set(imported.active.compactMap(\.path)) : []
        let on = Set(files.filter { activePaths.contains($0.path) }.map(\.source))
        // Once cancelled, the copies that went in on stay on when nothing else has those fonts on: FontBase deletes its
        // own copies as it quits. FontExplorer X leaves its fonts on, so with it they go off, or they'd be on twice.
        let keepOn = imported.source == .fontBase
        let installed = await importEngine.installOff(files.map(\.source), on: on, keepOnWhenCancelled: keepOn) { done, total in
            stage(.copying(done: done, total: total))
        }
        if Task.isCancelled {
            let onCount = keepOn ? Set(on.compactMap { installed.placed[$0] }).intersection(installed.new).count : 0
            if !installed.new.isEmpty {
                showToast(Self.stoppedCopying(installed.new.count, on: onCount, appName: imported.source.appName, again: "import again to finish"))
            }
            return nil
        }
        // The other app's paths → the copies'.
        var paths: [String: String] = [:]
        for file in files { if let copy = installed.placed[file.source] { paths[file.path] = copy } }
        stage(.starting)
        var summary: ImportSummary?
        await enqueued { model in
            // Files Cicero still has on where they are, though the library doesn't list them any more, as a location it
            // was in has gone: their copies take over, so the fonts aren't on from the other app's files.
            let stale = files.map(\.source).filter { model.data.records.inPlace.contains($0) && installed.placed[$0] != nil }
            if !stale.isEmpty { model.data.records = await model.engine.forgetInPlace(stale, records: model.data.records) }
            // The other app's own files, still on after it quit, as FontExplorer X leaves them: turned off, so the copies
            // can take over, rather than the fonts staying on from its files.
            let copiedFrom = Set(files.map(\.source).filter { installed.placed[$0] != nil })
            let onFromApp = choices.activate ? model.library.faces(inFiles: copiedFrom).filter { $0.state.source == .otherApp } : []
            if !onFromApp.isEmpty { model.data.records = await model.engine.deactivate(onFromApp, records: model.data.records).records }
            // The library with the copies in it, to match against.
            let input = model.scanInput
            let scanned = try? await model.scanner.scan(input) { progress in
                switch progress {
                case .identifying(let done, let total), .updating(let done, let total): stage(.reading(done: done, total: total))
                case .finding: break
                }
            }
            var updated = model.data
            // The copies that went in on, as their fonts were on, and those in already, on as a cancelled import of the same
            // library may have left them (`keepOnWhenCancelled`): on already, so nothing's left to do for them.
            let copiedInOn = Set(on.compactMap { installed.placed[$0] })
            var (result, faces) = LibraryImport.apply(imported, choices: choices, to: &updated, library: scanned ?? model.library,
                                                      paths: paths, copiedInOn: copiedInOn)
            // A style the other app's file still stands for goes on as its copy.
            let copies = Set(installed.placed.values)
            faces = faces.map { $0.copy(among: copies) }
            // The import's to count, name and undo: those it turns on, and those whose copies went in on just now. Not
            // those on from before, as when the same library is imported again: nothing changes for them.
            let copiedInOnNow = copiedInOn.intersection(installed.new)
            let turnedOn = faces.filter { $0.canActivate || copiedInOnNow.contains($0.face.path) }
            result.fonts = installed.new.count
            result.notCopied = installed.failed.count
            result.removedCopies = removed
            if result.sets + result.applicationSets + result.smartSets > 0 { updated.sidebar.hidden.remove(SidebarSection.sets.key) }
            if result.tags > 0 { updated.sidebar.hidden.remove(SidebarSection.tags.key) }
            if result.classifiedFamilies > 0 { updated.sidebar.hidden.remove(SidebarSection.classifications.key) }
            model.data = updated
            model.rescan()
            // And the copies of those that were on from the other app's files.
            let takingOver = Set(stale.compactMap { installed.placed[$0] }).subtracting(faces.map(\.face.path))
            let more = takingOver.isEmpty ? []
                : (scanned ?? model.library).families.flatMap(\.faces).filter { takingOver.contains($0.face.path) && $0.canActivate }
            // In a Fonts folder or Cicero's Library, they go on where they are.
            if !faces.isEmpty || !more.isEmpty { model.performActivation(faces + more, named: turnedOn + more) }
            result.activated = turnedOn.count
            summary = result
        }
        return summary
    }
}

extension Library {
    /// The folders of the files apps load from their own folders, like Adobe's, but Creative Cloud's Adobe Fonts.
    var appFontFolders: [URL] {
        var folders = Set<String>()
        for face in families.lazy.flatMap(\.faces) {
            for (path, app) in [(face.face.path, face.app)] + face.copies.map({ ($0.face.path, $0.app) })
            where app != nil && !ActiveSource.isAdobeFonts(path) {
                folders.insert((path as NSString).deletingLastPathComponent)
            }
        }
        return folders.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The styles in these files, each as that file, also where another copy stands for the style.
    func faces(inFiles paths: Set<String>) -> [LibraryFace] {
        families.flatMap(\.faces).flatMap { face in
            (paths.contains(face.face.path) ? [face] : []) + face.copies.filter { paths.contains($0.face.path) }.map(\.libraryFace)
        }
    }
}

extension LibraryFace {
    /// The style as its file among `paths` that's off, when another file stands for it; else as it is.
    func copy(among paths: Set<String>) -> LibraryFace {
        guard !paths.contains(face.path) else { return self }
        return copies.first { paths.contains($0.face.path) && !$0.state.isActive }?.libraryFace ?? self
    }
}

extension ImportedLibrary {
    /// Nothing to bring in.
    var isEmpty: Bool {
        fontFolder == nil && otherFiles.isEmpty && sets.isEmpty && smartSets.isEmpty && tags.isEmpty && classifications.isEmpty && ratings.isEmpty
            && history.isEmpty && active.isEmpty
    }
}
