import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// Another font manager's library, read for the Import sheet, and where it was read from.
struct ImportPrompt: Identifiable {
    let id = UUID()
    let library: ImportedLibrary
    /// "FontExplorer X’s library on this Mac", or the file's name.
    let origin: String

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

    /// Asks for FontExplorer X's database or a backup of it (a `.fexconfig` is a folder), or Font Book collections.
    func chooseImportFile(for source: ImportedLibrary.Source) {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        switch source {
        case .fontExplorer:
            panel.allowedContentTypes = FontExplorerImport.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose FontExplorer X’s library (FontExplorer X.fexdb), or a backup made with File → Local Backup (.fexconfig or .fexbackup)."
        case .fontBook:
            panel.allowedContentTypes = [UTType(filenameExtension: FontBookImport.fileExtension)].compactMap { $0 }
            panel.allowsMultipleSelection = true
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/FontCollections", isDirectory: true)
            panel.message = "Choose Font Book collections (.collection files), like those in Library/FontCollections in a home folder."
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
            let read = await Task.detached(priority: .userInitiated) { () async -> Result<ImportedLibrary, Error> in
                switch source {
                case .fontExplorer:
                    do { return .success(try await FontExplorerImport.read(urls[0])) } catch { return .failure(error) }
                case .fontBook:
                    return .success(FontBookImport.read(urls))
                }
            }.value
            switch read {
            case .success(let library) where isImporting:
                library.discard()
                showToast("Wait for the import to finish first")
            case .success(let library) where library.isEmpty:
                library.discard()
                showToast(source == .fontBook ? "No collections Cicero can import" : "Nothing in it Cicero can import")
            case .success(let library):
                importing = ImportPrompt(library: library, origin: origin)
            case .failure:
                showToast(source == .fontBook ? "Couldn’t read the collections" : "That isn’t a FontExplorer X library or backup")
            }
        }
    }

    // MARK: Importing

    /// Saves the current setup to the Backups folder; puts a backup's fonts in place (the long part, in the caller's
    /// task so it can be cancelled); lists the other app's fonts and reads them in one queued operation; brings in the
    /// rest, matched against them; then turns on, where they are, the fonts that were on. Nil when nothing was done.
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
        if choices.fontFolder, imported.bundledFonts != nil {
            _ = await LibraryImport.placeBundledFonts(imported) { done, total in stage(.copying(done: done, total: total)) }
            if Task.isCancelled { return nil }
        }
        stage(.starting)
        var summary: ImportSummary?
        await enqueued { model in
            var data = model.data
            let fonts = LibraryImport.addFonts(imported, choices: choices, to: &data, locations: model.locations)
            model.data = data
            // The library with the other app's fonts in it, to match against.
            let input = ScanInput(folders: data.scannedFolders(), files: data.fontFiles, records: data.records)
            let scanned = try? await model.scanner.scan(input) { progress in
                if case .identifying(let done, let total) = progress { stage(.reading(done: done, total: total)) }
            }
            var updated = model.data
            var (result, faces) = LibraryImport.apply(imported, choices: choices, to: &updated, library: scanned ?? model.library)
            result.fonts = fonts
            if fonts > 0 { updated.sidebar.hidden.remove(SidebarSection.folders.key) }
            if result.sets + result.applicationSets + result.smartSets > 0 { updated.sidebar.hidden.remove(SidebarSection.sets.key) }
            if result.tags > 0 { updated.sidebar.hidden.remove(SidebarSection.tags.key) }
            model.data = updated
            model.rescan()
            if !faces.isEmpty { model.performActivation(faces, method: .inPlace) }
            result.activated = faces.count
            summary = result
        }
        return summary
    }
}

extension ImportedLibrary {
    /// Nothing to bring in.
    var isEmpty: Bool {
        fontFolder == nil && otherFiles.isEmpty && sets.isEmpty && smartSets.isEmpty && tags.isEmpty && ratings.isEmpty && history.isEmpty
    }
}
