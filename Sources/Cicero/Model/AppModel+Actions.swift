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
            model.finish(result, operation: operation, undo: model.undo(restoring: named ?? faces, failed: result.failed))
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
            model.finish(result, operation: operation, undo: model.undo(restoring: targets, failed: result.failed))
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
            model.finish(result, operation: operation, undo: model.undo(restoring: faces, failed: result.failed))
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

    func finish(_ result: ActivationResult, operation: Int? = nil, operations: [Int] = [], undo: (() -> Void)? = nil) {
        var data = data
        data.records = result.records
        data.forgetInstalledAddedFiles()
        self.data = data
        if !result.message.isEmpty { showToast(result.message, undo: undo) }
        let scan = rescan()
        for operation in [operation].compactMap(\.self) + operations { settle(operation, after: scan) }
    }

    enum EarlierState {
        case off, app, untilQuit, whileAppsRun, on

        init(_ face: LibraryFace) {
            switch face.state.temporaryScope {
            case .untilQuit: self = .untilQuit
            case .whileAppsRun: self = .whileAppsRun
            case nil: self = switch face.position { case .on: .on; case .app: .app; case .off: .off }
            }
        }

        func matches(_ face: LibraryFace) -> Bool {
            switch self {
            case .untilQuit: face.state.temporaryScope == .untilQuit
            case .whileAppsRun: face.state.temporaryScope == .whileAppsRun
            case .on: face.position == .on && face.state.temporaryScope == nil
            case .app: face.position == .app
            case .off: face.position == .off
            }
        }
    }

    func undo(restoring faces: [LibraryFace], failed: [String]) -> (() -> Void)? {
        let failed = Set(failed)
        let changed = faces.filter { !failed.contains($0.face.path) }
        guard !changed.isEmpty else { return nil }
        return { [weak self] in self?.restore(changed) }
    }

    func restore(_ earlier: [LibraryFace]) {
        let found = findAgain(earlier)
        guard !found.isEmpty else { return showToast("Couldn’t undo: these fonts are no longer in your library") }
        var off: [LibraryFace] = [], app: [LibraryFace] = [], on: [LibraryFace] = [], untilQuit: [LibraryFace] = []
        var forApps = Set<String>()
        for (old, current) in found {
            let state = EarlierState(old)
            guard !state.matches(current) else { continue }
            switch state {
            case .off: if current.canDeactivate { off.append(current) }
            case .app: if current.app != nil { app.append(current) }
            case .on: if current.canActivate { on.append(current) }
            case .untilQuit, .whileAppsRun:
                if current.state.isActive {
                    if current.app != nil {
                        app.append(current)
                    } else if current.canDeactivate {
                        off.append(current)
                    } else {
                        continue
                    }
                }
                if state == .untilQuit { untilQuit.append(current) } else { forApps.insert(current.face.postScriptName) }
            }
        }
        guard !off.isEmpty || !app.isEmpty || !on.isEmpty || !untilQuit.isEmpty || !forApps.isEmpty else { return }
        let operations = [(off, SwitchPosition.off), (app, .app), (on + untilQuit, .on)].filter { !$0.0.isEmpty }.map { expect($0.0, at: $0.1) }
        let named = found.map(\.current)
        enqueue { model in
            var records = model.data.records
            var failed: [String] = []
            var failure: String?
            func take(_ result: ActivationResult) {
                records = result.records
                failed += result.failed
                if !result.failed.isEmpty, failure == nil { failure = result.message }
            }
            if !off.isEmpty { take(await model.engine.deactivate(off, records: records)) }
            if !app.isEmpty { take(await model.engine.useInAppOnly(app, records: records)) }
            if !on.isEmpty { take(await model.engine.activate(on, method: .inPlace, records: records)) }
            let temporary = untilQuit.filter { !failed.contains($0.face.path) }.map { face in
                face.state.isActive ? LibraryFace(face: face.face, state: face.app.map(FaceState.appOnly) ?? .inactive, copies: face.copies, app: face.app) : face
            }
            if !temporary.isEmpty { take(await model.engine.activateTemporarily(temporary, records: records)) }
            let message = failure ?? "\(FontNames.describe(named) ?? "Fonts") back as before"
            model.finish(ActivationResult(records: records, succeeded: 0, failed: failed, message: message), operations: operations)
            model.appSets.allow(forApps)
        }
    }

    private func findAgain(_ earlier: [LibraryFace]) -> [(old: LibraryFace, current: LibraryFace)] {
        let names = Set(earlier.map(\.face.postScriptName))
        var byID: [FaceID: LibraryFace] = [:]
        var byName: [String: [LibraryFace]] = [:]
        for face in library.families.lazy.flatMap(\.faces) where names.contains(face.face.postScriptName) {
            byID[face.id] = face
            for copy in face.copies { byID[copy.face.id] = face }
            byName[face.face.familyName + "\u{0}" + face.face.postScriptName, default: []].append(face)
        }
        var seen = Set<FaceID>()
        return earlier.compactMap { old in
            let candidates = byName[old.face.familyName + "\u{0}" + old.face.postScriptName] ?? []
            guard let current = byID[old.id] ?? candidates.first(where: { $0.id.index == old.id.index }) ?? candidates.first,
                  seen.insert(current.id).inserted else { return nil }
            return (old, current)
        }
    }

    static func title(for families: [Family]) -> String {
        families.count == 1 ? families[0].name : "\(families.count) families"
    }

    // MARK: Copies

    func copySources(of styles: [LibraryFace]) -> [CopySource] {
        CopyChooser.sources(of: styles, folders: data.namedFolders, records: data.records, locations: locations)
    }

    func useCopies(from source: CopySource) {
        let plan = CopyChooser.plan(source, records: data.records, library: library)
        guard !plan.isEmpty else { return showToast("Already using the copies from \(source.name)") }
        let request = CopySwitchRequest(source: source.name, plan: plan)
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
        if WatchedFolder.appFontFolders().contains(where: { path.hasPrefix($0.path + "/") }) { return "in \(folderName(WatchedFolder.adobeAppsID))" }
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
                let faces = library.families.flatMap(\.faces).flatMap { [$0] + $0.copies.map(\.libraryFace) }.filter { back.contains($0.face.path) }
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
            for face in library.families.lazy.flatMap(\.faces) {
                for copy in [face] + face.copies.map(\.libraryFace) where paths.contains(copy.face.path) {
                    switch (copy.position, copy.state.temporaryScope) {
                    case (.on, .untilQuit): onForNow.insert(copy.face.path)
                    case (.on, .whileAppsRun), (.off, _): off.insert(copy.face.path)
                    case (.on, nil): on.insert(copy.face.path)
                    case (.app, _): break
                    }
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
        if isInfoShown && shownInfoTab == .info {
            isInfoShown = false
        } else {
            infoTab = .info
            isInfoShown = true
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
        let paths = urls.map(\.standardizedFileURL.path)
        var added: [WatchedFolder] = []
        var absorbedNames: [String] = []
        var alreadyInside: (sub: String, outer: String, id: UUID, rel: String)?
        var alreadyExact: WatchedFolder?
        var turnedOnAdobe = false
        let before = data
        let libraryID = data.fontLibraryLocation?.id

        for path in paths {
            if WatchedFolder.detectAppName(forPath: path) != nil {
                data.showAdobeAppFolders = true
                turnedOnAdobe = true
                continue
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if let existing = data.folders.first(where: { FolderPath.relationship(between: $0.url, and: url) == .same }) {
                alreadyExact = existing
                continue
            }
            if let outer = data.folders.first(where: { $0.id != libraryID && FolderPath.relationship(between: $0.url, and: url) == .contains }),
               let rel = FolderPath.relativePath(of: url, inside: outer.url) {
                alreadyInside = (url.lastPathComponent, data.named(outer).displayName, outer.id, rel)
                continue
            }
            let contained = data.folders.filter { $0.id != libraryID && FolderPath.relationship(between: url, and: $0.url) == .contains }
            let newFolder = WatchedFolder(path: path)
            data.folders.append(newFolder)
            let outerIndex = data.folders.count - 1
            if !contained.isEmpty {
                let firstKey = "folder.\(contained[0].id)"
                for inner in contained {
                    if let rel = FolderPath.relativePath(of: inner.url, inside: url) {
                        data.absorb(inner, into: outerIndex, relativePath: rel)
                        absorbedNames.append(data.named(inner).displayName)
                    }
                }
                if var order = data.sidebar.order["folders"], let pos = order.firstIndex(of: firstKey) {
                    order[pos] = "folder.\(newFolder.id)"
                    data.sidebar.order["folders"] = order
                }
                let removedIDs = Set(contained.map(\.id))
                data.folders.removeAll { removedIDs.contains($0.id) }
                for id in removedIDs {
                    data.folderNames[id.uuidString] = nil
                    data.sidebar.forget("folder.\(id)")
                }
                deselect { item in
                    switch item {
                    case .folder(let id), .subfolder(let id, _): removedIDs.contains(id)
                    default: false
                    }
                }
            }
            data.sidebar.expanded.insert("folder.\(newFolder.id)")
            added.append(newFolder)
        }

        if !added.isEmpty {
            data.sidebar.hidden.remove(SidebarSection.folders.key)
            rescan()
            if !absorbedNames.isEmpty, added.count == 1 {
                let outerName = data.named(added[0]).displayName
                let innerText = absorbedNames.count > 3 ? "\(absorbedNames.count) locations" : absorbedNames.map { "“\($0)”" }.listed()
                showToast("\(innerText) \(absorbedNames.count == 1 ? "is" : "are") now inside “\(outerName)”") { [weak self] in
                    guard let self else { return }
                    var restored = self.data
                    restored.folders = before.folders
                    restored.folderNames = before.folderNames
                    restored.smartSets = before.smartSets
                    restored.sidebar = before.sidebar
                    self.data = restored
                    self.rescan()
                }
            } else if added.count == 1 {
                showToast("Added “\(URL(fileURLWithPath: added[0].path).lastPathComponent)” as a location")
            } else {
                showToast("Added \(added.count.plain) locations")
            }
            return
        }
        if let inside = alreadyInside {
            if let index = data.folders.firstIndex(where: { $0.id == inside.id }), !data.showsSubfolders(for: data.folders[index]) {
                data.folders[index].showsSubfolders = true
            }
            expandAncestors(of: inside.id, relativePath: inside.rel)
            if library.folderTrees[inside.id]?.nodes[inside.rel] != nil {
                selection = .subfolder(inside.id, inside.rel)
                showToast("“\(inside.sub)” is already in “\(inside.outer)”")
            } else {
                selection = .folder(inside.id)
                showToast("“\(inside.sub)” in “\(inside.outer)” has no fonts")
            }
        } else if let existing = alreadyExact {
            selection = .folder(existing.id)
            showToast(paths.count == 1 ? "“\(data.named(existing).displayName)” is already a location" : "These folders are already locations")
        } else if turnedOnAdobe {
            data.sidebar.hidden.remove(SidebarSection.folders.key)
            rescan()
        }
    }

    func removeFolder(_ id: UUID) {
        removeFolders([id])
    }

    func removeFolders(_ ids: Set<UUID>) {
        let removed = data.folders.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        let before = data
        let keptOn = removingFolders(ids)
        let names = removed.count > 3 ? "\(removed.count) locations" : removed.map { data.named($0).displayName }.listed()
        showToast("\(names) removed from the library") { [weak self] in
            guard let self else { return }
            var data = self.data
            data.folders = before.folders
            data.folderNames = before.folderNames
            data.smartSets = before.smartSets
            data.sidebar = before.sidebar
            self.data = data
            self.rescan()
            self.turnOnAgain(keptOn)
        }
    }

    func removingFolders(_ ids: Set<UUID>) -> [LibraryFace] {
        let activeFolders = data.folders.filter { ids.contains($0.id) && $0.hasActivePolicy }
        let keptOn = turnOffKeptFonts(in: activeFolders, silently: true)
        let values = Set(ids.map(\.uuidString))
        let prefixes = ids.map { $0.uuidString + "/" }
        for index in data.smartSets.indices {
            let matches = { (rule: SmartRule) in
                rule.field == .folder && (values.contains(rule.value) || prefixes.contains(where: rule.value.hasPrefix))
            }
            if data.smartSets[index].rules.contains(where: matches) {
                data.smartSets[index].rules.removeAll(where: matches)
            }
        }
        forgetFolders(ids)
        rescan()
        return keptOn
    }

    func turnOnAgain(_ faces: [LibraryFace]) {
        guard !faces.isEmpty else { return }
        let paths = Set(faces.map(\.face.path))
        let operation = expect(faces, at: .on)
        enqueue { model in
            let library = (try? await model.scanner.scan(model.scanInput, progress: { _ in })) ?? model.library
            let on = library.families.flatMap(\.faces).filter { paths.contains($0.face.path) && $0.canActivate }
            let result = on.isEmpty ? ActivationResult(records: model.data.records, succeeded: 0, failed: [], message: "")
                : await model.engine.activate(on, method: .inPlace, records: model.data.records)
            model.finish(result, operation: operation)
        }
    }

    func forgetFolders(_ ids: Set<UUID>) {
        var data = data
        data.folders.removeAll { ids.contains($0.id) }
        for id in ids {
            data.sidebar.forget("folder.\(id)")
            data.folderNames[id.uuidString] = nil
        }
        self.data = data
        deselect { item in
            switch item {
            case .folder(let id), .subfolder(let id, _): ids.contains(id)
            default: false
            }
        }
    }

    func availability(ofFolder id: UUID) -> FolderAvailability? {
        library.unavailableFolders[id]
    }

    func onlineOnlyCount(inFolder id: UUID) -> Int {
        library.onlineOnlyFiles[id]?.count ?? 0
    }

    func onlineOnlyCount(inSubfolder rel: String, of id: UUID) -> Int {
        guard let folder = folder(id), let paths = library.onlineOnlyFiles[id] else { return 0 }
        let prefixes = FolderPath.prefixes(of: folder, relativePath: rel)
        return paths.count { path in prefixes.contains(where: path.hasPrefix) }
    }

    func downloadOnlineOnlyFonts(inFolder id: UUID) {
        let paths = library.onlineOnlyFiles[id] ?? []
        guard !paths.isEmpty, downloads[id] == nil else { return }
        downloads[id] = WorkProgress(done: 0, total: paths.count)
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

    func showsSubfolders(for id: UUID) -> Bool {
        guard let folder = data.folders.first(where: { $0.id == id }) else { return false }
        return data.showsSubfolders(for: folder)
    }

    func setShowsSubfolders(_ show: Bool, for id: UUID) {
        guard let index = data.folders.firstIndex(where: { $0.id == id }) else { return }
        data.folders[index].showsSubfolders = show
        if !show {
            let hadSubfolder = selectedItems.contains { if case .subfolder(let folderID, _) = $0 { folderID == id } else { false } }
            if hadSubfolder {
                let kept = Set(selectedItems.map { item -> SidebarItem in
                    if case .subfolder(let folderID, _) = item, folderID == id { return .folder(id) }
                    return item
                })
                selectSidebarItems(kept)
            }
        }
    }

    func setActivation(ofFolder id: UUID, active: Bool, app: String?) {
        guard let index = data.folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = data.folders[index]
        let trimmed = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active, trimmed?.isEmpty == true { return }
        let app = active ? nil : trimmed
        guard folder.isActive != active || folder.appName != app else { return }
        let affected = facesAffected(by: folder, subfolder: nil)
        if folder.isActive && !active { turnOffKeptFaces(affected) }
        data.folders[index].isActive = active
        data.folders[index].appName = app
        if active && !folder.isActive { keepOn(affected) }
        rescan()
    }

    func setActivation(ofSubfolder rel: String, in id: UUID, policy: FolderPolicy?) {
        guard let index = data.folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = data.folders[index]
        let previous = folder.policy(forSubfolder: rel)
        let next: (isActive: Bool, appName: String?)
        var storedPolicy = policy
        if let policy {
            let trimmed = policy.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if !policy.isActive, trimmed?.isEmpty == true { return }
            let app = policy.isActive ? nil : trimmed
            storedPolicy = FolderPolicy(isActive: policy.isActive, appName: app, fileID: FolderPath.fileID(of: folder.path + "/" + rel))
            next = (policy.isActive, app)
        } else {
            next = folder.inheritedPolicy(forSubfolder: rel)
        }
        guard folder.subfolders[rel]?.isActive != storedPolicy?.isActive || folder.subfolders[rel]?.appName != storedPolicy?.appName else { return }
        let affected = facesAffected(by: folder, subfolder: rel)
        if previous.isActive && !next.isActive { turnOffKeptFaces(affected) }
        data.folders[index].subfolders[rel] = storedPolicy
        if !previous.isActive && next.isActive { keepOn(affected) }
        rescan()
    }

    func facesAffected(by folder: WatchedFolder, subfolder: String?) -> [LibraryFace] {
        let prefixes = FolderPath.prefixes(of: folder, relativePath: subfolder)
        let deeperKeys = folder.subfolders.keys.filter { key in
            if let subfolder { return key.hasPrefix(subfolder + "/") }
            return true
        }
        let deeperPrefixes = deeperKeys.flatMap { FolderPath.prefixes(of: folder, relativePath: $0) }
        return library.families.flatMap(\.faces).filter { face in
            let path = face.face.path
            guard !locations.isInInactiveFolder(path), prefixes.contains(where: path.hasPrefix) else { return false }
            return !deeperPrefixes.contains(where: path.hasPrefix)
        }
    }

    func faces(in folders: [WatchedFolder]) -> [LibraryFace] {
        guard !folders.isEmpty else { return [] }
        let roots = folders.map { (folder: $0, prefixes: FolderPath.prefixes(of: $0)) }
        return library.families.flatMap(\.faces).filter { face in
            let path = face.face.path
            guard !locations.isInInactiveFolder(path) else { return false }
            return roots.contains { root in
                root.prefixes.contains(where: path.hasPrefix) && root.folder.policy(forPath: path).isActive
            }
        }
    }

    func keepOn(_ faces: [LibraryFace]) {
        let targets = faces.filter(\.canActivate)
        guard !targets.isEmpty else { return }
        performActivation(targets)
    }

    @discardableResult
    private func turnOffKeptFonts(in folders: [WatchedFolder], silently: Bool = false) -> [LibraryFace] {
        turnOffKeptFaces(faces(in: folders), silently: silently)
    }

    @discardableResult
    private func turnOffKeptFaces(_ faces: [LibraryFace], silently: Bool = false) -> [LibraryFace] {
        let targets = faces.filter { $0.canDeactivate && data.records.inPlace.contains($0.face.path) }
        guard !targets.isEmpty else { return [] }
        guard silently else {
            performDeactivation(targets)
            return targets
        }
        let operation = expect(targets, at: .off)
        enqueue { model in
            var result = await model.engine.deactivate(targets, records: model.data.records)
            if result.failed.isEmpty { result.message = "" }
            model.finish(result, operation: operation)
        }
        return targets
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

    func finderURLs(of item: SidebarItem) -> [URL] {
        switch item {
        case .folder(let id): finderURLs(ofFolder: id)
        case .subfolder(let id, let rel): folder(id).map { [$0.url.appendingPathComponent(rel, isDirectory: true)] } ?? []
        default: []
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

    func subfolderParentName(of rel: String, in id: UUID) -> String {
        if let slash = rel.lastIndex(of: "/") {
            let parent = String(rel[..<slash])
            return (parent as NSString).lastPathComponent
        }
        return folderName(id)
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var own = folder(id) ?? WatchedFolder(id: id, path: "")
        own.customName = nil
        data.folderNames[id.uuidString] = trimmed.isEmpty || trimmed == own.displayName ? nil : trimmed
    }

    // MARK: Sets

    func addSet(named name: String, parentID: UUID? = nil, with families: [Family] = [], styles: [String: [String]] = [:]) {
        data.addSet(named: name, parentID: parentID, families: families.map(\.id), styles: styles)
    }

    func renameSet(_ id: UUID, to name: String) {
        data.renameSet(id, to: name)
    }

    func deleteSets(_ ids: Set<UUID>, undoable: Bool = true) {
        let removed = data.sets.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        let before = data
        var allSets = ids
        var allSmartSets = Set<UUID>()
        for id in ids {
            allSets.formUnion(data.descendants(ofSet: id))
            allSmartSets.formUnion(data.subtreeSmartSets(of: id))
        }
        data.deleteSets(ids)
        deselect { item in
            switch item {
            case .set(let id): allSets.contains(id)
            case .smartSet(let id): allSmartSets.contains(id)
            default: false
            }
        }
        guard undoable else { return }
        let names = removed.count > 3 ? "\(removed.count) folders" : removed.map(\.name).listed()
        showToast("\(names) deleted") { [weak self] in
            guard let self else { return }
            var restored = self.data
            restored.sets = before.sets
            restored.smartSets = before.smartSets
            restored.sidebar = before.sidebar
            self.data = restored
        }
    }

    func moveFolderItems(_ items: [SidebarItem], to parentID: UUID?) {
        var setIDs = Set<UUID>()
        var smartIDs = Set<UUID>()
        for item in items {
            switch item {
            case .set(let id): setIDs.insert(id)
            case .smartSet(let id): smartIDs.insert(id)
            default: break
            }
        }
        setIDs = setIDs.filter { id in data.ancestorIDs(ofSet: id).allSatisfy { !setIDs.contains($0) } }
        smartIDs = smartIDs.filter { id in
            guard let smart = data.smartSets.first(where: { $0.id == id }), let parent = smart.parentID else { return true }
            return !setIDs.contains(parent) && data.ancestorIDs(ofSet: parent).allSatisfy { !setIDs.contains($0) }
        }
        let validSets = setIDs.filter { data.canMove(set: $0, into: parentID) }
        guard !validSets.isEmpty || !smartIDs.isEmpty else { return }
        let movingKeys = items.compactMap { item -> String? in
            switch item {
            case .set(let id) where validSets.contains(id): "set.\(id)"
            case .smartSet(let id) where smartIDs.contains(id): "smartset.\(id)"
            default: nil
            }
        }
        var updated = data
        updated.moveSets(validSets, to: parentID)
        updated.moveSmartSets(smartIDs, to: parentID)
        if let parentID {
            updated.sidebar.collapsed.remove("set.\(parentID)")
            for ancestor in updated.ancestorIDs(ofSet: parentID) {
                updated.sidebar.collapsed.remove("set.\(ancestor)")
            }
        }
        let targetList = parentID.map { "sets.\($0)" } ?? SidebarSection.sets.rawValue
        for list in updated.sidebar.order.keys where list == SidebarSection.sets.rawValue || list.hasPrefix("sets.") {
            updated.sidebar.order[list]?.removeAll { movingKeys.contains($0) }
        }
        let currentSiblings = orderedFolderChildKeys(of: parentID, in: updated).filter { !movingKeys.contains($0) }
        updated.sidebar.setOrder(currentSiblings + movingKeys, of: targetList)
        data = updated
    }

    func canDropFolderItems(_ items: [SidebarItem], onto target: SidebarItem?) -> Bool {
        let parentID: UUID?
        switch target {
        case nil: parentID = nil
        case .set(let id): parentID = id
        default: return false
        }
        var anyChanges = false
        for item in items {
            switch item {
            case .set(let id):
                guard let set = data.sets.first(where: { $0.id == id }), data.canMove(set: id, into: parentID) else { return false }
                if set.parentID != parentID { anyChanges = true }
            case .smartSet(let id):
                guard let smart = data.smartSets.first(where: { $0.id == id }) else { return false }
                if smart.parentID != parentID { anyChanges = true }
            default:
                return false
            }
        }
        return anyChanges
    }

    private func orderedFolderChildKeys(of parentID: UUID?, in data: UserData) -> [String] {
        let keys = data.sets.filter { $0.parentID == parentID }.map { "set.\($0.id)" }
            + data.smartSets.filter { $0.parentID == parentID }.map { "smartset.\($0.id)" }
        let list = parentID.map { "sets.\($0)" } ?? SidebarSection.sets.rawValue
        return data.sidebar.ordered(keys, in: list) { $0 }
    }

    func moveFolderRows(_ source: IndexSet, to destination: Int, shown: [SidebarRow]) {
        let rawMoving = source.map { shown[$0] }
        let rawSetIDs = Set(rawMoving.compactMap { if case .set(let id) = $0.item { id } else { nil } })
        let moving = rawMoving.filter { row in
            switch row.item {
            case .set(let id):
                return data.ancestorIDs(ofSet: id).allSatisfy { !rawSetIDs.contains($0) }
            case .smartSet(let id):
                guard let parent = data.smartSets.first(where: { $0.id == id })?.parentID else { return true }
                return !rawSetIDs.contains(parent) && data.ancestorIDs(ofSet: parent).allSatisfy { !rawSetIDs.contains($0) }
            default:
                return false
            }
        }
        guard !moving.isEmpty else { return }
        let targetRow = destination < shown.count ? shown[destination] : nil
        let targetParentID: UUID? = targetRow?.parentKey.flatMap { key in
            key.hasPrefix("set.") ? UUID(uuidString: String(key.dropFirst(4))) : nil
        }
        let movingKeys = moving.map(\.key)
        let movingSetIDs = Set(moving.compactMap { if case .set(let id) = $0.item { id } else { nil } })
        let movingSmartIDs = Set(moving.compactMap { if case .smartSet(let id) = $0.item { id } else { nil } })
        guard movingSetIDs.allSatisfy({ data.canMove(set: $0, into: targetParentID) }) else { return }
        var updated = data
        updated.moveSets(movingSetIDs, to: targetParentID)
        updated.moveSmartSets(movingSmartIDs, to: targetParentID)
        for list in updated.sidebar.order.keys where list == SidebarSection.sets.rawValue || list.hasPrefix("sets.") {
            updated.sidebar.order[list]?.removeAll { movingKeys.contains($0) }
        }
        let targetList = targetParentID.map { "sets.\($0)" } ?? SidebarSection.sets.rawValue
        var siblings = orderedFolderChildKeys(of: targetParentID, in: updated).filter { !movingKeys.contains($0) }
        if let targetKey = targetRow?.key, let insertAt = siblings.firstIndex(of: targetKey) {
            siblings.insert(contentsOf: movingKeys, at: insertAt)
        } else {
            siblings.append(contentsOf: movingKeys)
        }
        updated.sidebar.setOrder(siblings, of: targetList)
        data = updated
    }

    func moveLocationRows(_ source: IndexSet, to destination: Int, shown: [SidebarRow]) {
        let topShown = shown.filter { $0.depth == 0 }
        let movingKeys = Set(source.compactMap { shown[$0].depth == 0 ? shown[$0].key : nil })
        guard !movingKeys.isEmpty else { return }
        let topSource = IndexSet(topShown.indices.filter { movingKeys.contains(topShown[$0].key) })
        let topDestination = shown.prefix(destination).count { $0.depth == 0 }
        let allTop = topLevelLocationRows.map(\.key)
        data.sidebar.move(topSource, to: topDestination, shown: topShown.map(\.key), all: allTop, in: SidebarSection.folders.rawValue)
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
        guard case .set(let id) = item else { return families.flatMap(\.faces) }
        return families.flatMap { family in family.faces.filter { data.contains(style: $0.face.postScriptName, of: family.id, inSetSubtree: id) } }
    }

    func families(in item: SidebarItem) -> [Family] {
        let test = filter(for: item)
        let families = library.families.filter { data.lists($0) && test($0) }
        switch item {
        case .folder, .subfolder:
            let only = onlyIn(item)
            return families.map { only[$0.id] ?? $0 }
        default:
            return families
        }
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
            if let parentID = smartSet.parentID { data.sidebar.collapsed.remove("set.\(parentID)") }
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
        var data = data
        for family in library.families where family.manufacturer.map({ data.foundryRenames[$0] ?? $0 }) == old {
            if let raw = family.manufacturer { data.foundryRenames[raw] = trimmed }
        }
        for (family, foundry) in data.foundryOverrides where foundry == old { data.foundryOverrides[family] = trimmed }
        for set in data.smartSets.indices {
            for rule in data.smartSets[set].rules.indices where data.smartSets[set].rules[rule].field == .foundry
                && data.smartSets[set].rules[rule].comparison != .contains && data.smartSets[set].rules[rule].value == old {
                data.smartSets[set].rules[rule].value = trimmed
            }
        }
        data.sidebar.rename("foundry.\(old)", to: "foundry.\(trimmed)")
        self.data = data
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
            var whole: [Family] = [], inWhole = Set<String>()
            for drag in drags {
                let dragged = drag.families.compactMap { family($0) }
                if let style = drag.style, let family = dragged.first, let face = family.faces.first(where: { $0.face.postScriptName == style }) {
                    setMembership(true, for: face, of: family, in: id)
                } else {
                    whole += dragged.filter { inWhole.insert($0.id).inserted }
                }
            }
            if !whole.isEmpty { setMembership(true, for: whole, in: id) }
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
        switch section {
        case .folders: return locationRows(expandedOnly: true)
        case .sets: return folderRows(expandedOnly: true)
        case .characterSets: return unorderedRows(for: section)
        default: return data.sidebar.ordered(unorderedRows(for: section), in: section.rawValue, key: \.key)
        }
    }

    func allRows(for section: SidebarSection) -> [SidebarRow] {
        switch section {
        case .folders: return locationRows(expandedOnly: false)
        case .sets: return folderRows(expandedOnly: false)
        default: return rows(for: section)
        }
    }

    var topLevelLocationRows: [SidebarRow] {
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
        let rows = folders.map { folder -> SidebarRow in
            let icon = folder.id == WatchedFolder.addedFilesID ? "doc"
                : library.unavailableFolders[folder.id] != nil ? "questionmark.folder" : "folder"
            let tree = data.showsSubfolders(for: folder) && library.unavailableFolders[folder.id] == nil ? library.folderTrees[folder.id] : nil
            let hasChildren = !(tree?.isEmpty ?? true)
            return SidebarRow(
                key: "folder.\(folder.id)", title: data.named(folder).displayName, icon: icon, item: .folder(folder.id),
                depth: 0, hasChildren: hasChildren, isExpanded: hasChildren && isLocationExpanded(folder.id), canMove: true
            )
        }
        return data.sidebar.ordered(rows, in: SidebarSection.folders.rawValue, key: \.key)
    }

    private func locationRows(expandedOnly: Bool) -> [SidebarRow] {
        var result: [SidebarRow] = []
        for row in topLevelLocationRows {
            result.append(row)
            guard case .folder(let id) = row.item, row.hasChildren, !expandedOnly || row.isExpanded,
                  let tree = library.folderTrees[id] else { continue }
            func appendSubfolders(_ paths: [String], depth: Int, parentKey: String) {
                for rel in paths {
                    guard let node = tree.nodes[rel] else { continue }
                    let key = "folder.\(id)/\(rel)"
                    let hasChildren = !node.children.isEmpty
                    let expanded = hasChildren && isSubfolderExpanded(id, rel)
                    result.append(SidebarRow(
                        key: key, title: node.name, icon: "folder", item: .subfolder(id, rel),
                        depth: depth, hasChildren: hasChildren, isExpanded: expanded, canMove: false, parentKey: parentKey
                    ))
                    if hasChildren && (!expandedOnly || expanded) {
                        appendSubfolders(node.children, depth: depth + 1, parentKey: key)
                    }
                }
            }
            appendSubfolders(tree.rootChildren, depth: 1, parentKey: row.key)
        }
        return result
    }

    private func folderRows(expandedOnly: Bool) -> [SidebarRow] {
        var result: [SidebarRow] = []
        let setsByParent = Dictionary(grouping: data.sets, by: \.parentID)
        let smartByParent = Dictionary(grouping: data.smartSets, by: \.parentID)
        func appendChildren(of parentID: UUID?, depth: Int) {
            let parentKey = parentID.map { "set.\($0)" }
            let listKey = parentID.map { "sets.\($0)" } ?? SidebarSection.sets.rawValue
            let directSets = (setsByParent[parentID] ?? []).map { set -> SidebarRow in
                let hasChildren = !(setsByParent[set.id]?.isEmpty ?? true) || !(smartByParent[set.id]?.isEmpty ?? true)
                return SidebarRow(
                    key: "set.\(set.id)", title: set.name, icon: set.apps.isEmpty ? "folder" : "app.badge.checkmark", item: .set(set.id),
                    depth: depth, hasChildren: hasChildren, isExpanded: hasChildren && isSetExpanded(set.id), canMove: true, parentKey: parentKey
                )
            }
            let directSmart = (smartByParent[parentID] ?? []).map { smart in
                SidebarRow(
                    key: "smartset.\(smart.id)", title: smart.name, icon: "gearshape", item: .smartSet(smart.id),
                    depth: depth, hasChildren: false, isExpanded: false, canMove: true, parentKey: parentKey
                )
            }
            let ordered = data.sidebar.ordered(directSets + directSmart, in: listKey, key: \.key)
            for row in ordered {
                result.append(row)
                if case .set(let id) = row.item, row.hasChildren, !expandedOnly || row.isExpanded {
                    appendChildren(of: id, depth: depth + 1)
                }
            }
        }
        appendChildren(of: nil, depth: 0)
        return result
    }

    func orderedSetRows(parentID: UUID? = nil, depth: Int = 0) -> [(set: FontSet, depth: Int, children: [FontSet])] {
        let byParent = Dictionary(grouping: data.sets, by: \.parentID)
        let listKey = parentID.map { "sets.\($0)" } ?? SidebarSection.sets.rawValue
        let sets = data.sidebar.ordered(byParent[parentID] ?? [], in: listKey) { "set.\($0.id)" }
        return sets.map { set in
            let kids = data.sidebar.ordered(byParent[set.id] ?? [], in: "sets.\(set.id)") { "set.\($0.id)" }
            return (set, depth, kids)
        }
    }

    func isLocationExpanded(_ id: UUID) -> Bool { data.sidebar.expanded.contains("folder.\(id)") }

    func setLocationExpanded(_ id: UUID, _ expanded: Bool) {
        if expanded { data.sidebar.expanded.insert("folder.\(id)") } else { data.sidebar.expanded.remove("folder.\(id)") }
    }

    func isSubfolderExpanded(_ id: UUID, _ rel: String) -> Bool { data.sidebar.expanded.contains("folder.\(id)/\(rel)") }

    func setSubfolderExpanded(_ id: UUID, _ rel: String, _ expanded: Bool) {
        let key = "folder.\(id)/\(rel)"
        if expanded { data.sidebar.expanded.insert(key) } else { data.sidebar.expanded.remove(key) }
    }

    func expandAncestors(of id: UUID, relativePath: String) {
        data.sidebar.expanded.insert("folder.\(id)")
        for ancestor in FolderTree.ancestors(of: relativePath) {
            data.sidebar.expanded.insert("folder.\(id)/\(ancestor)")
        }
    }

    func isSetExpanded(_ id: UUID) -> Bool { !data.sidebar.collapsed.contains("set.\(id)") }

    func setSetExpanded(_ id: UUID, _ expanded: Bool) {
        if expanded { data.sidebar.collapsed.remove("set.\(id)") } else { data.sidebar.collapsed.insert("set.\(id)") }
    }

    func toggleExpanded(for row: SidebarRow) {
        guard row.hasChildren else { return }
        switch row.item {
        case .folder(let id): setLocationExpanded(id, !row.isExpanded)
        case .subfolder(let id, let rel): setSubfolderExpanded(id, rel, !row.isExpanded)
        case .set(let id): setSetExpanded(id, !row.isExpanded)
        default: break
        }
    }

    private func unorderedRows(for section: SidebarSection) -> [SidebarRow] {
        switch section {
        case .folders:
            return topLevelLocationRows
        case .sets:
            return folderRows(expandedOnly: false)
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
        if case .subfolder(_, let rel) = item { return (rel as NSString).lastPathComponent }
        for section in SidebarSection.allCases {
            if let row = allRows(for: section).first(where: { $0.item == item }) { return row.title }
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
        let keptOn = locations.isEmpty ? [] : removingFolders(Set(locations.compactMap { if case .folder(let id) = $0.item { id } else { nil } }))
        let sets = Set(deleted.compactMap { if case .set(let id) = $0.item { id } else { nil } })
        if !sets.isEmpty { deleteSets(sets, undoable: false) }
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
            if !locations.isEmpty {
                self.rescan()
                self.turnOnAgain(keptOn)
            }
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
        case .folder, .subfolder: SidebarSection.folders.rawValue
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
        if let section = SidebarSection(rawValue: list) { return allRows(for: section) }
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
        if case .subfolder(let id, _) = item {
            return isVisible(SidebarSection.folders.key) && isVisible("folder.\(id)")
        }
        for section in SidebarSection.allCases {
            if let row = allRows(for: section).first(where: { $0.item == item }) {
                if case .set(let id) = item {
                    return isVisible(section.key) && isVisible(row.key) && data.ancestorIDs(ofSet: id).allSatisfy { isVisible("set.\($0)") }
                }
                if case .smartSet(let id) = item, let parent = data.smartSets.first(where: { $0.id == id })?.parentID {
                    return isVisible(section.key) && isVisible(row.key) && isVisible("set.\(parent)") && data.ancestorIDs(ofSet: parent).allSatisfy { isVisible("set.\($0)") }
                }
                return isVisible(section.key) && isVisible(row.key)
            }
        }
        return true
    }

    func isExpanded(_ section: SidebarSection) -> Bool { !data.sidebar.collapsed.contains(section.rawValue) }

    func setExpanded(_ section: SidebarSection, _ expanded: Bool) {
        if expanded { data.sidebar.collapsed.remove(section.rawValue) } else { data.sidebar.collapsed.insert(section.rawValue) }
    }

    // MARK: Prompts

    func prompt(_ title: String, text: String = "", confirm: String, requiresText: Bool = false, action: @escaping (String) -> Void) {
        ask { $0.textPrompt = TextPrompt(title: title, initialText: text, confirmTitle: confirm, requiresText: requiresText, action: action) }
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
