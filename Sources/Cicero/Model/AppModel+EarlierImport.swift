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
    static let declinedEarlierImportsKey = "earlierImport.declinedLocations"

    static func declinedEarlierImport(_ folder: WatchedFolder) -> Bool {
        UserDefaults.standard.stringArray(forKey: declinedEarlierImportsKey)?.contains(folder.id.uuidString) == true
    }

    func declineEarlierImport(_ prompt: EarlierImportPrompt) {
        let declined = UserDefaults.standard.stringArray(forKey: Self.declinedEarlierImportsKey) ?? []
        UserDefaults.standard.set(declined + [prompt.folder.id.uuidString], forKey: Self.declinedEarlierImportsKey)
    }

    func offerEarlierImportCopy() {
        guard job == nil, importing == nil,
              let folder = FontExplorerImport.earlierImportLocation(in: data), !Self.declinedEarlierImport(folder)
        else { return mayOfferEarlierImportCopy = false }
        let files = earlierImportFiles(in: folder)
        guard !files.isEmpty else { return mayOfferEarlierImportCopy = false }
        let onCount = library.faces(inFiles: Set(files)).filter { isOnWhereItIs($0) }.count
        let smartSets = data.smartSets.filter { $0.rules.contains { $0.field == .folder && $0.value == folder.id.uuidString } }.map(\.name)
        let engine = importEngine
        let intoFontLibrary = data.installsIntoFontLibrary
        Task {
            defer { mayOfferEarlierImportCopy = false }
            let copying = await Task.detached(priority: .userInitiated) { engine.copyPlan(files).toCopy.count }.value
            guard job == nil, importing == nil, FontExplorerImport.earlierImportLocation(in: data)?.id == folder.id else { return }
            let prompt = EarlierImportPrompt(folder: folder, name: data.folderNames[folder.id.uuidString] ?? folder.displayName,
                                             files: files, copying: copying, countedForFontLibrary: intoFontLibrary,
                                             onCount: onCount, smartSets: smartSets)
            ask { model in
                guard model.job == nil else { return }
                model.earlierImportPrompt = prompt
            }
        }
    }

    private func earlierImportFiles(in folder: WatchedFolder) -> [String] {
        let prefix = folder.path + "/"
        return Set(faces(in: [folder]).flatMap { [$0.face.path] + $0.otherCopies })
            .filter { $0.hasPrefix(prefix) && FileManager.default.fileExists(atPath: $0) }.sorted()
    }

    func isOnWhereItIs(_ face: LibraryFace) -> Bool {
        data.records.inPlace.contains(face.face.path) || face.state.source == .otherApp
    }

    func copyEarlierImport(_ prompt: EarlierImportPrompt, stage: @escaping @Sendable (ImportStage) -> Void) async -> Int? {
        guard startJob(.copyingEarlierImport) else { return nil }
        defer { endJob(.copyingEarlierImport) }
        guard await saveSetupSnapshot(named: "Before Copying FontExplorer X’s Fonts", nothingWas: "copied") else { return nil }
        // Copied outside the queue, so only after what's in it: the launch's tidying trashes what it finds in Staging, where the copies wait.
        stage(.waiting)
        var files: [String] = []
        var onFiles = Set<String>()
        await enqueued { model in
            files = model.earlierImportFiles(in: prompt.folder)
            onFiles = Set(model.library.faces(inFiles: Set(files)).filter { model.isOnWhereItIs($0) }.map(\.face.path))
        }
        if Task.isCancelled { return nil }
        holdScans()
        defer { releaseScans() }
        let installed = await importEngine.installOff(files, on: onFiles) { done, total in stage(.copying(done: done, total: total)) }
        if Task.isCancelled {
            if !installed.new.isEmpty { showToast(Self.stoppedCopying(installed.new.count, again: "Cicero offers the rest at the next launch")) }
            return nil
        }
        // Every file has to be in: a location whose fonts aren't all copied would lose some as it goes.
        let missing = files.filter { installed.placed[$0] == nil }
        guard missing.isEmpty else {
            for path in installed.new { try? FileManager.default.removeItem(atPath: path) }
            showToast(missing.count == 1 ? "Couldn’t copy “\((missing[0] as NSString).lastPathComponent)”, so nothing changed"
                : "Couldn’t copy \(missing.count) font files, so nothing changed")
            return nil
        }
        stage(.starting)
        let folder = prompt.folder
        let copied = Set(files)
        await enqueued { model in
            let on = model.library.faces(inFiles: copied).filter { model.isOnWhereItIs($0) }
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
