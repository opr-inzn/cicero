import AppKit
import CiceroCore

struct EarlierImportPrompt: Identifiable {
    let id = UUID()
    let folder: WatchedFolder
    let name: String
    let files: [String]
    let copying: Int
    let countedForFontLibrary: Bool
    let onCount: Int
    let smartSets: [String]
}

extension AppModel {
    func offerEarlierImportCopy() {
        guard !askedAboutEarlierImport, !isImporting, importing == nil,
              let folder = FontExplorerImport.earlierImportLocation(in: data)
        else { return mayOfferEarlierImportCopy = false }
        let faces = faces(in: [folder])
        let prefix = folder.path + "/"
        let files = Set(faces.flatMap { [$0.face.path] + $0.otherCopies }).filter { $0.hasPrefix(prefix) }.sorted()
        guard !files.isEmpty else { return mayOfferEarlierImportCopy = false }
        askedAboutEarlierImport = true
        let onCount = library.faces(inFiles: Set(files)).filter { isOnWhereItIs($0) }.count
        let smartSets = data.smartSets.filter { $0.rules.contains { $0.field == .folder && $0.value == folder.id.uuidString } }.map(\.name)
        let engine = importEngine
        let intoFontLibrary = data.installsIntoFontLibrary
        Task {
            defer { mayOfferEarlierImportCopy = false }
            let copying = await Task.detached(priority: .userInitiated) { engine.copyPlan(files).toCopy.count }.value
            guard !isImporting, importing == nil, FontExplorerImport.earlierImportLocation(in: data)?.id == folder.id else { return }
            earlierImportPrompt = EarlierImportPrompt(folder: folder, name: data.folderNames[folder.id.uuidString] ?? folder.displayName,
                                                      files: files, copying: copying, countedForFontLibrary: intoFontLibrary,
                                                      onCount: onCount, smartSets: smartSets)
        }
    }

    func isOnWhereItIs(_ face: LibraryFace) -> Bool {
        data.records.inPlace.contains(face.face.path) || face.state.source == .otherApp
    }

    func copyEarlierImport(_ prompt: EarlierImportPrompt, stage: @escaping @Sendable (ImportStage) -> Void) async -> Int? {
        isImporting = true
        defer { isImporting = false }
        guard await saveSetupSnapshot(named: "Before Copying FontExplorer X’s Fonts", nothingWas: "copied") else { return nil }
        holdScans()
        defer { releaseScans() }
        let onFiles = Set(library.faces(inFiles: Set(prompt.files)).filter { isOnWhereItIs($0) }.map(\.face.path))
        let installed = await importEngine.installOff(prompt.files, on: onFiles) { done, total in stage(.copying(done: done, total: total)) }
        if Task.isCancelled {
            if !installed.new.isEmpty { showToast(Self.stoppedCopying(installed.new.count, again: "Cicero offers the rest at the next launch")) }
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
            model.forgetFolders([folder.id])
            let input = model.scanInput
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
