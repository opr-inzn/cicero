import AppKit
import CiceroCore
import UniformTypeIdentifiers

struct OpenedFiles {
    var scan: Int
    var paths: Set<String>
    var target: SidebarItem?
    var note: AddNote
}

struct AddNote {
    var message = ""
    var installedAll = false
}

extension AppModel {
    static let fontTypes: [UTType] = FontFormat.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }

    // MARK: Adding

    func presentAddFontsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.fontTypes
        panel.prompt = installsAddedFiles ? "Install" : "Add"
        panel.message = switch data.installMethod {
        case .copy: "Choose font files. They’re copied into \(installPlace) and activated. The originals stay where they are."
        case .move: "Choose font files. They’re moved into \(installPlace) and activated."
        case .inPlace: "Choose font files. They’re listed in your library where they are, without being activated."
        case .ask: "Choose font files. Cicero asks whether to copy them into \(installPlace), move them there or leave them where they are."
        }
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func open(_ urls: [URL], into target: SidebarItem? = nil) {
        if let last = openQueue.batches.indices.last, openQueue.batches[last].target == target {
            openQueue.batches[last].urls += urls
        } else {
            openQueue.batches.append((urls, target))
        }
        openQueue.task?.cancel()
        openQueue.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.openWaitingFiles()
        }
    }

    var targetForAddedFiles: SidebarItem? {
        if openFamilyID == nil, similarFamilyID == nil, documentList == nil, externalSimilar == nil, selection?.isVault == true {
            return selectedItems.count == 1 ? selection : .vault
        }
        guard openFamilyID == nil, similarFamilyID == nil, documentList == nil, externalSimilar == nil, selectedItems.count == 1, let selection else { return nil }
        switch selection {
        case .set(let id): return data.sets.contains { $0.id == id } ? selection : nil
        case .tag(let name): return data.tags.contains(name) ? selection : nil
        case .folder(let id): return id == WatchedFolder.addedFilesID || dropLocation(id) != nil ? selection : nil
        case .vault, .vaultOwner: return selection
        default: return nil
        }
    }

    func dropLocation(_ id: UUID) -> DropLocation? {
        let candidates = id == WatchedFolder.adobeAppsID ? WatchedFolder.appFontFolders() : data.folders.filter { $0.id == id }
        guard library.unavailableFolders[id] == nil,
              let folder = candidates.first(where: { FileManager.default.isWritableFile(atPath: $0.path) }) else { return nil }
        return DropLocation(id: id, name: folderName(id), folder: folder.url, isActive: folder.isActive, app: folder.appName)
    }

    static var pastedFiles: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    func openOnSidebar(_ urls: [URL]) {
        let urls = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !urls.isEmpty else { return }
        Task {
            let (folders, rest) = await Task.detached(priority: .userInitiated) {
                var folders: [URL] = []
                var rest: [URL] = []
                for url in urls {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    if values?.isDirectory == true && values?.isPackage != true {
                        folders.append(url)
                    } else {
                        rest.append(url)
                    }
                }
                return (folders, rest)
            }.value
            if !folders.isEmpty {
                addFolders(folders)
                if rest.isEmpty, folders.count == 1, let folder = data.folders.first(where: { $0.path == folders[0].path }) { selection = .folder(folder.id) }
            }
            if !rest.isEmpty { open(rest) }
        }
    }

    func pasteFiles() {
        let urls = Self.pastedFiles
        if !urls.isEmpty { open(urls, into: targetForAddedFiles) }
    }

    func openWaitingFiles() {
        guard started, !openQueue.batches.isEmpty, hasScanned || !library.families.isEmpty else { return }
        let batches = openQueue.batches
        openQueue.batches = []
        for batch in batches { open(batch.urls, target: batch.target) }
    }

    private func open(_ urls: [URL], target: SidebarItem?) {
        if let target, target.isVault {
            if let id = openLicenseID, let license = vaultLicenses.first(where: { $0.id == id }) { return addFiles(urls, to: license) }
            return addToVault(urls, owner: target.vaultOwner)
        }
        let vault = self.vault
        let fileURLs = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        let imports = importFiles(among: fileURLs)
        let outside = fileURLs.filter { !imports.contains($0) && !vault.contains($0.path) }
        guard !outside.isEmpty || fileURLs.count == imports.count else {
            return showToast("Fonts in the Vault stay there. Copy them out in the Finder to add them")
        }
        let candidates = outside
        let skipped = vault.skippedPrefixes
        let readFolders = readFolders
        let totalCount = urls.count
        Task {
            let classified = await Task.detached(priority: .userInitiated) { () -> (folders: [URL], files: [String], seen: Set<String>, documents: [URL], webFonts: [URL]) in
                let realFolders = readFolders.compactMap { folder in Self.realPath(folder).map { (folder, $0) } }
                let lookup = PathLookup(addedFiles: [], libraryPaths: [], folders: readFolders, realFolders: realFolders)
                let fm = FileManager.default
                var folders: [URL] = []
                var files: [String] = []
                var seen = Set<String>()
                var documents: [URL] = []
                // Web fonts are left out: Adobe apps don't see them in a Fonts folder, and set blank text in them used in place.
                var webFonts: [URL] = []
                for url in candidates {
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                    let pathExtension = url.pathExtension.lowercased()
                    if isDirectory.boolValue {
                        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
                        if !isPackage { folders.append(url) }
                    } else if FontFormat.fileExtensions.contains(pathExtension) {
                        let path = lookup.libraryPath(of: url.path)
                        if seen.insert(path).inserted { files.append(path) }
                    } else if DocumentFonts.fileExtensions.contains(pathExtension) {
                        documents.append(url)
                    } else if ["woff", "woff2"].contains(pathExtension) {
                        webFonts.append(url)
                    }
                }
                return (folders, files, seen, documents, webFonts)
            }.value
            let folders = classified.folders
            let files = classified.files
            let seenFiles = classified.seen
            let documents = classified.documents
            let webFonts = classified.webFonts
            if let document = documents.first { findFonts(in: document) }
            guard !folders.isEmpty || !files.isEmpty else {
                guard documents.isEmpty, imports.isEmpty else { return }
                if !webFonts.isEmpty {
                    let kinds = Set(webFonts.map { $0.pathExtension.uppercased() }).sorted().listed()
                    return showToast("Cicero can’t use web fonts like \(kinds)", action: ToastAction(title: "Save in Vault") { $0.addToVault(webFonts) })
                }
                return showToast(totalCount == 1 ? "That isn’t a font Cicero can read" : "Those aren’t fonts Cicero can read")
            }
            var method: InstallMethod?
            var location: DropLocation?
            if case .folder(let id) = target {
                if id == WatchedFolder.addedFilesID { method = .inPlace } else { location = dropLocation(id) }
            }
            let opened = folders.filter { WatchedFolder.detectAppName(forPath: $0.path) == nil }
            guard (method ?? data.installMethod) != .inPlace, !opened.isEmpty else {
                return add(files, folders: folders, method: method, location: location, target: target)
            }
            var expandedFiles = files
            var seen = seenFiles
            let found = await Task.detached(priority: .userInitiated) { opened.flatMap { LibraryScanner.fontFiles(in: $0, skipping: skipped) } }.value
            let lookup = pathLookup()
            for raw in found {
                let path = lookup.libraryPath(of: raw)
                if seen.insert(path).inserted { expandedFiles.append(path) }
            }
            guard !expandedFiles.isEmpty || opened.count < folders.count else {
                return showToast(opened.count == 1 ? "There are no fonts Cicero can read in “\(opened[0].lastPathComponent)”" : "There are no fonts Cicero can read in those folders")
            }
            add(expandedFiles, folders: folders.filter { !opened.contains($0) }, method: method, location: location, target: target)
        }
    }

    private func add(_ files: [String], folders: [URL], method: InstallMethod?, location: DropLocation?, target: SidebarItem?) {
        if !folders.isEmpty {
            let before = Set(data.folders.map(\.id))
            addFolders(folders)
            let added = data.folders.filter { !before.contains($0.id) }
            if files.isEmpty, added.count == 1 { selection = .folder(added[0].id) }
        }
        guard !files.isEmpty else { return }
        addCheckingDuplicates(files, method: method, into: location) { model, paths, note in
            model.awaitingScan.append(OpenedFiles(scan: model.rescan(), paths: paths, target: target, note: note))
        }
    }

    func addCheckingDuplicates(_ paths: [String], method: InstallMethod? = nil, into location: DropLocation? = nil,
                               then: @escaping (AppModel, Set<String>, AddNote) -> Void) {
        let lookup = pathLookup()
        let new = paths.filter { !lookup.isListed($0) }
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
                return ask { $0.duplicatePrompt = prompt }
            }
            if handling == .replace, duplicates.contains(where: warnsBeforeReplacing) {
                return ask { $0.replacePrompt = prompt }
            }
            addFontFiles(paths, resolving: duplicates, choices: Dictionary(zip(duplicates.map(\.id), chosen.compactMap(\.self)), uniquingKeysWith: { first, _ in first }),
                         method: method, into: location, then: then)
        }
    }

    var openAppsKeepingFonts: [String] {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [("com.adobe.InDesign", "InDesign"), ("com.adobe.illustrator", "Illustrator"), ("com.adobe.Photoshop", "Photoshop")]
            .filter { open.contains($0.0) }.map(\.1)
    }

    func replaceEverywhere(_ prompt: DuplicatePrompt) {
        let choices = Dictionary(prompt.duplicates.map { ($0.id, $0.choice(for: .replace) ?? $0.suggestion) }, uniquingKeysWith: { first, _ in first })
        addFontFiles(prompt.paths, resolving: prompt.duplicates, choices: choices, method: prompt.method, into: prompt.location,
                     then: prompt.then)
    }

    var installsAddedFiles: Bool { data.installMethod == .copy || data.installMethod == .move }

    var installPlace: String { data.installsIntoFontLibrary ? "Cicero’s Library" : "your Fonts folder" }

    func addFontFiles(_ paths: [String], resolving duplicates: [AddedDuplicate] = [], choices: [String: DuplicateChoice] = [:],
                      method: InstallMethod? = nil, into location: DropLocation? = nil, then: ((AppModel, Set<String>, AddNote) -> Void)? = nil,
                      askedAboutOpenApps: Bool = false) {
        let skipped = duplicates.filter { choices[$0.id] == .skip }
        let replacements = duplicates.filter { choices[$0.id] == .replace && $0.canReplace }.flatMap(\.replacements)
        if !replacements.isEmpty, !askedAboutOpenApps, case let apps = openAppsKeepingFonts, !apps.isEmpty {
            let prompt = OpenAppsReplacePrompt(apps: apps) { model in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, into: location, then: then,
                                   askedAboutOpenApps: true)
            }
            return ask { $0.openAppsReplacePrompt = prompt }
        }
        let left = Set(skipped.flatMap(\.paths)).subtracting(duplicates.filter { choices[$0.id] != .skip }.flatMap(\.paths))
            .union(replacements.map(\.added))
        let lookup = pathLookup()
        let offAdded = lookup.movableFiles(among: paths).filter { !library.activePaths.contains($0) }
        if method == nil, data.installMethod == .ask,
           case let asked = paths.filter({ !left.contains($0) && (!lookup.isListed($0) || offAdded.contains($0)) }), !asked.isEmpty {
            let prompt = InstallPrompt(files: asked, offersMove: asked.contains { !lookup.isInReadFolder($0) }, location: location) { model, method in
                model.addFontFiles(paths, resolving: duplicates, choices: choices, method: method, into: location, then: then,
                                   askedAboutOpenApps: true)
            }
            return offerInstall(prompt)
        }
        let method = method ?? data.installMethod
        let installs = method == .copy || method == .move
        let paths = paths.filter { !left.contains($0) }
        let existing = Set(skipped.flatMap { $0.styles.map(\.face.path) })
        let skipNote = Self.skipNote(skipped)
        let movable = lookup.movableFiles(among: paths)
        let installing = !installs ? [] : paths.filter { path in
            !lookup.isListed(path) || movable.contains(path) && !library.activePaths.contains(path)
        }
        let moving = method == .move
        let new = installs ? [] : paths.filter { !lookup.isListed($0) }
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
            model.data.fontFiles.removeAll { copies[$0] != nil }
            model.data.forgetInstalledAddedFiles()
            let message = (messages + [skipNote]).filter { !$0.isEmpty }.joined(separator: ". ")
            let found = shown.union(copies.values).union(existing).union(replaced)
            guard let then, !found.isEmpty else {
                model.showToast(message)
                model.rescan()
                return
            }
            then(model, found, AddNote(message: message, installedAll: location == nil && !installing.isEmpty && !failed
                                                                       && replacements.isEmpty && skipNote.isEmpty))
        }
    }

    private func offerInstall(_ prompt: InstallPrompt) {
        ask(overActivationSheets: true) { model in
            guard let shown = model.installPrompt else { return model.installPrompt = prompt }
            model.installPrompt = InstallPrompt(files: shown.files + prompt.files.filter { !shown.files.contains($0) },
                                                offersMove: shown.offersMove || prompt.offersMove,
                                                location: shown.location == prompt.location ? shown.location : nil) { model, method in
                shown.add(model, method)
                prompt.add(model, method)
            }
        }
    }

    func renameBackLater(_ pending: [String: String]) {
        let engine = engine
        engine.noteRenamesLater(pending)
        Task { [weak self] in
            let remembered = await engine.waitUntilForgotten(Array(pending.values), timeout: engine.renameBackWait, every: .seconds(1))
            let ready = pending.filter { !remembered.contains($0.value) }
            guard !ready.isEmpty, let self else { return }
            self.enqueue { model in
                let result = await model.engine.renameBack(ready, records: model.data.records)
                model.engine.forgetRenamesLater(result.settled)
                if !result.renamed.isEmpty { model.rescan() }
            }
        }
    }

    private static func skipNote(_ skipped: [AddedDuplicate]) -> String {
        guard let names = FontNames.describe(families: skipped.map(\.family)) else { return "" }
        return skipped.count > 2 ? "Skipped \(names) already in your library" : "Skipped \(names), already in your library"
    }

    nonisolated private struct PathLookup: Sendable {
        let addedFiles: Set<String>
        let libraryPaths: Set<String>
        let folders: [String]
        let realFolders: [(folder: String, real: String)]

        func libraryPath(of path: String) -> String {
            guard !folders.contains(where: { path.hasPrefix($0 + "/") }), let real = AppModel.realPath(path) else { return path }
            for (folder, realFolder) in realFolders where real.hasPrefix(realFolder + "/") {
                return folder + real.dropFirst(realFolder.count)
            }
            return path
        }

        func isInReadFolder(_ path: String) -> Bool {
            let normalized = libraryPath(of: path)
            return folders.contains { normalized.hasPrefix($0 + "/") }
        }

        func isListed(_ path: String) -> Bool {
            addedFiles.contains(path) || libraryPaths.contains(path) || isInReadFolder(path)
        }

        func movableFiles(among paths: [String]) -> Set<String> {
            Set(paths.filter { addedFiles.contains($0) && !isInReadFolder($0) })
        }
    }

    private func pathLookup() -> PathLookup {
        let folders = readFolders
        let realFolders = folders.compactMap { folder in Self.realPath(folder).map { (folder, $0) } }
        var libraryPaths = Set<String>()
        for family in library.families {
            for face in family.faces {
                libraryPaths.insert(face.face.path)
                libraryPaths.formUnion(face.otherCopies)
            }
        }
        return PathLookup(addedFiles: Set(data.fontFiles), libraryPaths: libraryPaths, folders: folders, realFolders: realFolders)
    }

    private var readFolders: [String] {
        [locations.userFonts.path, locations.allUsersFonts.path] + locations.allInactiveFolders.map(\.path) + data.scannedFolders().map(\.path)
    }

    func libraryPath(of path: String, folders: [String]) -> String {
        guard !folders.contains(where: { path.hasPrefix($0 + "/") }), let real = Self.realPath(path) else { return path }
        for folder in folders {
            guard let realFolder = Self.realPath(folder), real.hasPrefix(realFolder + "/") else { continue }
            return folder + real.dropFirst(realFolder.count)
        }
        return path
    }

    nonisolated private static func realPath(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    func movableFiles(among paths: [String]) -> Set<String> {
        pathLookup().movableFiles(among: paths)
    }

    func showOpenedFiles(after id: Int) {
        let ready = awaitingScan.filter { $0.scan <= id }
        awaitingScan.removeAll { $0.scan <= id }
        for opened in ready { showOpenedFiles(opened) }
    }

    private func showOpenedFiles(_ opened: OpenedFiles) {
        let paths = opened.paths
        let found = library.families.filter { family in
            family.faces.contains { paths.contains($0.face.path) || $0.otherCopies.contains(where: paths.contains) }
        }
        let say = { (more: String) in
            let message = [opened.note.message, more].filter { !$0.isEmpty }.joined(separator: ". ")
            if !message.isEmpty { self.showToast(message) }
        }
        guard !found.isEmpty else {
            let name = paths.count == 1 ? URL(fileURLWithPath: paths.first!).lastPathComponent : nil
            return say(name.map { "Couldn’t read “\($0)”" } ?? "Couldn’t read these fonts")
        }
        let families = found.filter(data.lists)
        guard !families.isEmpty else {
            let singular = found.count == 1
            return say(found[0].state == .system
                ? (singular ? "That font comes with macOS, and system fonts are hidden (Preferences → General)"
                            : "Those fonts come with macOS, and system fonts are hidden (Preferences → General)")
                : (singular ? "That font is from Adobe Fonts, which are hidden (Preferences → General)"
                            : "Those fonts are from Adobe Fonts, which are hidden (Preferences → General)"))
        }
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

    func canRemoveFromLibrary(_ families: [Family]) -> Bool {
        let added = Set(data.fontFiles)
        return !families.isEmpty && families.allSatisfy { $0.faces.allSatisfy { added.contains($0.face.path) } }
    }

    func removeFromLibrary(_ families: [Family]) {
        let paths = Set(families.flatMap(\.faces).flatMap { [$0.face.path] + $0.otherCopies })
        data.fontFiles.removeAll(where: paths.contains)
        rescan()
    }
}
