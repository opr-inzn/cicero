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

    /// Saves the current setup to the Backups folder; copies the other app's fonts in, off, where installing puts them
    /// (the long part, in the caller's task so it can be cancelled: the copies made so far go again); reads them in one
    /// queued operation; brings in the rest, matched against the copies; then turns on the fonts that were on. Nil when
    /// nothing was done.
    func performImport(_ prompt: ImportPrompt, choices: ImportChoices, stage: @escaping @Sendable (ImportStage) -> Void) async -> ImportSummary? {
        let imported = prompt.library
        isImporting = true
        defer { isImporting = false }
        let backup = LibraryBackup(locations: locations)
        let current = data
        let saved = await Task.detached(priority: .userInitiated) { (try? backup.saveSnapshot(current, named: "Before Import")) != nil }.value
        guard saved else {
            showToast("Couldn’t save the current setup first, so nothing was imported")
            return nil
        }
        // The other app's copies go first, so they aren't on beside Cicero's.
        let removed = choices.removeCopies ? LibraryImport.removeCopies(imported) : 0
        var data = data
        let files = LibraryImport.fontFiles(imported, choices: choices, data: &data, locations: locations)
        self.data.showAdobeAppFolders = data.showAdobeAppFolders
        let installed = await engine.installOff(files.map(\.source)) { done, total in stage(.copying(done: done, total: total)) }
        if Task.isCancelled {
            for path in installed.new { try? FileManager.default.removeItem(atPath: path) }
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
            // The library with the copies in it, to match against.
            let input = ScanInput(folders: model.data.scannedFolders(), files: model.data.fontFiles, records: model.data.records)
            let scanned = try? await model.scanner.scan(input) { progress in
                switch progress {
                case .identifying(let done, let total), .updating(let done, let total): stage(.reading(done: done, total: total))
                case .finding: break
                }
            }
            var updated = model.data
            var (result, faces) = LibraryImport.apply(imported, choices: choices, to: &updated, library: scanned ?? model.library, paths: paths)
            result.fonts = installed.new.count
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
            if !faces.isEmpty || !more.isEmpty { model.performActivation(faces + more) }
            result.activated = faces.count
            summary = result
        }
        return summary
    }
}

extension ImportedLibrary {
    /// Nothing to bring in.
    var isEmpty: Bool {
        fontFolder == nil && otherFiles.isEmpty && sets.isEmpty && smartSets.isEmpty && tags.isEmpty && classifications.isEmpty && ratings.isEmpty
            && history.isEmpty && active.isEmpty
    }
}
