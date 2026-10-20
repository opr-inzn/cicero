import AppKit
import CiceroCore

extension AppModel {
    // MARK: Activation

    func activate(_ families: [Family]) {
        activate(families.flatMap(\.faces), title: Self.title(for: families))
    }

    /// Asks how to activate when the install method is Ask, unless every face comes from a folder
    /// an app loads by itself (those are always used where they are). Asks first whether to turn on so many when that's
    /// more than `UserData.manyFamilies` families, unless `confirmed`.
    func activate(_ faces: [LibraryFace], title: String, confirmed: Bool = false) {
        let targets = faces.filter(\.canActivate)
        guard !targets.isEmpty else { return showToast("Already on") }
        if !confirmed, let prompt = manyActivationPrompt(for: targets, title: title, temporarily: false) {
            return manyActivationPrompt = prompt
        }
        let needsChoice = targets.contains { $0.app == nil }
        if data.installMethod == .ask && needsChoice {
            activationPrompt = ActivationPrompt(title: title, faces: targets)
        } else {
            performActivation(targets, method: data.installMethod == .ask ? .inPlace : data.installMethod)
        }
    }

    func performActivation(_ faces: [LibraryFace], method: InstallMethod) {
        let operation = expect(faces, at: .on)
        let movable = movableFiles(among: faces.map(\.face.path))
        enqueue { model in
            let result = await model.engine.activate(faces, method: method, records: model.data.records, movable: movable)
            model.finish(result, operation: operation)
        }
    }

    func activateTemporarily(_ families: [Family]) {
        activateTemporarily(families.flatMap(\.faces))
    }

    /// Until Cicero quits. Asks first when that's many families, unless `confirmed`, like `activate`.
    func activateTemporarily(_ faces: [LibraryFace], confirmed: Bool = false) {
        let targets = faces.filter(\.canActivateTemporarily)
        guard !targets.isEmpty else { return showToast("Already on") }
        if !confirmed, let prompt = manyActivationPrompt(for: targets, title: "", temporarily: true) {
            return manyActivationPrompt = prompt
        }
        let operation = expect(targets, at: .on)
        enqueue { model in
            let result = await model.engine.activateTemporarily(targets, records: model.data.records)
            model.finish(result, operation: operation)
        }
    }

    /// A question for turning on more than `UserData.manyFamilies` families at once, while the user wants one.
    private func manyActivationPrompt(for faces: [LibraryFace], title: String, temporarily: Bool) -> ManyActivationPrompt? {
        guard data.asksBeforeActivatingMany else { return nil }
        let families = Set(faces.map(\.face.familyName)).count
        guard families > UserData.manyFamilies else { return nil }
        return ManyActivationPrompt(title: title, faces: faces, families: families, temporarily: temporarily)
    }

    /// Goes on with an activation the user agreed to.
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

    func deactivate(_ faces: [LibraryFace]) {
        let targets = faces.filter(\.canDeactivate)
        guard !targets.isEmpty else {
            return showToast(faces.contains { $0.state.isActive } ? "These fonts are managed by macOS or another app" : "Nothing to deactivate")
        }
        performDeactivation(targets)
    }

    func performDeactivation(_ faces: [LibraryFace]) {
        let operation = expect(faces, at: .off)
        enqueue { model in
            let result = await model.engine.deactivate(faces, records: model.data.records)
            model.finish(result, operation: operation)
        }
    }

    /// On ↔ off; fonts an app loads from its own folder go from on in that app to on everywhere, then
    /// off everywhere, then back. A switch already moving waits for its operation.
    func toggle(_ family: Family) {
        guard expectedFamilyPositions[family.id] == nil else { return }
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

    /// The engine has waited for macOS, so a scan now sees what the operation did.
    func finish(_ result: ActivationResult, operation: Int? = nil) {
        data.records = result.records
        forgetInstalledAddedFiles()
        showToast(result.message)
        let scan = rescan()
        if let operation { settle(operation, after: scan) }
    }

    static func title(for families: [Family]) -> String {
        families.count == 1 ? families[0].name : "\(families.count) families"
    }

    // MARK: Copies

    /// The places these styles can be used from, when some are in more than one, like each client's folder
    /// (see `CopyChooser`).
    func copySources(of styles: [LibraryFace]) -> [CopySource] {
        CopyChooser.sources(of: styles, folders: data.namedFolders, records: data.records, locations: locations)
    }

    /// Uses a place's copies of the styles it has and turns off the other copies of them Cicero turned on.
    /// Asks first when that turns off other styles too, and how to activate when the install method is Ask.
    func useCopies(from source: CopySource, title: String) {
        let plan = CopyChooser.plan(source, records: data.records, library: library)
        guard !plan.isEmpty else { return showToast("Already using the copies from \(source.name)") }
        let request = CopySwitchRequest(source: source.name, title: title, plan: plan)
        if plan.alsoTurnsOff.isEmpty {
            confirmCopySwitch(request)
        } else {
            copySwitchPrompt = request
        }
    }

    func confirmCopySwitch(_ request: CopySwitchRequest) {
        let targets = request.plan.switches.compactMap(\.target)
        if data.installMethod == .ask && !targets.isEmpty {
            activationPrompt = ActivationPrompt(title: request.title, faces: targets, switching: request)
        } else {
            performCopySwitch(request, method: data.installMethod == .ask ? .inPlace : data.installMethod)
        }
    }

    func performCopySwitch(_ request: CopySwitchRequest, method: InstallMethod) {
        let operation = expect(request.plan.styles, at: .on)
        enqueue { model in
            var result = await model.engine.switchCopies(request.plan.switches, method: method, records: model.data.records)
            if result.failed.isEmpty {
                result.message = "Using the copies from \(request.source)"
                    + (request.plan.leavesOtherCopiesOn ? ". Another copy Cicero didn’t turn on is still on, so apps may use that one" : "")
            }
            model.finish(result, operation: operation)
        }
    }

    // MARK: Font Library

    /// The fonts Cicero installed right in ~/Library/Fonts while it installs into the Font Library, with the family each
    /// file is in, for its folder there (see `ActivationEngine.misplacedCopies`).
    func misplacedInstalledFonts() -> (paths: [String], families: [String: String]) {
        let paths = engine.misplacedCopies(in: data.records)
        guard !paths.isEmpty else { return ([], [:]) }
        let wanted = Set(paths)
        var families: [String: String] = [:]
        for family in library.families {
            for face in family.faces {
                for path in [face.face.path] + face.otherCopies where wanted.contains(path) && families[path] == nil {
                    families[path] = family.id
                }
            }
        }
        return (paths, families)
    }

    /// Moves the fonts Cicero installed right in ~/Library/Fonts into the Font Library (see `misplacedInstalledFonts`).
    func moveInstalledFonts() {
        let (paths, families) = misplacedInstalledFonts()
        guard !paths.isEmpty else { return }
        enqueue { model in
            let result = await model.engine.moveInstalledCopies(paths, families: families, records: model.data.records)
            model.finish(result)
        }
    }

    /// Asks for an empty folder and moves the Font Library there, with its fonts, their registrations and the records;
    /// a folder it can't go into is refused, saying why (see `ActivationEngine.refusal`).
    func changeFontLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose an empty folder for Cicero’s Font Library, or make a new one. Its fonts move there."
        panel.directoryURL = data.fontLibrary?.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        if let reason = ActivationEngine.refusal(forFontLibraryAt: url, current: data.fontLibrary?.url, folders: data.scannedFolders(), locations: locations) {
            let alert = NSAlert()
            alert.messageText = "The Font Library can’t go into “\(url.lastPathComponent)”."
            alert.informativeText = reason
            alert.runModal()
            return
        }
        enqueue { model in
            let result = await model.engine.moveFontLibrary(to: url, records: model.data.records)
            if result.failed.isEmpty { model.data.fontLibraryPath = url.path }
            model.finish(result)
        }
    }

    // MARK: Trash

    func requestTrash(_ families: [Family]) {
        let title = families.count == 1 ? "“\(families[0].name)”" : "\(families.count) families"
        requestTrash(families.flatMap(\.faces), removing: families.map(\.id), title: title)
    }

    func requestTrash(_ faces: [LibraryFace], removing families: [String], title: String) {
        guard let plan = engine.trashPlan(for: faces, removing: families, in: library, title: title) else {
            return showToast("Fonts that come with macOS or an app can’t be moved to the Trash")
        }
        trashPlan = plan
    }

    func moveToTrash(_ plan: TrashPlan) {
        enqueue { model in
            let result = await model.engine.moveToTrash(plan, records: model.data.records)
            model.data.records = result.records
            if result.failed.isEmpty {
                for name in plan.removedFamilies { model.forget(family: name) }
            }
            model.showToast(result.message)
            model.rescan()
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
        if isInfoPresented && infoTab == .info {
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
            // Adobe's folders come with the Testing switch rather than one by one.
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

    /// Several at once with one rescan, as Settings → Folders removes the selected ones.
    func removeFolders(_ ids: Set<UUID>) {
        turnOffKeptFonts(in: data.folders.filter { ids.contains($0.id) && $0.isActive })
        data.folders.removeAll { ids.contains($0.id) }
        for id in ids {
            data.sidebar.forget("folder.\(id)")
            data.folderNames[id.uuidString] = nil
        }
        deselect { item in ids.contains { item == .folder($0) } }
        rescan()
    }

    /// Why a watched folder's fonts are out of reach, if they are.
    func availability(ofFolder id: UUID) -> FolderAvailability? {
        library.unavailableFolders[id]
    }

    /// Font files in a watched folder (or among the added fonts) that a cloud service keeps online only.
    func onlineOnlyCount(inFolder id: UUID) -> Int {
        library.onlineOnlyFiles[id]?.count ?? 0
    }

    /// Downloads the font files a cloud service keeps online only in a watched folder (or among the added
    /// fonts), so the library lists them. The cloud service may take them off the Mac again later; making the
    /// folder available offline in the Finder keeps them.
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
                showToast(paths.count == 1 ? "Downloaded 1 font file" : "Downloaded \(paths.count.formatted()) font files")
            } else {
                showToast("Couldn’t download \(failed.count.formatted()) of \(paths.count.formatted()) font files. Check the connection and try again")
            }
            rescan()
        }
    }

    /// System Settings at Privacy & Security → Files and Folders, where Cicero can be let into a folder.
    func openFilesAndFoldersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Inactive, Active (Cicero turns on every font in the folder where it is, and keeps new ones on: see
    /// `activateAddedFonts`), or loaded by `app` by itself. Leaving Active turns off what it turned on.
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

    /// The library's fonts whose files are in these folders.
    func faces(in folders: [WatchedFolder]) -> [LibraryFace] {
        let prefixes = folders.map { $0.path + "/" }
        guard !prefixes.isEmpty else { return [] }
        return library.families.flatMap(\.faces).filter { face in prefixes.contains { face.face.path.hasPrefix($0) } }
    }

    /// Turned on where they are, whatever Activate fonts by says: moving or copying them would take them out of
    /// the folder that keeps them on.
    func keepOn(_ faces: [LibraryFace]) {
        let targets = faces.filter(\.canActivate)
        guard !targets.isEmpty else { return }
        performActivation(targets, method: .inPlace)
    }

    /// What Cicero turned on where it is in these folders, as it does for Active ones.
    private func turnOffKeptFonts(in folders: [WatchedFolder]) {
        let targets = faces(in: folders).filter { $0.canDeactivate && data.records.inPlace.contains($0.face.path) }
        guard !targets.isEmpty else { return }
        performDeactivation(targets)
    }

    /// Every added font file there is, for Reveal in Finder on Added Fonts.
    var addedFileURLs: [URL] {
        data.fontFiles.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// The user's folder, or Cicero's Font Library, with the name the user gave it.
    func folder(_ id: UUID) -> WatchedFolder? {
        if id == WatchedFolder.fontLibraryID { return data.fontLibrary.map(data.named) }
        return data.folders.first { $0.id == id }.map(data.named)
    }

    /// What the sidebar calls a folder or one of Cicero's own items (Testing, Adobe Fonts, Added Fonts): the name the
    /// user gave it, else its own.
    func folderName(_ id: UUID) -> String {
        (folder(id) ?? data.named(WatchedFolder(id: id, path: ""))).displayName
    }

    /// Shows a folder under another name; the folder on disk keeps its own. An empty name, or the folder's own, goes
    /// back to that.
    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var own = folder(id) ?? WatchedFolder(id: id, path: "")
        own.customName = nil
        data.folderNames[id.uuidString] = trimmed.isEmpty || trimmed == own.displayName ? nil : trimmed
    }

    // MARK: Sets

    func addSet(named name: String, with families: [Family] = [], styles: [String: [String]] = [:]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.sets.append(FontSet(name: trimmed, families: families.map(\.id), styles: styles))
        data.sidebar.hidden.remove(SidebarSection.sets.key)
    }

    func renameSet(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.sets.firstIndex(where: { $0.id == id }) else { return }
        data.sets[index].name = trimmed
    }

    func deleteSet(_ id: UUID) {
        data.sets.removeAll { $0.id == id }
        data.sidebar.forget("set.\(id)")
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .set && $0.value == id.uuidString }
        }
        deselect { $0 == .set(id) }
    }

    /// Whether the set has the whole family.
    func isMember(_ family: Family, of setID: UUID) -> Bool {
        data.sets.first { $0.id == setID }?.families.contains(family.id) ?? false
    }

    /// Puts the families in the set whole, in place of the styles of them it had, or takes them out with their styles.
    func setMembership(_ member: Bool, for families: [Family], in setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        if member {
            data.sets[index].add(families: families.map(\.id))
        } else {
            data.sets[index].remove(families: Set(families.map(\.id)))
        }
    }

    /// Whether the set has the style, on its own or with its whole family.
    func isMember(_ face: LibraryFace, of family: Family, in setID: UUID) -> Bool {
        data.sets.first { $0.id == setID }?.contains(style: face.face.postScriptName, of: family.id) ?? false
    }

    /// Puts one style of a family in a set, or takes it out; a family the set has whole keeps its other styles.
    func setMembership(_ member: Bool, for face: LibraryFace, of family: Family, in setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        if member {
            data.sets[index].add(style: face.face.postScriptName, of: family.id)
        } else {
            data.sets[index].remove(style: face.face.postScriptName, of: family.id, all: family.faces.map(\.face.postScriptName))
        }
    }

    /// The styles a sidebar row has: a set's own, which can be only some of a family's, else every style of its families.
    func faces(in item: SidebarItem) -> [LibraryFace] {
        let families = families(in: item)
        guard case .set(let id) = item, let set = data.sets.first(where: { $0.id == id }) else { return families.flatMap(\.faces) }
        return families.flatMap { family in family.faces.filter { set.contains(style: $0.face.postScriptName, of: family.id) } }
    }

    /// The families a sidebar row shows, without the search.
    func families(in item: SidebarItem) -> [Family] {
        let test = filter(for: item)
        return library.families.filter { data.lists($0) && test($0) }
    }

    /// Activate Set on a set's or smart set's menu: every font in it, asking how when the install method is Ask.
    func activateFonts(in item: SidebarItem, named name: String) {
        let faces = faces(in: item)
        guard !faces.isEmpty else { return showToast("There are no fonts in “\(name)”") }
        activate(faces, title: "“\(name)”")
    }

    func activateFontsTemporarily(in item: SidebarItem) {
        let faces = faces(in: item)
        guard !faces.isEmpty else { return showToast("Nothing to activate") }
        activateTemporarily(faces)
    }

    func deactivateFonts(in item: SidebarItem) {
        let faces = faces(in: item)
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

    func deleteSmartSet(_ id: UUID) {
        data.smartSets.removeAll { $0.id == id }
        data.sidebar.forget("smartset.\(id)")
        deselect { $0 == .smartSet(id) }
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

    func deleteCharacterSet(_ id: UUID) {
        let setID = "custom.\(id.uuidString)"
        data.customCharacterSets.removeAll { $0.id == id }
        data.sidebar.forget("charset.\(setID)")
        deselect { $0 == .characterSet(setID) }
    }

    // MARK: Drag and drop

    /// Sidebar rows that family names can be dropped onto: sets, tags, foundries and classifications.
    func takesFamilies(_ item: SidebarItem) -> Bool {
        switch item {
        case .set, .tag, .foundry, .classification: true
        default: false
        }
    }

    /// Families, or single styles of them, dropped onto a sidebar row. A set takes a style on its own; a tag, foundry or
    /// classification is the whole family's, and a tag is given along with the ones the family has.
    func handleDrop(_ drags: [FontDrag], on item: SidebarItem) -> Bool {
        var seen = Set<String>()
        let families = drags.compactMap { family($0.family) }.filter { seen.insert($0.id).inserted }
        guard !families.isEmpty else { return false }
        switch item {
        case .set(let id):
            for drag in drags {
                guard let family = family(drag.family) else { continue }
                if let style = drag.style, let face = family.faces.first(where: { $0.face.postScriptName == style }) {
                    setMembership(true, for: face, of: family, in: id)
                } else {
                    setMembership(true, for: [family], in: id)
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

    /// The sections below the library rows. They no longer move, but an order saved when they did is kept
    /// (Reset Order puts them back).
    var sections: [SidebarSection] {
        data.sidebar.ordered(SidebarSection.allCases, in: "sections", key: \.key)
    }

    var libraryRows: [SidebarRow] {
        let rows = [
            SidebarRow(key: "library.all", title: "All Fonts", icon: "books.vertical", item: .all),
            SidebarRow(key: "library.active", title: "Active", icon: "checkmark.circle", item: .active),
            SidebarRow(key: "library.inactive", title: "Inactive", icon: "circle.dashed", item: .inactive),
            // With system fonts off in Settings, they're nowhere, this item included.
            data.showSystemFonts ? SidebarRow(key: "library.system", title: "System Fonts", icon: "apple.logo", item: .system) : nil,
            SidebarRow(key: "library.problems", title: "Problems", icon: "exclamationmark.triangle", item: .problems, badge: problems.count { !$0.kind.isMinor }),
        ].compactMap { $0 }
        return data.sidebar.ordered(rows, in: "library", key: \.key)
    }

    /// A section's rows in the user's order. Character sets are in groups, ordered in `characterSetGroups`.
    func rows(for section: SidebarSection) -> [SidebarRow] {
        let rows = unorderedRows(for: section)
        return section == .characterSets ? rows : data.sidebar.ordered(rows, in: section.rawValue, key: \.key)
    }

    private func unorderedRows(for section: SidebarSection) -> [SidebarRow] {
        switch section {
        case .folders:
            var folders = data.folders
            // Every folder Adobe apps load by themselves is one item.
            if ownFoldersWithFonts.contains(WatchedFolder.adobeAppsID) {
                folders.append(WatchedFolder(id: WatchedFolder.adobeAppsID, path: "", appName: "Adobe"))
            }
            // Adobe Fonts, from Creative Cloud, apart from the fonts the user put in Adobe's folders.
            if ownFoldersWithFonts.contains(WatchedFolder.adobeFontsID) {
                folders.append(WatchedFolder(id: WatchedFolder.adobeFontsID, path: ""))
            }
            if ownFoldersWithFonts.contains(WatchedFolder.addedFilesID) {
                folders.append(WatchedFolder(id: WatchedFolder.addedFilesID, path: ""))
            }
            if ownFoldersWithFonts.contains(WatchedFolder.fontLibraryID), let fontLibrary = data.fontLibrary {
                folders.append(fontLibrary)
            }
            // Never Cicero's Deactivated folder: it only keeps fonts while they're off, and Inactive lists those.
            return folders.map {
                let icon = $0.id == WatchedFolder.addedFilesID ? "doc"
                    : library.unavailableFolders[$0.id] != nil ? "questionmark.folder" : "folder"
                return SidebarRow(key: "folder.\($0.id)", title: data.named($0).displayName, icon: icon, item: .folder($0.id))
            }
        case .sets:
            return data.sets.map { SidebarRow(key: "set.\($0.id)", title: $0.name, icon: $0.apps.isEmpty ? "square.stack" : "app.badge.checkmark", item: .set($0.id)) }
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

    /// The window title for the sidebar selection: with several items, their names.
    var selectionTitle: String {
        let item = selection ?? .all
        if selectedItems.count > 1 {
            return rows(inList: sidebarList(of: item))
                .filter { selectedItems.contains($0.item) && $0.item != .problems }
                .map(\.title).formatted(.list(type: .and))
        }
        if let row = libraryRows.first(where: { $0.item == item }) { return row.title }
        for section in SidebarSection.allCases {
            if let row = rows(for: section).first(where: { $0.item == item }) { return row.title }
        }
        return "Fonts"
    }

    func isVisible(_ key: String) -> Bool { !data.sidebar.hidden.contains(key) }

    func setVisible(_ key: String, _ visible: Bool) {
        if visible { data.sidebar.hidden.remove(key) } else { data.sidebar.hidden.insert(key) }
        if !visible { deselect { !isShown($0) } }
    }

    /// What the sidebar list selects. Several items only within one list (a section, or a group of
    /// character sets), so they can move together: Command-clicking in another list starts over there.
    func selectSidebarItems(_ items: Set<SidebarItem>) {
        let items = sidebarSelection(items, from: selectedItems)
        guard let any = items.first else { selection = nil; return }
        let list = sidebarList(of: any)
        // The one selected before when it's still there, else the first. Problems has no fonts to show,
        // so it's never the one among several.
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

    /// What the list's selection becomes when it goes from `current` to `items`: the items in the list of
    /// the one just added (else of the one selected before), so that several are only ever in one list.
    func sidebarSelection(_ items: Set<SidebarItem>, from current: Set<SidebarItem>) -> Set<SidebarItem> {
        guard !items.isEmpty else { return [] }
        let added = items.subtracting(current)
        let anchor = added.count == 1 ? added.first! : selection.flatMap { items.contains($0) ? $0 : nil } ?? items.first!
        let list = sidebarList(of: anchor)
        return items.filter { sidebarList(of: $0) == list }
    }

    /// Takes items that are gone, or hidden, out of the sidebar selection; All Fonts when none are left.
    func deselect(where remove: (SidebarItem) -> Bool) {
        let kept = selectedItems.filter { !remove($0) }
        guard kept != selectedItems else { return }
        if kept.isEmpty { selection = .all } else { selectSidebarItems(kept) }
    }

    /// The list of the sidebar an item is in, named as in `SidebarPreferences.order`.
    func sidebarList(of item: SidebarItem) -> String {
        switch item {
        case .all, .active, .inactive, .system, .problems: "library"
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

    /// Character sets for the sidebar, in their groups (Latin S–XL, Adobe Latin, Unicode Blocks,
    /// Google Fonts, then the user's own).
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

    func isGroupExpanded(_ id: String) -> Bool { !data.sidebar.collapsed.contains("charsetgroup.\(id)") }

    func setGroupExpanded(_ id: String, _ expanded: Bool) {
        if expanded { data.sidebar.collapsed.remove("charsetgroup.\(id)") } else { data.sidebar.collapsed.insert("charsetgroup.\(id)") }
    }

    func showAllSidebarItems() {
        data.sidebar.hidden.removeAll()
    }

    /// Moves items within one list of the sidebar (see `SidebarPreferences.order`), never into another.
    /// `shown` is what the list shows, `all` the keys of every item it has.
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
        textPrompt = TextPrompt(title: title, initialText: text, confirmTitle: confirm, action: action)
    }

    // MARK: Compare

    func compare(_ families: [Family]) {
        compareEntries = []
        _ = addToCompare(families.map(\.id))
    }

    /// Adds the families that aren't in Compare yet, in the style the preview weight picks.
    func addToCompare(_ names: [String]) -> Bool {
        let new = names.filter { name in family(name) != nil && !compareEntries.contains { $0.familyID == name } }
        for name in new {
            compareEntries.append(CompareEntry(familyID: name, tint: nextCompareTint))
        }
        return !new.isEmpty
    }

    /// The same family again, after it, in its first style not in `shown`: the styles Compare shows it in, those that
    /// follow the preview weight included.
    func compareAnotherStyle(of id: UUID, besides shown: Set<FaceID>) {
        guard let index = compareEntries.firstIndex(where: { $0.id == id }), let family = family(compareEntries[index].familyID) else { return }
        let style = family.faces.first { !shown.contains($0.id) }?.id
        compareEntries.insert(CompareEntry(familyID: family.id, style: style, tint: nextCompareTint), at: index + 1)
    }

    /// nil: the style the preview weight picks.
    func setCompareStyle(_ style: FaceID?, of id: UUID) {
        guard let index = compareEntries.firstIndex(where: { $0.id == id }) else { return }
        compareEntries[index].style = style
    }

    func removeFromCompare(_ id: UUID) {
        compareEntries.removeAll { $0.id == id }
    }

    /// Puts a compared family where another one is, moving the others along.
    func moveInCompare(_ id: UUID, to target: UUID) {
        guard let from = compareEntries.firstIndex(where: { $0.id == id }), let to = compareEntries.firstIndex(where: { $0.id == target }),
              from != to else { return }
        compareEntries.insert(compareEntries.remove(at: from), at: to)
    }

    /// The first tint no compared family has.
    private var nextCompareTint: Int {
        (0...).first { tint in !compareEntries.contains { $0.tint == tint } }!
    }

    // MARK: Font caches

    /// Returns true when macOS's caches were cleared, which is when restarting helps.
    func clearCaches(scopes: [SystemFontCaches.Scope], apps: [AppFontCaches.App]) async -> Bool {
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
        if failures > 0 {
            showToast(failures == 1 ? "Couldn’t move 1 cache item to the Trash" : "Couldn’t move \(failures) cache items to the Trash")
        } else if !trashed.isEmpty && !clearedSystem {
            showToast("Moved the \(trashed.formatted(.list(type: .and))) font caches to the Trash")
        }
        if clearedSystem || !trashed.isEmpty { rebuildFontList() }
        return clearedSystem
    }

    // MARK: Problems

    /// `family` is the family the problem is about, if any: removing files names the others in them.
    func apply(_ fix: ProblemFix, family: String? = nil) {
        switch fix {
        case .reveal(let paths):
            NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
        case .deactivate(let ids):
            // Asks first like any deactivation, for files Cicero didn't install.
            let ids = Set(ids)
            let faces = library.families.flatMap(\.faces).filter { ids.contains($0.id) }
            if !faces.isEmpty { deactivate(faces) }
        case .trash(let paths):
            guard let plan = engine.spareCopiesTrashPlan(paths, families: Set([family].compactMap(\.self)), in: library) else { return }
            trashPlan = plan
        case .forgetInPlace(let path):
            enqueue { model in
                model.data.records = await model.engine.forgetInPlace(path, records: model.data.records)
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
        }
    }

    /// Remove All Extra Copies: every problem's extra copies at once, after asking.
    func trashExtraCopies(of problems: [Problem]) {
        var seen = Set<String>()
        let paths = problems.flatMap(\.extraCopies).filter { seen.insert($0).inserted }
        guard var plan = engine.spareCopiesTrashPlan(paths, families: Set(problems.compactMap(\.family)), in: library) else { return }
        plan.title = plan.paths.count == 1 ? "1 extra copy" : "\(plan.paths.count) extra copies"
        trashPlan = plan
    }
}
