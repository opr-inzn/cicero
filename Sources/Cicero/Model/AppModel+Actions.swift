import AppKit
import CiceroCore

extension AppModel {
    // MARK: Activation

    func activate(_ families: [Family]) {
        activate(families.flatMap(\.faces), title: Self.title(for: families))
    }

    func activate(_ faces: [LibraryFace], title: String, confirmed: Bool = false) {
        let targets = faces.filter(\.canActivate)
        guard !targets.isEmpty else { return showToast("Already on") }
        if !confirmed, let prompt = manyActivationPrompt(for: targets, title: title, temporarily: false) {
            return ask(overActivationSheets: true) { $0.manyActivationPrompt = prompt }
        }
        performActivation(targets)
    }

    func performActivation(_ faces: [LibraryFace], named: [LibraryFace]? = nil) {
        let operation = expect(faces, at: .on)
        enqueue { model in
            var result = await model.engine.activate(faces, method: .inPlace, records: model.data.records)
            if let named, result.failed.isEmpty { result.message = FontNames.describe(named).map { "\($0) activated" } ?? "" }
            model.finish(result, operation: operation, undo: model.undo(turning: named ?? faces, on: false, failed: result.failed))
        }
    }

    func activateTemporarily(_ families: [Family]) {
        activateTemporarily(families.flatMap(\.faces))
    }

    func activateTemporarily(_ faces: [LibraryFace], confirmed: Bool = false) {
        let targets = faces.filter(\.canActivateTemporarily)
        guard !targets.isEmpty else { return showToast("Already on") }
        if !confirmed, let prompt = manyActivationPrompt(for: targets, title: "", temporarily: true) {
            return ask(overActivationSheets: true) { $0.manyActivationPrompt = prompt }
        }
        let operation = expect(targets, at: .on)
        enqueue { model in
            let result = await model.engine.activateTemporarily(targets, records: model.data.records)
            model.finish(result, operation: operation, undo: model.undo(turning: targets, on: false, failed: result.failed))
        }
    }

    private func manyActivationPrompt(for faces: [LibraryFace], title: String, temporarily: Bool) -> ManyActivationPrompt? {
        ActivationQuestions.many(for: faces, title: title, temporarily: temporarily, data: data)
    }

    func confirm(_ prompt: ManyActivationPrompt) {
        if prompt.temporarily {
            activateTemporarily(prompt.faces, confirmed: true)
        } else {
            activate(prompt.faces, title: prompt.title, confirmed: true)
        }
    }

    func deactivate(_ families: [Family]) {
        deactivate(families.flatMap(\.faces))
    }

    func deactivate(_ faces: [LibraryFace], confirmed: Bool = false) {
        let targets = faces.filter(\.canDeactivate)
        guard !targets.isEmpty else {
            return showToast(faces.contains { $0.state.isActive } ? "These fonts are managed by macOS or another app" : "Nothing to deactivate")
        }
        if !confirmed, let prompt = movingOutPrompt(for: targets) {
            return ask(overActivationSheets: true) { $0.movingOutPrompt = prompt }
        }
        performDeactivation(targets)
    }

    private func movingOutPrompt(for faces: [LibraryFace]) -> MovingOutPrompt? {
        ActivationQuestions.movingOut(for: faces, data: data)
    }

    func confirm(_ prompt: MovingOutPrompt, movingOut: Bool) {
        if movingOut { return deactivate(prompt.faces, confirmed: true) }
        let shared = Set(prompt.shared.map(\.id))
        let others = prompt.faces.filter { !shared.contains($0.id) }
        let keptOn = prompt.shared.filter { $0.position == .on }
        if !keptOn.isEmpty { useInAppOnly(keptOn) }
        if !others.isEmpty { deactivate(others, confirmed: true) }
    }

    func performDeactivation(_ faces: [LibraryFace]) {
        let operation = expect(faces, at: .off)
        enqueue { model in
            let result = await model.engine.deactivate(faces, records: model.data.records)
            model.finish(result, operation: operation, undo: model.undo(turning: faces, on: true, failed: result.failed))
        }
    }

    func toggle(_ family: Family) {
        guard expectedFamilyPositions[family.id] == nil else { return }
        let targets = targets(for: family).filter { expectedFamilyPositions[$0.id] == nil }
        if targets.count > 1 {
            return family.position == .on ? deactivate(targets) : activate(targets)
        }
        switch family.position {
        case .on: deactivate([family])
        case .app: activate([family])
        case .off: family.app == nil ? activate([family]) : useInAppOnly(family.faces)
        }
    }

    func toggle(_ face: LibraryFace, in family: Family) {
        guard expectedFacePositions[face.id] == nil else { return }
        switch face.position {
        case .on: deactivate([face])
        case .app: activate([face], title: "\(family.name) \(face.face.styleName)")
        case .off: face.app == nil ? activate([face], title: "\(family.name) \(face.face.styleName)") : useInAppOnly([face])
        }
    }

    func useInAppOnly(_ faces: [LibraryFace]) {
        let operation = expect(faces, at: .app)
        enqueue { model in
            let result = await model.engine.useInAppOnly(faces, records: model.data.records)
            model.finish(result, operation: operation)
        }
    }

    func finish(_ result: ActivationResult, operation: Int? = nil, undo: (() -> Void)? = nil) {
        var data = data
        data.records = result.records
        data.forgetInstalledAddedFiles()
        self.data = data
        if !result.message.isEmpty { showToast(result.message, undo: undo) }
        let scan = rescan()
        if let operation { settle(operation, after: scan) }
    }

    func undo(turning faces: [LibraryFace], on: Bool, failed: [String]) -> (() -> Void)? {
        let failed = Set(failed)
        let ids = Set(faces.filter { !failed.contains($0.face.path) }.map(\.id))
        guard !ids.isEmpty else { return nil }
        return { [weak self] in
            guard let self else { return }
            let families = self.library.families.filter { $0.faces.contains { ids.contains($0.id) } }
            let current = families.flatMap(\.faces).filter { ids.contains($0.id) }
            guard !current.isEmpty else { return }
            if on {
                self.activate(current, title: Self.title(for: families), confirmed: true)
            } else {
                self.deactivate(current)
            }
        }
    }

    static func title(for families: [Family]) -> String {
        families.count == 1 ? families[0].name : "\(families.count) families"
    }

    // MARK: Copies

    func copySources(of styles: [LibraryFace]) -> [CopySource] {
        CopyChooser.sources(of: styles, folders: data.namedFolders, records: data.records, locations: locations)
    }

    func useCopies(from source: CopySource, title: String) {
        let plan = CopyChooser.plan(source, records: data.records, library: library)
        guard !plan.isEmpty else { return showToast("Already using the copies from \(source.name)") }
        let request = CopySwitchRequest(source: source.name, title: title, plan: plan)
        if plan.alsoTurnsOff.isEmpty {
            confirmCopySwitch(request)
        } else {
            ask { $0.copySwitchPrompt = request }
        }
    }

    func confirmCopySwitch(_ request: CopySwitchRequest) {
        let operation = expect(request.plan.styles, at: .on)
        enqueue { model in
            var result = await model.engine.switchCopies(request.plan.switches, method: .inPlace, records: model.data.records)
            if result.failed.isEmpty {
                result.message = "Using the copies from \(request.source)"
                    + (request.plan.leavesOtherCopiesOn ? ". Another copy Cicero didn’t turn on is still on, so apps may use that one" : "")
            }
            model.finish(result, operation: operation)
        }
    }

    // MARK: Font Library

    func placeName(of path: String) -> String {
        if path.hasPrefix(locations.userFonts.path + "/") { return "in your Fonts folder" }
        if locations.isInInactiveFolder(path) { return "in the Inactive folder" }
        if let library = data.fontLibrary, path.hasPrefix(library.path + "/") { return "in \(folderName(WatchedFolder.fontLibraryID))" }
        if data.fontFiles.contains(path) { return "in \(folderName(WatchedFolder.addedFilesID))" }
        if let folder = data.namedFolders.filter({ path.hasPrefix($0.path + "/") }).max(by: { $0.path.count < $1.path.count }) {
            return "in \(folder.displayName)"
        }
        return "in “\(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)”"
    }

    func replacedPlaces(_ duplicate: AddedDuplicate) -> String { places(of: duplicate.replacements.map(\.old)) }

    func places(of paths: [String]) -> String {
        let places = paths.map(placeName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return places.listed()
    }

    func spareCopies(_ duplicate: AddedDuplicate) -> [String] {
        engine.spareCopies(among: duplicate.replacements, records: data.records).keys.sorted()
    }

    func warnsBeforeReplacing(_ duplicate: AddedDuplicate) -> Bool {
        duplicate.replacesSeveralCopies || duplicate.replacements.contains { replacement in
            let path = replacement.old
            let isCiceros = path.hasPrefix(locations.userFonts.path + "/") || locations.isInInactiveFolder(path)
                || data.fontLibrary.map { path.hasPrefix($0.path + "/") } == true
            return !isCiceros
        }
    }

    func replaceWarning(_ duplicate: AddedDuplicate) -> String {
        let spare = spareCopies(duplicate)
        let replaced = duplicate.replacements.map(\.old).filter { !spare.contains($0) }
        let files = replaced.count == 1 ? "the file \(places(of: replaced))" : "\(replaced.count) files: \(places(of: replaced))"
        guard !spare.isEmpty else { return "Replaces \(files)" }
        let copies = spare.count == 1 ? "Cicero’s copy \(places(of: spare)) goes" : "Cicero’s copies \(places(of: spare)) go"
        return "Replaces \(files), and \(copies) to the Trash"
    }

    func setInstallsIntoFontLibrary(_ on: Bool) {
        guard on != data.installsIntoFontLibrary else { return }
        var changed = data
        if on {
            if let location = changed.takeBackFontLibrary() { deselect { $0 == .folder(location.id) } }
        } else {
            changed.keepFontLibraryAsLocation(hasFonts: changed.fontLibrary.map { fontLibraryHasFonts($0.url) } ?? false)
        }
        changed.installsIntoFontLibrary = on
        data = changed
        rescan()
    }

    func fontLibraryHasFonts(_ folder: URL) -> Bool {
        let prefix = folder.path + "/"
        return ActivationEngine.hasFontFiles(in: folder) || data.records.inPlace.contains { $0.hasPrefix(prefix) }
    }

    func changeFontLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        // One line: the panel cuts off a longer message.
        panel.message = "Choose where Cicero’s Library goes. In a folder with other files, it goes into a new “Cicero Library” folder."
        panel.directoryURL = data.fontLibrary?.url.deletingLastPathComponent()
        let current = data.fontLibrary?.url, folders = data.scannedFolders(), locations = locations
        let checker = FontLibraryFolderCheck { url in
            ActivationEngine.refusal(forFontLibraryAt: url, current: current, folders: folders, locations: locations)
        }
        panel.delegate = checker
        let response = panel.runModal()
        withExtendedLifetime(checker) {}
        guard response == .OK, let url = panel.url?.standardizedFileURL else { return }
        let destination = ActivationEngine.fontLibraryFolder(in: url)
        enqueue { model in
            let result = await model.engine.moveFontLibrary(to: destination, records: model.data.records)
            if result.failed.isEmpty { model.data.fontLibraryPath = destination.path }
            model.finish(result)
            // What the move wrote down goes only once the new path is on the disk, so a stop in between still has it.
            if result.failed.isEmpty, model.store.flush(durably: true) { model.engine.forgetLibraryMove() }
        }
    }

    // MARK: Trash

    func requestTrash(_ families: [Family]) {
        let title = families.count == 1 ? "“\(families[0].name)”" : "\(families.count) Families"
        requestTrash(families.flatMap(\.faces), removing: families.map(\.id), title: title)
    }

    func requestTrash(_ faces: [LibraryFace], removing families: [String], title: String) {
        guard let plan = engine.trashPlan(for: faces, removing: families, in: library, title: title) else {
            return showToast("Fonts that come with macOS or an app can’t be moved to the Trash")
        }
        ask { $0.trashPlan = plan }
    }

    func moveToTrash(_ plan: TrashPlan) {
        let before = TrashUndo(plan: plan, data: data, library: library)
        enqueue { model in
            let result = await model.engine.moveToTrash(plan, records: model.data.records)
            model.data.records = result.records
            if result.failed.isEmpty {
                for name in plan.removedFamilies { model.forget(family: name) }
            }
            let trashed = result.trashed
            let unknown = result.succeeded - trashed.count
            #if CICERO_MEASURE
            model.lastTrashed = trashed
            #endif
            model.showToast(result.message, undo: trashed.isEmpty ? nil : { [weak model] in model?.putBack(trashed, unknown: unknown, as: before) })
            model.rescan()
        }
    }

    func putBack(_ trashed: [String: String], unknown: Int, as before: TrashUndo) {
        enqueue { model in
            let outcome = await model.engine.putBack(trashed, off: before.off)
            let back = Set(outcome.back)
            var records = model.data.records
            for path in back {
                if let origin = before.data.records.installedCopies[path] { records.installedCopies[path] = origin }
                if let origin = before.data.records.appFolderOrigins[path] { records.appFolderOrigins[path] = origin }
            }
            model.data.records = records
            model.restore(families: before.removedFamilies, from: before.data)
            if !back.isEmpty, let library = try? await model.scanner.scan(model.scanInput, progress: { _ in }) {
                let faces = library.families.flatMap(\.faces).filter { back.contains($0.face.path) }
                let on = faces.filter { before.on.contains($0.face.path) && $0.canActivate }
                if !on.isEmpty { model.data.records = await model.engine.activate(on, method: .inPlace, records: model.data.records).records }
                let forNow = faces.filter { before.onForNow.contains($0.face.path) && $0.canActivateTemporarily }
                if !forNow.isEmpty { model.data.records = await model.engine.activateTemporarily(forNow, records: model.data.records).records }
                // macOS turns a file that comes back into the Fonts folder on by itself.
                let off = faces.filter { before.off.contains($0.face.path) && $0.state.isActive && $0.canDeactivate }
                if !off.isEmpty { model.data.records = await model.engine.deactivate(off, records: model.data.records).records }
            }
            model.rescan()
            model.showToast(Self.putBackMessage(back: back.count, problems: outcome.problems, unknown: unknown))
        }
    }

    private func restore(families names: [String], from before: UserData) {
        var data = self.data
        for name in names {
            for old in before.sets where old.families.contains(name) || old.styles[name] != nil {
                guard let index = data.sets.firstIndex(where: { $0.id == old.id }) else { continue }
                if old.families.contains(name), !data.sets[index].families.contains(name) { data.sets[index].families.append(name) }
                if let styles = old.styles[name], data.sets[index].styles[name] == nil { data.sets[index].styles[name] = styles }
            }
            if data.familyTags[name] == nil { data.familyTags[name] = before.familyTags[name] }
            if data.familyRatings[name] == nil { data.familyRatings[name] = before.familyRatings[name] }
            if data.familyNotes[name] == nil { data.familyNotes[name] = before.familyNotes[name] }
            if data.activations[name] == nil { data.activations[name] = before.activations[name] }
            if data.foundryOverrides[name] == nil { data.foundryOverrides[name] = before.foundryOverrides[name] }
        }
        self.data = data
    }

    static func putBackMessage(back: Int, problems: [String: ActivationEngine.PutBackProblem], unknown: Int = 0) -> String {
        guard !problems.isEmpty || unknown > 0 else { return back == 1 ? "Put back from the Trash" : "Put back \(back) files from the Trash" }
        let total = back + problems.count + unknown
        guard !problems.isEmpty else { return "Put back \(back) of \(total) files" }
        let gone = problems.values.count { $0 == .notInTrash }, taken = problems.values.count { $0 == .pathTaken }
        let reasons = [gone > 0 ? "\(gone) no longer in the Trash" : nil, taken > 0 ? "\(taken) where another file is now" : nil,
                       problems.count - gone - taken > 0 ? "\(problems.count - gone - taken) couldn’t be moved" : nil].compactMap { $0 }
        let lead = back == 0 ? (total == 1 ? "Couldn’t put the file back" : "Couldn’t put the files back")
            : "Put back \(back) of \(total) files"
        return lead + ": " + reasons.joined(separator: ", ")
    }

    struct TrashUndo {
        let data: UserData
        let removedFamilies: [String]
        let on: Set<String>
        let onForNow: Set<String>
        let off: Set<String>

        init(plan: TrashPlan, data: UserData, library: Library) {
            self.data = data
            removedFamilies = plan.removedFamilies
            let paths = Set(plan.paths)
            var on: Set<String> = [], onForNow: Set<String> = [], off: Set<String> = []
            for face in library.families.lazy.flatMap(\.faces) where paths.contains(face.face.path) {
                switch face.position {
                case .on: if face.isOnUntilQuit { onForNow.insert(face.face.path) } else { on.insert(face.face.path) }
                case .off: off.insert(face.face.path)
                case .app: break
                }
            }
            (self.on, self.onForNow, self.off) = (on, onForNow, off)
        }
    }

    private func forget(family name: String) {
        for index in data.sets.indices { data.sets[index].remove(families: [name]) }
        data.familyTags[name] = nil
        data.familyRatings[name] = nil
        data.familyNotes[name] = nil
        data.activations[name] = nil
        data.foundryOverrides[name] = nil
        selectedIDs.remove(name)
        if openFamilyID == name { openFamilyID = nil }
    }

    // MARK: Finder

    func reveal(_ families: [Family]) {
        var seen = Set<String>()
        let urls = families.flatMap(\.faces).flatMap { [$0.face.path] + $0.otherCopies }
            .filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Info panel

    func toggleInfo() {
        if isInfoPresented && shownInfoTab == .info {
            isInfoPresented = false
        } else {
            infoTab = .info
            isInfoPresented = true
        }
    }

    // MARK: Folders

    func presentAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain fonts. They’re listed in your library without being activated."
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func addFolders(_ urls: [URL]) {
        let existing = Set(data.folders.map(\.path))
        let new = urls.map(\.standardizedFileURL.path).filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        for path in new {
            if WatchedFolder.detectAppName(forPath: path) != nil {
                data.showAdobeAppFolders = true
            } else {
                data.folders.append(WatchedFolder(path: path))
            }
        }
        data.sidebar.hidden.remove(SidebarSection.folders.key)
        rescan()
    }

    func removeFolder(_ id: UUID) {
        removeFolders([id])
    }

    func removeFolders(_ ids: Set<UUID>) {
        turnOffKeptFonts(in: data.folders.filter { ids.contains($0.id) && $0.isActive })
        forgetFolders(ids)
        rescan()
    }

    func forgetFolders(_ ids: Set<UUID>) {
        data.folders.removeAll { ids.contains($0.id) }
        for id in ids {
            data.sidebar.forget("folder.\(id)")
            data.folderNames[id.uuidString] = nil
        }
        deselect { item in ids.contains { item == .folder($0) } }
    }

    func availability(ofFolder id: UUID) -> FolderAvailability? {
        library.unavailableFolders[id]
    }

    func onlineOnlyCount(inFolder id: UUID) -> Int {
        library.onlineOnlyFiles[id]?.count ?? 0
    }

    func downloadOnlineOnlyFonts(inFolder id: UUID) {
        let paths = library.onlineOnlyFiles[id] ?? []
        guard !paths.isEmpty, downloads[id] == nil else { return }
        downloads[id] = DownloadProgress(done: 0, total: paths.count)
        Task { [weak self] in
            let failed = await Reachability.download(paths) { [weak self] done in
                Task { @MainActor in self?.downloads[id]?.done = done }
            }
            guard let self else { return }
            downloads[id] = nil
            if failed.isEmpty {
                showToast(paths.count == 1 ? "Downloaded 1 font file" : "Downloaded \(paths.count.plain) font files")
            } else {
                showToast("Couldn’t download \(failed.count.plain) of \(paths.count.plain) font files. Check the connection and try again")
            }
            rescan()
        }
    }

    func openFilesAndFoldersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }

    func setActivation(ofFolder id: UUID, active: Bool, app: String?) {
        guard let index = data.folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = data.folders[index]
        let trimmed = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = active || trimmed?.isEmpty != false ? nil : trimmed
        guard folder.isActive != active || folder.appName != app else { return }
        if folder.isActive && !active { turnOffKeptFonts(in: [folder]) }
        data.folders[index].isActive = active
        data.folders[index].appName = app
        if active { keepOn(faces(in: [folder])) }
        rescan()
    }

    func faces(in folders: [WatchedFolder]) -> [LibraryFace] {
        let prefixes = folders.map { $0.path + "/" }
        guard !prefixes.isEmpty else { return [] }
        return library.families.flatMap(\.faces).filter { face in
            prefixes.contains { face.face.path.hasPrefix($0) } && !locations.isInInactiveFolder(face.face.path)
        }
    }

    func keepOn(_ faces: [LibraryFace]) {
        let targets = faces.filter(\.canActivate)
        guard !targets.isEmpty else { return }
        performActivation(targets)
    }

    private func turnOffKeptFonts(in folders: [WatchedFolder]) {
        let targets = faces(in: folders).filter { $0.canDeactivate && data.records.inPlace.contains($0.face.path) }
        guard !targets.isEmpty else { return }
        performDeactivation(targets)
    }

    var addedFileURLs: [URL] {
        data.fontFiles.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func finderURLs(ofFolder id: UUID) -> [URL] {
        switch id {
        case WatchedFolder.adobeAppsID: WatchedFolder.appFontFolders().map(\.url)
        case WatchedFolder.addedFilesID: addedFileURLs
        default: folder(id).map { [$0.url] } ?? []
        }
    }

    func isRemovableFolder(_ id: UUID) -> Bool {
        data.folders.contains { $0.id == id }
    }

    func folder(_ id: UUID) -> WatchedFolder? {
        if id == WatchedFolder.fontLibraryID { return data.fontLibrary.map(data.named) }
        return data.folders.first { $0.id == id }.map(data.named)
    }

    func folderName(_ id: UUID) -> String {
        (folder(id) ?? data.named(WatchedFolder(id: id, path: ""))).displayName
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var own = folder(id) ?? WatchedFolder(id: id, path: "")
        own.customName = nil
        data.folderNames[id.uuidString] = trimmed.isEmpty || trimmed == own.displayName ? nil : trimmed
    }

    // MARK: Sets

    func addSet(named name: String, with families: [Family] = [], styles: [String: [String]] = [:]) {
        data.addSet(named: name, families: families.map(\.id), styles: styles)
    }

    func renameSet(_ id: UUID, to name: String) {
        data.renameSet(id, to: name)
    }

    func deleteSets(_ ids: Set<UUID>) {
        data.deleteSets(ids)
        deselect { if case .set(let id) = $0 { ids.contains(id) } else { false } }
    }

    func isMember(_ family: Family, of setID: UUID) -> Bool {
        data.sets.first { $0.id == setID }?.families.contains(family.id) ?? false
    }

    func setMembership(_ member: Bool, for families: [Family], in setID: UUID) {
        data.setMembership(member, for: families.map(\.id), in: setID)
    }

    func isMember(_ face: LibraryFace, of family: Family, in setID: UUID) -> Bool {
        data.sets.first { $0.id == setID }?.contains(style: face.face.postScriptName, of: family.id) ?? false
    }

    func setMembership(_ member: Bool, for face: LibraryFace, of family: Family, in setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        if member {
            data.sets[index].add(style: face.face.postScriptName, of: family.id)
        } else {
            data.sets[index].remove(style: face.face.postScriptName, of: family.id, all: family.faces.map(\.face.postScriptName))
        }
    }

    func faces(in item: SidebarItem) -> [LibraryFace] {
        let families = families(in: item)
        if item == .temporary { return families.flatMap { $0.faces.filter(\.isOnUntilQuit) } }
        guard case .set(let id) = item, let set = data.sets.first(where: { $0.id == id }) else { return families.flatMap(\.faces) }
        return families.flatMap { family in family.faces.filter { set.contains(style: $0.face.postScriptName, of: family.id) } }
    }

    func families(in item: SidebarItem) -> [Family] {
        let test = filter(for: item)
        return library.families.filter { data.lists($0) && test($0) }
    }

    func faces(in items: [SidebarItem]) -> [LibraryFace] {
        guard items.count > 1 else { return items.first.map { faces(in: $0) } ?? [] }
        var seen = Set<FaceID>()
        return items.flatMap { faces(in: $0) }.filter { seen.insert($0.id).inserted }
    }

    func activateFonts(in rows: [SidebarRow]) {
        let faces = faces(in: rows.map(\.item))
        let names = rows.map { "“\($0.title)”" }.listed()
        guard !faces.isEmpty else { return showToast("There are no fonts in \(names)") }
        activate(faces, title: names)
    }

    func activateFontsTemporarily(in items: [SidebarItem]) {
        let faces = faces(in: items)
        guard !faces.isEmpty else { return showToast("Nothing to activate") }
        activateTemporarily(faces)
    }

    func deactivateFonts(in items: [SidebarItem]) {
        let faces = faces(in: items)
        guard !faces.isEmpty else { return showToast("Nothing to deactivate") }
        deactivate(faces)
    }

    // MARK: Smart sets

    func saveSmartSet(_ smartSet: SmartSet) {
        if let index = data.smartSets.firstIndex(where: { $0.id == smartSet.id }) {
            data.smartSets[index] = smartSet
        } else {
            data.smartSets.append(smartSet)
            data.sidebar.hidden.remove(SidebarSection.sets.key)
            selection = .smartSet(smartSet.id)
        }
    }

    func deleteSmartSets(_ ids: Set<UUID>) {
        data.smartSets.removeAll { ids.contains($0.id) }
        for id in ids { data.sidebar.forget("smartset.\(id)") }
        deselect { if case .smartSet(let id) = $0 { ids.contains(id) } else { false } }
    }

    // MARK: Foundries

    func setFoundry(_ name: String?, for families: [Family]) {
        for family in families {
            data.foundryOverrides[family.id] = name?.isEmpty == false ? name : nil
        }
    }

    func renameFoundry(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        for family in library.families where family.manufacturer.map({ data.foundryRenames[$0] ?? $0 }) == old {
            if let raw = family.manufacturer { data.foundryRenames[raw] = trimmed }
        }
        for (family, foundry) in data.foundryOverrides where foundry == old { data.foundryOverrides[family] = trimmed }
        data.sidebar.rename("foundry.\(old)", to: "foundry.\(trimmed)")
        if selectedItems.contains(.foundry(old)) {
            selectSidebarItems(Set(selectedItems.map { $0 == .foundry(old) ? .foundry(trimmed) : $0 }))
        }
    }

    // MARK: Character sets

    func saveCharacterSet(_ set: CustomCharacterSet) {
        if let index = data.customCharacterSets.firstIndex(where: { $0.id == set.id }) {
            data.customCharacterSets[index] = set
        } else {
            data.customCharacterSets.append(set)
            data.sidebar.hidden.remove(SidebarSection.characterSets.key)
        }
    }

    func deleteCharacterSets(_ ids: Set<UUID>) {
        let setIDs = Set(ids.map { "custom.\($0.uuidString)" })
        data.customCharacterSets.removeAll { ids.contains($0.id) }
        for setID in setIDs { data.sidebar.forget("charset.\(setID)") }
        deselect { if case .characterSet(let id) = $0 { setIDs.contains(id) } else { false } }
    }

    // MARK: Drag and drop

    func takesFamilies(_ item: SidebarItem) -> Bool {
        switch item {
        case .set, .tag, .foundry, .classification: true
        default: false
        }
    }

    func handleDrop(_ drags: [FontDrag], on item: SidebarItem) -> Bool {
        var seen = Set<String>()
        let families = drags.flatMap(\.families).compactMap { family($0) }.filter { seen.insert($0.id).inserted }
        guard !families.isEmpty else { return false }
        switch item {
        case .set(let id):
            for drag in drags {
                let dragged = drag.families.compactMap { family($0) }
                if let style = drag.style, let family = dragged.first, let face = family.faces.first(where: { $0.face.postScriptName == style }) {
                    setMembership(true, for: face, of: family, in: id)
                } else {
                    setMembership(true, for: dragged, in: id)
                }
            }
        case .tag(let name): setTag(name, true, for: families)
        case .foundry(let name): setFoundry(name, for: families)
        case .classification(let name): setClassification(name, for: families)
        default: return false
        }
        return true
    }

    // MARK: Sidebar

    var sections: [SidebarSection] {
        data.sidebar.ordered(SidebarSection.allCases, in: "sections", key: \.key)
    }

    var libraryRows: [SidebarRow] {
        let rows = [
            SidebarRow(key: "library.all", title: "All Fonts", icon: "books.vertical", item: .all),
            SidebarRow(key: "library.active", title: "Active", icon: "checkmark.seal", item: .active),
            SidebarRow(key: "library.inactive", title: "Inactive", icon: "xmark.seal", item: .inactive),
            hasTemporaryFonts || selectedItems.contains(.temporary)
                ? SidebarRow(key: "library.temporary", title: "Temporary", icon: "clock", item: .temporary) : nil,
            SidebarRow(key: "library.recent", title: "Recents", icon: "tray.and.arrow.down", item: .recent),
            data.showSystemFonts ? SidebarRow(key: "library.system", title: "System Fonts", icon: "apple.logo", item: .system) : nil,
            SidebarRow(key: "library.problems", title: "Conflicts", icon: "exclamationmark.triangle", item: .problems, badge: problems.count { !$0.kind.isMinor }),
        ].compactMap { $0 }
        return data.sidebar.ordered(rows, in: "library", key: \.key)
    }

    var hasTemporaryFonts: Bool { library.hasFacesOnUntilQuit }

    func rows(for section: SidebarSection) -> [SidebarRow] {
        let rows = unorderedRows(for: section)
        return section == .characterSets ? rows : data.sidebar.ordered(rows, in: section.rawValue, key: \.key)
    }

    private func unorderedRows(for section: SidebarSection) -> [SidebarRow] {
        switch section {
        case .folders:
            var folders = data.folders
            if ownFoldersWithFonts.contains(WatchedFolder.adobeAppsID) {
                folders.append(WatchedFolder(id: WatchedFolder.adobeAppsID, path: "", appName: "Adobe"))
            }
            if ownFoldersWithFonts.contains(WatchedFolder.adobeFontsID) {
                folders.append(WatchedFolder(id: WatchedFolder.adobeFontsID, path: ""))
            }
            if ownFoldersWithFonts.contains(WatchedFolder.addedFilesID) {
                folders.append(WatchedFolder(id: WatchedFolder.addedFilesID, path: ""))
            }
            return folders.map {
                let icon = $0.id == WatchedFolder.addedFilesID ? "doc"
                    : library.unavailableFolders[$0.id] != nil ? "questionmark.folder" : "folder"
                return SidebarRow(key: "folder.\($0.id)", title: data.named($0).displayName, icon: icon, item: .folder($0.id))
            }
        case .sets:
            return data.sets.map { SidebarRow(key: "set.\($0.id)", title: $0.name, icon: $0.apps.isEmpty ? "folder" : "app.badge.checkmark", item: .set($0.id)) }
                + data.smartSets.map { SidebarRow(key: "smartset.\($0.id)", title: $0.name, icon: "gearshape", item: .smartSet($0.id)) }
        case .tags:
            return data.tags.map { SidebarRow(key: "tag.\($0)", title: $0, icon: SidebarSection.tags.icon, item: .tag($0), color: data.tagColors[$0]) }
        case .foundries:
            return foundryNames.map { SidebarRow(key: "foundry.\($0)", title: $0, icon: "building.2", item: .foundry($0)) }
        case .classifications:
            return presentClassifications.map {
                SidebarRow(key: "classification.\($0)", title: $0, icon: classificationIcon($0), item: .classification($0))
            }
        case .characterSets:
            return characterSets.map {
                SidebarRow(key: "charset.\($0.id)", title: $0.name, icon: $0.isCustom ? "character.cursor.ibeam" : "textformat.abc", item: .characterSet($0.id))
            }
        }
    }

    var selectionTitle: String {
        if let name = similarName { return "Similar to \(name)" }
        if let list = documentList { return "Fonts in “\(list.name)”" }
        let item = selection ?? .all
        if selectedItems.count > 1 {
            return rows(inList: sidebarList(of: item))
                .filter { selectedItems.contains($0.item) && $0.item != .problems }
                .map(\.title).listed()
        }
        if let row = libraryRows.first(where: { $0.item == item }) { return row.title }
        for section in SidebarSection.allCases {
            if let row = rows(for: section).first(where: { $0.item == item }) { return row.title }
        }
        return "Fonts"
    }

    func isVisible(_ key: String) -> Bool { SidebarRow.alwaysShown.contains(key) || !data.sidebar.hidden.contains(key) }

    func setVisible(_ key: String, _ visible: Bool) {
        if visible { data.sidebar.hidden.remove(key) } else { hide([key]) }
    }

    func hide(_ keys: [String]) {
        data.sidebar.hidden.formUnion(keys.filter { !SidebarRow.alwaysShown.contains($0) })
        deselect { !isShown($0) }
    }

    func menuTargets(of row: SidebarRow, selected: Set<SidebarItem>) -> [SidebarRow] {
        guard selected.count > 1, selected.contains(row.item) else { return [row] }
        let rows = rows(inList: sidebarList(of: row.item)).filter { selected.contains($0.item) }
        return rows.isEmpty ? [row] : rows
    }

    func dragOutOfSidebar(_ rows: [SidebarRow]) {
        let rows = rows.filter { $0.canHide && isVisible($0.key) }
        guard !rows.isEmpty else { return }
        let before = data
        var locations: [SidebarRow] = [], deleted: [SidebarRow] = [], hidden: [SidebarRow] = []
        for row in rows {
            switch row.item {
            case .folder(let id) where isRemovableFolder(id): locations.append(row)
            case .set, .smartSet, .tag: deleted.append(row)
            default: hidden.append(row)
            }
        }
        if !locations.isEmpty {
            removeFolders(Set(locations.compactMap { if case .folder(let id) = $0.item { id } else { nil } }))
        }
        let sets = Set(deleted.compactMap { if case .set(let id) = $0.item { id } else { nil } })
        if !sets.isEmpty { deleteSets(sets) }
        let smartSets = Set(deleted.compactMap { if case .smartSet(let id) = $0.item { id } else { nil } })
        if !smartSets.isEmpty { deleteSmartSets(smartSets) }
        let tags = Set(deleted.compactMap { if case .tag(let name) = $0.item { name } else { nil } })
        if !tags.isEmpty { deleteTags(tags) }
        if !hidden.isEmpty { hide(hidden.map(\.key)) }

        func names(_ rows: [SidebarRow], _ noun: String) -> String {
            rows.count > 3 ? "\(rows.count) \(noun)" : rows.map(\.title).listed()
        }
        let deletedNoun = deleted.allSatisfy { if case .tag = $0.item { true } else { false } } ? "tags" : "folders"
        let message = [
            locations.isEmpty ? nil : "\(names(locations, "locations")) removed from the library",
            deleted.isEmpty ? nil : "\(names(deleted, deletedNoun)) deleted",
            hidden.isEmpty ? nil : "\(names(hidden, "items")) hidden from the sidebar",
        ].compactMap { $0 }.joined(separator: " and ")
        showToast(message) { [weak self] in
            guard let self else { return }
            var data = self.data
            // The lists as they were before the drag, so what was changed in them since is lost.
            data.folders = before.folders
            data.folderNames = before.folderNames
            data.sets = before.sets
            data.smartSets = before.smartSets
            data.tags = before.tags
            data.familyTags = before.familyTags
            data.tagColors = before.tagColors
            data.sidebar = before.sidebar
            self.data = data
            if !locations.isEmpty { rescan() }
        }
    }

    func selectSidebarItems(_ items: Set<SidebarItem>) {
        let items = sidebarSelection(items, from: selectedItems)
        guard let any = items.first else { selection = nil; return }
        let list = sidebarList(of: any)
        let candidates = items.count > 1 ? items.subtracting([.problems]) : items
        let primary = selection.flatMap { candidates.contains($0) ? $0 : nil }
            ?? rows(inList: list).first { candidates.contains($0.item) }?.item ?? candidates.first
        if selection != primary { selection = primary }
        if selectedItems != items {
            selectedItems = items
            selectedIDs = []
            openFamilyID = nil
        }
    }

    func sidebarSelection(_ items: Set<SidebarItem>, from current: Set<SidebarItem>) -> Set<SidebarItem> {
        guard !items.isEmpty else { return [] }
        let added = items.subtracting(current)
        let anchor = added.count == 1 ? added.first! : selection.flatMap { items.contains($0) ? $0 : nil } ?? items.first!
        let list = sidebarList(of: anchor)
        return items.filter { sidebarList(of: $0) == list }
    }

    func deselect(where remove: (SidebarItem) -> Bool) {
        let kept = selectedItems.filter { !remove($0) }
        guard kept != selectedItems else { return }
        if kept.isEmpty { selection = .all } else { selectSidebarItems(kept) }
    }

    func sidebarList(of item: SidebarItem) -> String {
        switch item {
        case .all, .active, .inactive, .temporary, .system, .recent, .problems: "library"
        case .folder: SidebarSection.folders.rawValue
        case .set, .smartSet: SidebarSection.sets.rawValue
        case .tag: SidebarSection.tags.rawValue
        case .foundry: SidebarSection.foundries.rawValue
        case .classification: SidebarSection.classifications.rawValue
        case .characterSet(let id):
            "charsetgroup.\(id.hasPrefix("custom.") ? CharacterSetDefinition.customGroupID : characterSetCatalog.definition(id)?.groupID ?? "")"
        }
    }

    private func rows(inList list: String) -> [SidebarRow] {
        if list == "library" { return libraryRows }
        if let section = SidebarSection(rawValue: list) { return rows(for: section) }
        return characterSetGroups.first { "charsetgroup.\($0.id)" == list }?.rows ?? []
    }

    var characterSetGroups: [(id: String, title: String, rows: [SidebarRow])] {
        func row(_ set: CharacterSetDefinition) -> SidebarRow {
            SidebarRow(key: "charset.\(set.id)", title: set.name, icon: set.isCustom ? "character.cursor.ibeam" : "textformat.abc", item: .characterSet(set.id))
        }
        var groups = characterSetCatalog.groups.map { (id: $0.id, title: $0.name, rows: $0.sets.map(row)) }
        if !data.customCharacterSets.isEmpty {
            groups.append((id: CharacterSetDefinition.customGroupID, title: "Your Coverage Sets", rows: customCharacterSets.map(row)))
        }
        let ordered = groups.map { (id: $0.id, title: $0.title, rows: data.sidebar.ordered($0.rows, in: "charsetgroup.\($0.id)", key: \.key)) }
        return data.sidebar.ordered(ordered, in: SidebarSection.characterSets.rawValue) { "charsetgroup.\($0.id)" }
    }

    func hideGroup(_ id: String) {
        guard let group = characterSetGroups.first(where: { $0.id == id }) else { return }
        hide(group.rows.map(\.key))
    }

    func isGroupExpanded(_ id: String) -> Bool { !data.sidebar.collapsed.contains("charsetgroup.\(id)") }

    func setGroupExpanded(_ id: String, _ expanded: Bool) {
        if expanded { data.sidebar.collapsed.remove("charsetgroup.\(id)") } else { data.sidebar.collapsed.insert("charsetgroup.\(id)") }
    }

    func showAllSidebarItems() {
        data.sidebar.hidden.removeAll()
    }

    func moveSidebarItems(_ source: IndexSet, to destination: Int, shown: [String], all: [String], in list: String) {
        data.sidebar.move(source, to: destination, shown: shown, all: all, in: list)
    }

    var hasSidebarOrder: Bool { !data.sidebar.order.isEmpty }

    func resetSidebarOrder() {
        data.sidebar.order = [:]
    }

    private func isShown(_ item: SidebarItem) -> Bool {
        if let row = libraryRows.first(where: { $0.item == item }) { return isVisible(row.key) }
        for section in SidebarSection.allCases {
            if let row = rows(for: section).first(where: { $0.item == item }) { return isVisible(section.key) && isVisible(row.key) }
        }
        return true
    }

    func isExpanded(_ section: SidebarSection) -> Bool { !data.sidebar.collapsed.contains(section.rawValue) }

    func setExpanded(_ section: SidebarSection, _ expanded: Bool) {
        if expanded { data.sidebar.collapsed.remove(section.rawValue) } else { data.sidebar.collapsed.insert(section.rawValue) }
    }

    // MARK: Prompts

    func prompt(_ title: String, text: String = "", confirm: String, action: @escaping (String) -> Void) {
        ask { $0.textPrompt = TextPrompt(title: title, initialText: text, confirmTitle: confirm, action: action) }
    }

    // MARK: Compare

    static let compareLimit = 12

    var isCompareFull: Bool { compareEntries.count >= Self.compareLimit }

    func compare(_ families: [Family]) {
        compareEntries = []
        _ = addToCompare(families.map(\.id))
    }

    func addToCompare(_ names: [String]) -> Bool {
        let new = names.filter { name in family(name) != nil && !compareEntries.contains { $0.familyID == name } }
        let added = new.prefix(Self.compareLimit - compareEntries.count)
        for name in added {
            compareEntries.append(CompareEntry(familyID: name, tint: nextCompareTint))
        }
        if added.count < new.count {
            showToast("Compare holds up to \(Self.compareLimit) styles")
        }
        return !added.isEmpty
    }

    func compareAnotherStyle(of id: UUID, besides shown: Set<FaceID>) {
        guard !isCompareFull, let index = compareEntries.firstIndex(where: { $0.id == id }),
              let family = family(compareEntries[index].familyID) else { return }
        let style = family.faces.first { !shown.contains($0.id) }?.id
        compareEntries.insert(CompareEntry(familyID: family.id, style: style, tint: nextCompareTint), at: index + 1)
    }

    func setCompareStyle(_ style: FaceID?, of id: UUID) {
        guard let index = compareEntries.firstIndex(where: { $0.id == id }) else { return }
        compareEntries[index].style = style
    }

    func setCompareTint(_ tint: Int, of id: UUID) {
        guard let index = compareEntries.firstIndex(where: { $0.id == id }) else { return }
        compareEntries[index].tint = tint
    }

    func removeFromCompare(_ id: UUID) {
        compareEntries.removeAll { $0.id == id }
    }

    func toggleInCompare(_ familyID: String) {
        if compareEntries.contains(where: { $0.familyID == familyID }) {
            compareEntries.removeAll { $0.familyID == familyID }
        } else {
            _ = addToCompare([familyID])
        }
    }

    func moveInCompare(_ id: UUID, to target: UUID) {
        guard let from = compareEntries.firstIndex(where: { $0.id == id }), let to = compareEntries.firstIndex(where: { $0.id == target }),
              from != to else { return }
        compareEntries.insert(compareEntries.remove(at: from), at: to)
    }

    private var nextCompareTint: Int {
        (0...).first { tint in !compareEntries.contains { $0.tint == tint } }!
    }

    // MARK: Font caches

    func clearCaches(scopes: [SystemFontCaches.Scope], apps: [AppFontCaches.App]) async -> Bool {
        guard startJob(.clearingCaches) else { return false }
        defer { endJob(.clearingCaches) }
        var trashed: [String] = []
        var failures = 0
        for app in apps {
            let found = await Task.detached(priority: .userInitiated) { AppFontCaches.find(app) }.value
            guard !found.isEmpty else { continue }
            failures += await Task.detached(priority: .userInitiated) { AppFontCaches.trash(found) }.value
            trashed.append(app.title)
        }
        var clearedSystem = false
        for scope in scopes {
            do {
                try await SystemFontCaches.clear(scope)
                clearedSystem = true
            } catch SystemFontCaches.Failure.cancelled {
            } catch {
                showToast("Couldn’t clear the macOS font caches")
            }
        }
        // Clearing them makes macOS forget the fonts Cicero uses where they are, for good or for a while: on again.
        if clearedSystem {
            await enqueued { model in
                let result = await model.engine.registerAgain(model.data.records)
                if !result.failed.isEmpty {
                    model.showToast(result.failed.count == 1 ? "Couldn’t turn 1 file on again" : "Couldn’t turn \(result.failed.count) files on again")
                }
            }
        }
        if failures > 0 {
            showToast(failures == 1 ? "Couldn’t move 1 cache item to the Trash" : "Couldn’t move \(failures) cache items to the Trash")
        } else if !trashed.isEmpty && !clearedSystem {
            showToast("Moved the \(trashed.listed()) font caches to the Trash")
        }
        if clearedSystem || !trashed.isEmpty { rebuildFontList() }
        return clearedSystem
    }

    // MARK: Problems

    func apply(_ fix: ProblemFix, family: String? = nil) {
        switch fix {
        case .reveal(let paths):
            NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
        case .deactivate(let ids):
            let ids = Set(ids)
            let faces = library.families.flatMap(\.faces).filter { ids.contains($0.id) }
            if !faces.isEmpty { deactivate(faces) }
        case .trash(let paths):
            guard let plan = engine.spareCopiesTrashPlan(paths, families: Set([family].compactMap(\.self)), in: library) else { return }
            ask { $0.trashPlan = plan }
        case .forgetInPlace(let path):
            enqueue { model in
                model.data.records = await model.engine.forgetInPlace([path], records: model.data.records)
                model.updateProblems()
                model.rescan()
            }
        case .forgetInstalledCopy(let path):
            // Queued, so an operation already running can't write its older records back over it.
            enqueue { model in
                model.data.records.installedCopies[path] = nil
                model.updateProblems()
            }
        case .removeFromSet(let id, let family):
            if let index = data.sets.firstIndex(where: { $0.id == id }) { data.sets[index].remove(families: [family]) }
            updateProblems()
        case .installCopy(let path):
            guard let face = library.families.lazy.flatMap(\.faces).first(where: { $0.face.path == path }) else { return }
            enqueue { model in
                let result = await model.engine.installCopy(of: face, records: model.data.records)
                model.finish(result)
            }
        case .removeFromAdobeFonts(let paths):
            CreativeCloud.open(paths)
        }
    }

    func forgetAll(of problems: [Problem]) {
        var inPlace: [String] = [], copies: [String] = []
        for fix in problems.flatMap(\.fixes) {
            switch fix {
            case .forgetInPlace(let path): inPlace.append(path)
            case .forgetInstalledCopy(let path): copies.append(path)
            default: break
            }
        }
        enqueue { model in
            for path in copies { model.data.records.installedCopies[path] = nil }
            if !inPlace.isEmpty {
                model.data.records = await model.engine.forgetInPlace(inPlace, records: model.data.records)
                model.rescan()
            }
            model.updateProblems()
        }
    }

    func trashExtraCopies(of problems: [Problem]) {
        var seen = Set<String>()
        let paths = problems.flatMap(\.extraCopies).filter { seen.insert($0).inserted }
        guard var plan = engine.spareCopiesTrashPlan(paths, families: Set(problems.compactMap(\.family)), in: library) else { return }
        plan.title = plan.paths.count == 1 ? "1 Extra Copy" : "\(plan.paths.count) Extra Copies"
        ask { [plan] in $0.trashPlan = plan }
    }
}

private final class FontLibraryFolderCheck: NSObject, NSOpenSavePanelDelegate {
    let refusal: (URL) -> String?

    init(refusal: @escaping (URL) -> String?) {
        self.refusal = refusal
    }

    func panel(_ sender: Any, validate url: URL) throws {
        let url = url.standardizedFileURL
        if let reason = refusal(url) {
            throw NSError(domain: "Cicero", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cicero’s Library can’t go into “\(url.lastPathComponent)”.",
                NSLocalizedRecoverySuggestionErrorKey: reason,
            ])
        }
        guard let service = ActivationEngine.cloudService(syncing: url) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch service {
        case .iCloudDrive:
            alert.messageText = "“\(url.lastPathComponent)” Syncs With iCloud Drive"
            alert.informativeText = "iCloud Drive can remove fonts from this Mac to save space, and then they can stop working in your apps. To keep them on this Mac, right-click Cicero’s Library in the Finder and choose Keep Downloaded."
        case .other:
            alert.messageText = "“\(url.lastPathComponent)” Syncs With a Cloud Service"
            alert.informativeText = "The service can remove fonts from this Mac to save space, and then they can stop working in your apps. To keep them on this Mac, right-click Cicero’s Library in the Finder and make it available offline."
        }
        alert.addButton(withTitle: "Choose Another Folder")
        alert.addButton(withTitle: "Use Anyway")
        let response: NSApplication.ModalResponse
        if let panel = sender as? NSWindow {
            // A sheet on the panel, waited for here: the panel needs the answer before Choose goes on.
            alert.beginSheetModal(for: panel) { NSApp.stopModal(withCode: $0) }
            response = NSApp.runModal(for: alert.window)
        } else {
            response = alert.runModal()
        }
        guard response == .alertSecondButtonReturn else { throw CocoaError(.userCancelled) }
    }
}
