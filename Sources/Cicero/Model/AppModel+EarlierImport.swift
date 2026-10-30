import AppKit
import CiceroCore

/// FontExplorer X's Font Library as a location, as an import made it up to 0.10.13: offered at launch to be copied in,
/// as imports copy fonts in now.
struct EarlierImportPrompt: Identifiable {
    let id = UUID()
    let folder: WatchedFolder
    /// The font files in it the library lists.
    let files: [String]
    /// How many of them are copied: not those in already, and one of the same files (see `ActivationEngine.copyPlan`).
    let copying: Int
    /// Where `copying` was counted for: Cicero's Library, or the Fonts folder.
    let countedForFontLibrary: Bool
    /// How many of those are on where they are.
    let onCount: Int
    /// The smart folders with a rule about the location, which find nothing once it's gone.
    let smartSets: [String]
}

extension AppModel {
    /// Once a launch, after its first scan: asks about FontExplorer X's Font Library when it's still one of the user's
    /// locations with fonts in it. Not Now asks again at the next launch.
    func offerEarlierImportCopy() {
        guard !askedAboutEarlierImport, !isImporting, importing == nil,
              let folder = FontExplorerImport.earlierImportLocation(in: data)
        else { return }
        let faces = faces(in: [folder])
        let prefix = folder.path + "/"
        let files = Set(faces.flatMap { [$0.face.path] + $0.otherCopies }).filter { $0.hasPrefix(prefix) }.sorted()
        guard !files.isEmpty else { return }
        askedAboutEarlierImport = true
        let onCount = library.faces(inFiles: Set(files)).filter { isOnWhereItIs($0) }.count
        let smartSets = data.smartSets.filter { $0.rules.contains { $0.field == .folder && $0.value == folder.id.uuidString } }.map(\.name)
        let engine = engine
        let intoFontLibrary = data.installsIntoFontLibrary
        Task {
            // Counted before asking, so the sheet says from the start how many it copies.
            let copying = await Task.detached(priority: .userInitiated) { engine.copyPlan(files).toCopy.count }.value
            guard !isImporting, importing == nil, FontExplorerImport.earlierImportLocation(in: data)?.id == folder.id else { return }
            earlierImportPrompt = EarlierImportPrompt(folder: folder, files: files, copying: copying, countedForFontLibrary: intoFontLibrary,
                                                      onCount: onCount, smartSets: smartSets)
        }
    }

    /// On from its file where it is: by Cicero, or by FontExplorer X, which leaves its fonts on after it quits.
    func isOnWhereItIs(_ face: LibraryFace) -> Bool {
        data.records.inPlace.contains(face.face.path) || face.state.source == .otherApp
    }

    /// Saves the current setup to the Backups folder; copies the location's fonts in, off, where installing puts them
    /// (the long part, in the caller's task so it can be cancelled: the copies made so far go again); then, in one queued
    /// operation, turns off the location's fonts that were on, removes the location, reads the copies and turns on those
    /// of the fonts that were on. Folders, tags and the rest go by family and PostScript name, so they stay as they are.
    /// FontExplorer X's own files stay where they are. Returns how many files were copied; nil when nothing was done.
    func copyEarlierImport(_ prompt: EarlierImportPrompt, stage: @escaping @Sendable (ImportStage) -> Void) async -> Int? {
        isImporting = true
        defer { isImporting = false }
        let backup = LibraryBackup(locations: locations)
        let current = data
        let saved = await Task.detached(priority: .userInitiated) {
            (try? backup.saveSnapshot(current, named: "Before Copying FontExplorer X’s Fonts")) != nil
        }.value
        guard saved else {
            showToast("Couldn’t save the current setup first, so nothing was copied")
            return nil
        }
        // The copies are read in one go once they're all in, rather than with each batch.
        holdScans()
        defer { releaseScans() }
        let installed = await engine.installOff(prompt.files) { done, total in stage(.copying(done: done, total: total)) }
        if Task.isCancelled {
            for path in installed.new { try? FileManager.default.removeItem(atPath: path) }
            return nil
        }
        // Every file has to be in: a location whose fonts aren't all copied would lose some as it goes.
        let missing = prompt.files.filter { installed.placed[$0] == nil }
        guard missing.isEmpty else {
            for path in installed.new { try? FileManager.default.removeItem(atPath: path) }
            showToast(missing.count == 1 ? "Couldn’t copy “\((missing[0] as NSString).lastPathComponent)”, so nothing changed"
                : "Couldn’t copy \(missing.count) font files, so nothing changed")
            return nil
        }
        stage(.starting)
        let folder = prompt.folder
        await enqueued { model in
            let on = model.library.faces(inFiles: Set(prompt.files)).filter { model.isOnWhereItIs($0) }
            if !on.isEmpty {
                let result = await model.engine.deactivate(on, records: model.data.records)
                model.data.records = result.records
            }
            model.data.folders.removeAll { $0.id == folder.id }
            model.data.sidebar.forget("folder.\(folder.id)")
            model.data.folderNames[folder.id.uuidString] = nil
            model.deselect { $0 == .folder(folder.id) }
            // The library with the copies in it and without the location, for the copies' faces.
            let input = ScanInput(folders: model.data.scannedFolders(), files: model.data.fontFiles, records: model.data.records)
            let scanned = try? await model.scanner.scan(input) { progress in
                switch progress {
                case .identifying(let done, let total), .updating(let done, let total): stage(.reading(done: done, total: total))
                case .finding: break
                }
            }
            let wanted = Set(on.compactMap { installed.placed[$0.face.path] })
            let copies = (scanned ?? model.library).faces(inFiles: wanted).filter(\.canActivate)
            if !copies.isEmpty {
                let result = await model.engine.activate(copies, method: .inPlace, records: model.data.records)
                model.data.records = result.records
            }
            model.rescan()
        }
        return installed.new.count
    }
}
