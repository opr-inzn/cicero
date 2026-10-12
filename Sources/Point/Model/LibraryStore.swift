import AppKit
import CoreText
import SwiftUI

enum SidebarSelection: Hashable {
    case all, active, inactive, system, problems
    case folder(UUID)
    case set(UUID)
    case tag(String)
    case foundry(String)
    case classification(FontClassification)
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case folders, sets, tags, foundries, classifications

    var id: String { rawValue }
    var key: String { "section.\(rawValue)" }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .folders: "folder"
        case .sets: "square.stack"
        case .tags: "tag"
        case .foundries: "building.2"
        case .classifications: "textformat"
        }
    }
}

struct SidebarRow: Identifiable, Hashable {
    var key: String
    var title: String
    var icon: String
    var selection: SidebarSelection
    /// A count shown at the trailing edge; zero shows nothing.
    var badge = 0

    var id: String { key }
}

struct ActivationRequest: Identifiable {
    let id = UUID()
    var title: String
    var faces: [LibraryFace]
}

struct DeactivationRequest {
    var faces: [LibraryFace]
    var unmanagedCount: Int
}

struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var initialText: String
    var confirmTitle: String
    var action: (String) -> Void
}

@Observable @MainActor
final class LibraryStore {
    private(set) var families: [FontFamily] = []
    private var familyIndex: [String: Int] = [:]
    private var searchBlobs: [String: String] = [:]
    private(set) var isScanning = false
    private(set) var scanStatus = ""
    private(set) var hasScanned = false
    /// Font files from the last scan that CoreText couldn't read.
    private(set) var unreadableFiles: [String] = []
    /// Every file path macOS currently has active.
    private(set) var activePaths: Set<String> = []
    /// Trouble found in the library (see ProblemFinder); refreshed after each scan.
    var problems: [FontProblem] = []
    /// Families shown by the Compare and Slideshow windows.
    var presentation = PresentationState()

    var data: UserLibraryData

    var sidebarSelection: SidebarSelection? = .all {
        didSet {
            guard oldValue != sidebarSelection else { return }
            selectedFamilyIDs = []
            detailFamilyID = nil
        }
    }
    var selectedFamilyIDs: Set<String> = []
    var detailFamilyID: String? {
        didSet { if oldValue != detailFamilyID { detailFeatures = [] } }
    }
    var searchText = ""
    var isEditingSidebar = false
    var isInspectorPresented = false
    var isConfirmingCacheClear = false
    var inspectorTab: InspectorTab = .info
    /// OpenType features applied to the detail view's previews.
    var detailFeatures: [FeatureSetting] = []

    var pendingActivation: ActivationRequest?
    var pendingDeactivation: DeactivationRequest?
    var textPrompt: TextPrompt?
    var toast: String?

    private var started = false
    private var scanTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var pendingRescan: Task<Void, Never>?
    private var lastScanDate = Date.distantPast
    private var lastScannedPaths: Set<String> = []

    init() {
        data = Persistence.load() ?? UserLibraryData()
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        save()  // writes data migrated from older versions in the current format
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastScanDate) > 10 else { return }
                self.rescan()
            }
        }
        center.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan(after: 0.5) }
        }
        rescan()
    }

    func save() {
        Persistence.save(data)
    }

    func scheduleRescan(after delay: Double) {
        pendingRescan?.cancel()
        pendingRescan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    func rescan() {
        scanTask?.cancel()
        lastScanDate = Date()
        isScanning = true
        var folders = data.watchedFolders.map { FontScanner.Folder(id: $0.id, path: $0.path) }
        folders.append(.init(id: WatchedFolder.deactivatedID, path: Persistence.deactivatedDirectory.path))
        scanTask = Task { [weak self] in
            let files = await Task.detached(priority: .userInitiated) {
                FontScanner.scan(folders: folders) { message in
                    Task { @MainActor in self?.scanStatus = message }
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(files)
            self.isScanning = false
            self.hasScanned = true
        }
    }

    private func apply(_ files: [ScannedFile]) {
        let paths = Set(files.map(\.path))
        if paths != lastScannedPaths {
            FontCache.shared.invalidate()
            lastScannedPaths = paths
        }
        let userFonts = NSHomeDirectory() + "/Library/Fonts/"
        var appOnlyByFolder: [UUID: String] = [:]
        for folder in data.watchedFolders {
            if let app = folder.appOnlyName { appOnlyByFolder[folder.id] = app }
        }

        struct Builder {
            var faces: [String: LibraryFace] = [:]
            var folders: Set<UUID> = []
        }
        var builders: [String: Builder] = [:]
        for file in files {
            let status: FaceStatus
            if file.isActive {
                status = .active(activeKind(of: file.path, userFonts: userFonts))
            } else if let folder = file.folderID, let app = appOnlyByFolder[folder] {
                status = .appOnly(app)
            } else {
                status = .inactive
            }
            for face in file.faces where !face.familyName.isEmpty && !face.familyName.hasPrefix(".") {
                var builder = builders[face.familyName, default: Builder()]
                if let folder = file.folderID { builder.folders.insert(folder) }
                // The same font can exist twice, e.g. an original in a watched folder and its installed copy.
                if var existing = builder.faces[face.postScriptName] {
                    if !existing.status.isActive && status.isActive {
                        builder.faces[face.postScriptName] = LibraryFace(
                            face: face, status: status, otherPaths: existing.otherPaths + [existing.face.path]
                        )
                    } else {
                        existing.otherPaths.append(face.path)
                        builder.faces[face.postScriptName] = existing
                    }
                } else {
                    builder.faces[face.postScriptName] = LibraryFace(face: face, status: status)
                }
                builders[face.familyName] = builder
            }
        }

        var foundryCasing: [String: String] = [:]
        var result: [FontFamily] = []
        result.reserveCapacity(builders.count)
        for (name, builder) in builders {
            let faces = builder.faces.values.sorted {
                ($0.face.weightClass, $0.face.isItalic ? 1 : 0, $0.face.styleName) <
                    ($1.face.weightClass, $1.face.isItalic ? 1 : 0, $1.face.styleName)
            }
            var manufacturer = faces.lazy.compactMap { Self.normalizedFoundry($0.face.manufacturer) }.first
            if let raw = manufacturer {
                let folded = raw.lowercased().filter { $0.isLetter || $0.isNumber }
                manufacturer = foundryCasing[folded] ?? raw
                foundryCasing[folded] = manufacturer
            }
            result.append(FontFamily(
                name: name,
                faces: faces,
                status: FontFamily.status(of: faces),
                folderIDs: builder.folders,
                manufacturer: manufacturer
            ))
        }
        result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        families = result
        familyIndex = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.name, $0) })
        searchBlobs = [:]
        for family in result {
            let names = family.faces.map(\.face.postScriptName).joined(separator: " ")
            searchBlobs[family.name] = "\(family.name) \(family.manufacturer ?? "") \(names)".lowercased()
        }
        selectedFamilyIDs = selectedFamilyIDs.filter { familyIndex[$0] != nil }
        if let detail = detailFamilyID, familyIndex[detail] == nil { detailFamilyID = nil }
        unreadableFiles = files.filter { $0.faces.isEmpty }.map(\.path)
        activePaths = Set(files.lazy.filter(\.isActive).map(\.path))
        refreshProblems()
    }

    func activeKind(of path: String, userFonts: String) -> ActiveKind {
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Application Support/Apple/") {
            return .system
        }
        if path.hasPrefix("/Library/Fonts/") { return .allUsers }
        if path.hasPrefix(userFonts) { return .user }
        if path.contains("/Adobe/CoreSync/") { return .adobeCloud }
        if data.registeredPaths.contains(path) { return .registered }
        if path.contains(".app/") { return .application }
        return .other
    }


    // MARK: Inspector

    /// The family the inspector describes: the open family, or a single selection in the browser.
    var inspectorFamily: FontFamily? {
        if let detail = detailFamily { return detail }
        guard selectedFamilyIDs.count == 1, let id = selectedFamilyIDs.first else { return nil }
        return family(named: id)
    }

    func showInfo(for family: FontFamily) {
        if detailFamilyID == nil { selectedFamilyIDs = [family.id] }
        inspectorTab = .info
        isInspectorPresented = true
    }

    func toggleInfo() {
        if isInspectorPresented && inspectorTab == .info {
            isInspectorPresented = false
        } else {
            inspectorTab = .info
            isInspectorPresented = true
        }
    }

    // MARK: Lookup and filtering

    func family(named name: String) -> FontFamily? {
        familyIndex[name].map { families[$0] }
    }

    var detailFamily: FontFamily? { detailFamilyID.flatMap(family(named:)) }

    var visibleFamilies: [FontFamily] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let selection = sidebarSelection ?? .all
        var members: Set<String>?
        if case .set(let id) = selection {
            members = Set(data.sets.first { $0.id == id }?.familyNames ?? [])
        }
        return families.filter { family in
            if let members {
                guard members.contains(family.name) else { return false }
            } else {
                if !data.showSystemFonts && family.status == .system && selection != .system { return false }
                guard matches(family, selection) else { return false }
            }
            return query.isEmpty || (searchBlobs[family.name]?.contains(query) ?? false)
        }
    }

    private func matches(_ family: FontFamily, _ selection: SidebarSelection) -> Bool {
        switch selection {
        case .all: true
        case .active: family.hasActiveFaces
        case .inactive: family.faces.contains { $0.status == .inactive }
        case .system: family.status == .system
        case .problems: false
        case .folder(let id): family.folderIDs.contains(id)
        case .set: true
        case .tag(let tag): tags(of: family).contains(tag)
        case .foundry(let name): foundryName(of: family) == name
        case .classification(let classification): family.classification == classification
        }
    }

    func foundryName(of family: FontFamily) -> String? {
        if let override = data.foundryOverrides[family.name] { return override }
        guard let raw = family.manufacturer else { return nil }
        return data.foundryRenames[raw] ?? raw
    }

    var foundryNames: [String] {
        var names = Set<String>()
        for family in families where data.showSystemFonts || family.status != .system {
            if let name = foundryName(of: family) { names.insert(name) }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The name of the current sidebar selection, used as the window title.
    var selectionTitle: String {
        let selection = sidebarSelection ?? .all
        if let row = libraryRows.first(where: { $0.selection == selection }) { return row.title }
        for section in SidebarSection.allCases {
            if let row = rows(for: section).first(where: { $0.selection == selection }) { return row.title }
        }
        return "Fonts"
    }

    func families(withIDs ids: Set<String>) -> [FontFamily] {
        families.filter { ids.contains($0.id) }
    }

    /// Context-menu targets: the whole selection when the clicked family is part of it.
    func targets(for family: FontFamily) -> [FontFamily] {
        guard selectedFamilyIDs.contains(family.id), selectedFamilyIDs.count > 1 else { return [family] }
        return families.filter { selectedFamilyIDs.contains($0.id) }
    }

    var selectedFamilies: [FontFamily] {
        if let detail = detailFamily { return [detail] }
        return families.filter { selectedFamilyIDs.contains($0.id) }
    }

    // MARK: Sidebar

    func isVisible(_ key: String) -> Bool { !data.hiddenSidebarItems.contains(key) }

    func setVisible(_ key: String, _ visible: Bool) {
        if visible { data.hiddenSidebarItems.remove(key) } else { data.hiddenSidebarItems.insert(key) }
        save()
        if !visible, let selection = sidebarSelection, !isSelectionVisible(selection) {
            sidebarSelection = firstVisibleSelection
        }
    }

    func visibilityBinding(for key: String) -> Binding<Bool> {
        Binding(get: { self.isVisible(key) }, set: { self.setVisible(key, $0) })
    }

    func showAllSidebarItems() {
        data.hiddenSidebarItems.removeAll()
        save()
    }

    private func isSelectionVisible(_ selection: SidebarSelection) -> Bool {
        for row in libraryRows where row.selection == selection { return isVisible(row.key) }
        for section in SidebarSection.allCases {
            for row in rows(for: section) where row.selection == selection {
                return isVisible(section.key) && isVisible(row.key)
            }
        }
        return true
    }

    private var firstVisibleSelection: SidebarSelection? {
        libraryRows.first { isVisible($0.key) }?.selection
    }

    var libraryRows: [SidebarRow] {
        [
            SidebarRow(key: "library.all", title: "All Fonts", icon: "books.vertical", selection: .all),
            SidebarRow(key: "library.active", title: "Activated", icon: "circle.inset.filled", selection: .active),
            SidebarRow(key: "library.inactive", title: "Not Activated", icon: "circle", selection: .inactive),
            SidebarRow(key: "library.system", title: "System Fonts", icon: "apple.logo", selection: .system),
            SidebarRow(key: "library.problems", title: "Problems", icon: "exclamationmark.triangle", selection: .problems, badge: problems.count),
        ]
    }

    func rows(for section: SidebarSection) -> [SidebarRow] {
        switch section {
        case .folders:
            var folders = data.watchedFolders
            if families.contains(where: { $0.folderIDs.contains(WatchedFolder.deactivatedID) }) {
                folders.append(WatchedFolder(id: WatchedFolder.deactivatedID, path: Persistence.deactivatedDirectory.path))
            }
            return folders.map {
                SidebarRow(key: "folder.\($0.id)", title: $0.displayName, icon: $0.appOnlyName == nil ? "folder" : "folder.badge.gearshape", selection: .folder($0.id))
            }
        case .sets:
            return data.sets.map { SidebarRow(key: "set.\($0.id)", title: $0.name, icon: "square.stack", selection: .set($0.id)) }
        case .tags:
            return data.tags.map { SidebarRow(key: "tag.\($0)", title: $0, icon: "tag", selection: .tag($0)) }
        case .foundries:
            return foundryNames.map { SidebarRow(key: "foundry.\($0)", title: $0, icon: "building.2", selection: .foundry($0)) }
        case .classifications:
            let present = Set(families.lazy.filter { self.data.showSystemFonts || $0.status != .system }.map(\.classification))
            return FontClassification.allCases.filter(present.contains).map {
                SidebarRow(key: "classification.\($0.rawValue)", title: $0.rawValue, icon: $0.icon, selection: .classification($0))
            }
        }
    }

    func isExpanded(_ section: SidebarSection) -> Bool { !data.collapsedSections.contains(section.rawValue) }

    func setExpanded(_ section: SidebarSection, _ expanded: Bool) {
        if expanded { data.collapsedSections.remove(section.rawValue) } else { data.collapsedSections.insert(section.rawValue) }
        save()
    }

    // MARK: Folders

    func presentAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Select folders that contain fonts. They're listed in your library without being installed."
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func addFolders(_ urls: [URL]) {
        let existing = Set(data.watchedFolders.map(\.path))
        let new = urls.map(\.standardizedFileURL.path).filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        for path in new {
            data.watchedFolders.append(WatchedFolder(path: path, appOnlyName: WatchedFolder.detectAppOnlyName(forPath: path)))
        }
        save()
        rescan()
    }

    func removeFolder(_ id: UUID) {
        data.watchedFolders.removeAll { $0.id == id }
        data.hiddenSidebarItems.remove("folder.\(id)")
        if sidebarSelection == .folder(id) { sidebarSelection = .all }
        save()
        rescan()
    }

    func setAppOnlyName(_ name: String?, forFolder id: UUID) {
        guard let index = data.watchedFolders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        data.watchedFolders[index].appOnlyName = trimmed?.isEmpty == true ? nil : trimmed
        save()
        rescan()
    }

    func folder(_ id: UUID) -> WatchedFolder? {
        if id == WatchedFolder.deactivatedID {
            return WatchedFolder(id: id, path: Persistence.deactivatedDirectory.path)
        }
        return data.watchedFolders.first { $0.id == id }
    }

    // MARK: Sets

    func addSet(named name: String, with families: [FontFamily] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.sets.append(FontSet(name: trimmed, familyNames: families.map(\.name)))
        save()
    }

    func renameSet(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.sets.firstIndex(where: { $0.id == id }) else { return }
        data.sets[index].name = trimmed
        save()
    }

    func deleteSet(_ id: UUID) {
        data.sets.removeAll { $0.id == id }
        data.hiddenSidebarItems.remove("set.\(id)")
        if sidebarSelection == .set(id) { sidebarSelection = .all }
        save()
    }

    func isMember(_ family: FontFamily, of setID: UUID) -> Bool {
        data.sets.first { $0.id == setID }?.familyNames.contains(family.name) ?? false
    }

    func setMembership(_ member: Bool, for families: [FontFamily], in setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        var names = data.sets[index].familyNames
        for family in families {
            names.removeAll { $0 == family.name }
            if member { names.append(family.name) }
        }
        data.sets[index].familyNames = names
        save()
    }

    // MARK: Tags

    func tags(of family: FontFamily) -> [String] {
        data.familyTags[family.name] ?? []
    }

    func setTag(_ tag: String, _ on: Bool, for families: [FontFamily]) {
        for family in families {
            var tags = data.familyTags[family.name] ?? []
            tags.removeAll { $0 == tag }
            if on { tags.append(tag) }
            data.familyTags[family.name] = tags.isEmpty ? nil : tags
        }
        save()
    }

    func addTag(named name: String, to families: [FontFamily] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !data.tags.contains(trimmed) { data.tags.append(trimmed) }
        if families.isEmpty { save() } else { setTag(trimmed, true, for: families) }
    }

    func renameTag(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, !data.tags.contains(trimmed),
              let index = data.tags.firstIndex(of: old) else { return }
        data.tags[index] = trimmed
        for (family, tags) in data.familyTags where tags.contains(old) {
            data.familyTags[family] = tags.map { $0 == old ? trimmed : $0 }
        }
        if data.hiddenSidebarItems.remove("tag.\(old)") != nil { data.hiddenSidebarItems.insert("tag.\(trimmed)") }
        if sidebarSelection == .tag(old) { sidebarSelection = .tag(trimmed) }
        save()
    }

    func deleteTag(_ tag: String) {
        data.tags.removeAll { $0 == tag }
        for (family, tags) in data.familyTags where tags.contains(tag) {
            let remaining = tags.filter { $0 != tag }
            data.familyTags[family] = remaining.isEmpty ? nil : remaining
        }
        data.hiddenSidebarItems.remove("tag.\(tag)")
        if sidebarSelection == .tag(tag) { sidebarSelection = .all }
        save()
    }

    // MARK: Foundries

    func setFoundry(_ name: String?, for families: [FontFamily]) {
        for family in families {
            if let name, !name.isEmpty { data.foundryOverrides[family.name] = name } else { data.foundryOverrides.removeValue(forKey: family.name) }
        }
        save()
    }

    func renameFoundry(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        for family in families where family.manufacturer.map({ data.foundryRenames[$0] ?? $0 }) == old {
            if let raw = family.manufacturer { data.foundryRenames[raw] = trimmed }
        }
        for (family, foundry) in data.foundryOverrides where foundry == old { data.foundryOverrides[family] = trimmed }
        if data.hiddenSidebarItems.remove("foundry.\(old)") != nil { data.hiddenSidebarItems.insert("foundry.\(trimmed)") }
        if sidebarSelection == .foundry(old) { sidebarSelection = .foundry(trimmed) }
        save()
    }

    /// Drag and drop of family names onto a sidebar row.
    func handleDrop(_ names: [String], on selection: SidebarSelection) -> Bool {
        let dropped = names.compactMap(family(named:))
        guard !dropped.isEmpty else { return false }
        switch selection {
        case .set(let id): setMembership(true, for: dropped, in: id)
        case .tag(let tag): setTag(tag, true, for: dropped)
        case .foundry(let name): setFoundry(name, for: dropped)
        default: return false
        }
        return true
    }

    // MARK: Prompts

    func prompt(_ title: String, text: String = "", confirm: String, action: @escaping (String) -> Void) {
        textPrompt = TextPrompt(title: title, initialText: text, confirmTitle: confirm, action: action)
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Finder

    func reveal(_ families: [FontFamily]) {
        let urls = families.flatMap(\.revealURLs)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func reveal(_ face: LibraryFace) {
        NSWorkspace.shared.activateFileViewerSelecting([face.face.url])
    }

    func revealSelection() {
        reveal(selectedFamilies)
    }

    // MARK: Helpers

    static func normalizedFoundry(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 60 else { return nil }
        let lower = name.lowercased()
        guard !lower.contains("http"), !lower.contains("www."), !lower.hasPrefix("copyright"), !name.contains("©") else { return nil }
        for suffix in [", Inc.", " Inc.", ", Inc", " Inc", " LLC", " Ltd.", " Ltd", " GmbH", " AG", " S.A.", " B.V.", " Corporation", " Corp."]
        where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        return name.isEmpty ? nil : name
    }

}
