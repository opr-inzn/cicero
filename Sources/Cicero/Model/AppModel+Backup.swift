import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

/// The Back Up and Restore sheets of the main window, which the File menu opens.
@Observable
final class BackupPrompts {
    var isBackingUp = false
    /// A backup read from disk, waiting for the Restore sheet's go-ahead.
    var restoring: BackupContents?
}

extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroBackup = UTType(exportedAs: "com.maximilianinzinger.cicero.backup")
}

extension AppModel {
    // MARK: Export

    /// The browser's selection, or with nothing selected every family in the list.
    func exportSelectionOrList() {
        let selected = selectedFamilies
        if !selected.isEmpty {
            exportFonts(selected, named: nil)
        } else {
            exportFonts(visibleFamilies, named: selectedItems.count == 1 ? selectionTitle : nil)
        }
    }

    /// Sidebar rows whose fonts can be exported: sets, tags, folders, foundries, classifications and character sets.
    func canExport(_ item: SidebarItem) -> Bool {
        switch item {
        // Creative Cloud's files never leave it.
        case .folder(WatchedFolder.adobeFontsID): false
        case .set, .smartSet, .tag, .folder, .foundry, .classification, .characterSet: true
        case .all, .active, .inactive, .system, .problems: false
        }
    }

    /// Exports the fonts a sidebar row has, named after the row: of a set, only the styles it has.
    func exportFonts(in item: SidebarItem, named name: String) {
        let faces = Set(faces(in: item).map(\.id))
        exportFonts(families(in: item), named: name) { faces.contains($1.id) }
    }

    /// Asks where to put the files (and whether as a folder or a ZIP archive), copies them off the
    /// main thread and reveals the result. Called `name`, else after the one family or "N Families". `including` picks
    /// the styles of a family to export; all of them unless it says otherwise.
    func exportFonts(_ families: [Family], named name: String?, including: (Family, LibraryFace) -> Bool = { _, _ in true }) {
        let plan = FontExportPlan(families: families, including: including)
        guard !plan.isEmpty else {
            return showToast(families.isEmpty ? "No fonts to export" : "Fonts that come with macOS or an app can’t be exported")
        }
        let defaultName = name ?? (families.count == 1 ? families[0].name : "\(families.count) Families")
        guard let choice = ExportPanel.run(name: defaultName) else { return }
        // Replace in the save panel must never trash the fonts themselves, or a folder holding them.
        let kept = FontExporter.keptPaths(in: library, data: data, locations: locations)
        Task {
            do {
                let result = try await FontExporter().export(plan, to: choice.url, format: choice.format, keeping: kept)
                NSWorkspace.shared.activateFileViewerSelecting([result])
                showToast(plan.completionMessage)
            } catch let refusal as KeptItemError {
                showToast(refusal.message)
            } catch {
                showToast("Couldn’t export the fonts")
            }
        }
    }

    // MARK: Font list

    /// A list of the browser's selection, or with nothing selected of every family in the list (see `exportFontList`).
    func exportFontListOfSelectionOrList() {
        let selected = selectedFamilies
        if !selected.isEmpty {
            exportFontList(selected, named: nil)
        } else {
            exportFontList(visibleFamilies, named: selectedItems.count == 1 ? selectionTitle : nil)
        }
    }

    /// Asks where to save a CSV file listing the families, for a spreadsheet, writes it and reveals it. Called `name`,
    /// else after the one family or "N Families".
    func exportFontList(_ families: [Family], named name: String?) {
        guard !families.isEmpty else { return showToast("No fonts to list") }
        let panel = NSSavePanel()
        panel.title = "Export Font List"
        panel.prompt = "Export"
        panel.nameFieldLabel = "Export As:"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (name ?? (families.count == 1 ? families[0].name : "\(families.count) Families")) + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let foundryName = foundryNamer()
        let classificationName = classificationNamer()
        let rows = families.map { family in
            FontListCSV.Row(family: family, foundry: foundryName(family), classification: classificationName(family), status: statusTitle(of: family),
                            tags: data.tags(of: family.id), rating: rating(of: family), note: note(of: family))
        }
        do {
            try FontListCSV.data(rows).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showToast("\(FontNames.describe(families: families.map(\.name)) ?? "") listed in “\(url.lastPathComponent)”")
        } catch {
            showToast("Couldn’t save the font list")
        }
    }

    /// Whether a family is on, in words, as the font list has it.
    private func statusTitle(of family: Family) -> String {
        switch family.state {
        case .active: family.temporaryScope != nil ? "Active Temporarily" : "Active"
        case .partial: "Partly Active"
        case .inactive: "Inactive"
        case .appOnly(let app): "Active in \(FaceState.appDescription(app))"
        case .system: "Installed with macOS"
        }
    }

    // MARK: Backup

    private var backup: LibraryBackup { LibraryBackup(locations: locations) }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Every font file in the library with its size, for the Back Up sheet. Reads the disk off the main thread.
    func backupInventory() async -> [BackupFont] {
        await backup.inventory(of: library, records: data.records)
    }

    /// Writes a backup; the caller shows the progress and may cancel the task.
    func backUp(to destination: URL, fonts: [BackupFont], includeFonts: Bool, progress: @escaping @Sendable (BackupProgress) -> Void) async throws {
        // Replace in the save panel must never trash a font, even when the sheet hasn't counted them yet.
        let kept = FontExporter.keptPaths(in: library, data: data, locations: locations)
        try await backup.write(to: destination, userData: data, fonts: fonts, includeFonts: includeFonts, keeping: kept,
                               appVersion: appVersion, progress: progress)
    }

    // MARK: Restore

    /// Asks for a backup file and reads it; nil when cancelled or it can't be read (a toast says why).
    func chooseBackupToRestore() async -> BackupContents? {
        let panel = NSOpenPanel()
        // By the declared type, and by extension in case the type isn't registered with macOS yet.
        panel.allowedContentTypes = [.ciceroBackup] + [UTType(filenameExtension: LibraryBackup.fileExtension)].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Cicero backup to restore."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try await LibraryBackup.open(url)
        } catch let failure as LibraryBackup.Failure {
            showToast(failure.message)
        } catch {
            showToast("Couldn’t read the backup")
        }
        return nil
    }

    /// Saves the current setup to the Backups folder, puts the fonts back (the long part, in the
    /// caller's task so it can be cancelled), then replaces the setup and merges the records in one
    /// queued operation, activates again what the backup had in place, rescans and reports.
    func restore(_ contents: BackupContents, settings: Bool, fonts: Bool, progress: @escaping @Sendable (Int, Int) -> Void) async {
        let backup = backup
        let current = data
        let saved = await Task.detached(priority: .userInitiated) { (try? backup.saveSnapshot(current)) != nil }.value
        guard saved else { return showToast("Couldn’t save the current setup first, so nothing was restored") }

        // Restoring the settings brings the backup's Font Library, if it has one; otherwise its fonts go into this one.
        let fontLibrary = settings && !contents.userData.fontLibraryPath.isEmpty ? nil : current.fontLibraryPath
        var fontResult: FontRestoreResult?
        if fonts { fontResult = await backup.restoreFonts(contents, fontLibrary: fontLibrary, progress: progress) }
        let fallbackFolder = (fontResult?.fallback ?? 0) > 0 ? backup.fallbackFolder : nil
        if let fontResult, fontResult.cancelled {
            if let fallbackFolder { addFallbackFolder(fallbackFolder) }
            rescan()
            return showToast("Stopped restoring")
        }

        let restored = backup.userData(from: contents, fontLibrary: fontLibrary)
        await enqueued { model in
            if settings {
                var data = restored
                // This Mac's activation state, merged below.
                data.records = model.data.records
                // A backup from before there were license tags gets them, and one from 1.9.1 or before loses the former
                // ones it never used, as a library from then does as it loads.
                data.updateLicenseTags()
                model.data = data
                model.selection = .all
            }
            if let fallbackFolder { model.addFallbackFolder(fallbackFolder) }
            let current = model.data.records
            let written = fontResult?.restoredPaths ?? []
            let merged = await Task.detached(priority: .userInitiated) {
                LibraryBackup.mergedRecords(current: current, backup: restored.records, written: written) { FileManager.default.fileExists(atPath: $0) }
            }.value
            model.data.records = merged.records
            if !merged.reactivate.isEmpty {
                // macOS doesn't know these registrations; a scan finds the faces of the files just put back.
                let input = ScanInput(folders: model.data.scannedFolders(), records: model.data.records)
                if let library = try? await model.scanner.scan(input, progress: { _ in }) {
                    let wanted = Set(merged.reactivate)
                    let faces = library.families.flatMap(\.faces).filter { wanted.contains($0.face.path) && $0.canActivate }
                    if !faces.isEmpty {
                        let result = await model.engine.activate(faces, method: .inPlace, records: model.data.records)
                        model.data.records = result.records
                    }
                }
            }
            model.rescan()
            model.showToast(Self.restoreSummary(settings: settings, data: restored, fonts: fontResult))
        }
    }

    /// Fonts that couldn't go back are in a folder of their own; it's watched so they stay in the library.
    private func addFallbackFolder(_ folder: URL) {
        guard !data.folders.contains(where: { $0.path == folder.path }) else { return }
        data.folders.append(WatchedFolder(path: folder.path))
        data.sidebar.hidden.remove(SidebarSection.folders.key)
    }

    /// Runs an operation after the queued ones and waits for it.
    func enqueued(_ work: @escaping (AppModel) async -> Void) async {
        await withCheckedContinuation { continuation in
            enqueue { model in
                await work(model)
                continuation.resume()
            }
        }
    }

    /// "Restored 4 sets and 3,790 font files; 22 were already there"
    private static func restoreSummary(settings: Bool, data: UserData, fonts: FontRestoreResult?) -> String {
        var parts: [String] = []
        if settings {
            let sets = data.sets.count + data.smartSets.count
            parts.append(sets == 0 ? "your settings" : sets == 1 ? "1 set" : "\(sets) sets")
        }
        if let fonts {
            let count = fonts.restored + fonts.fallback
            parts.append(count == 1 ? "1 font file" : "\(count.formatted()) font files")
        }
        var notes: [String] = []
        if let fonts, fonts.skipped > 0 {
            notes.append(fonts.skipped == 1 ? "1 was already there" : "\(fonts.skipped.formatted()) were already there")
        }
        if let fonts, fonts.fallback > 0 {
            notes.append("\(fonts.fallback.formatted()) couldn’t go back and are in “\(LibraryBackup.fallbackFolderName)”")
        }
        if let fonts, fonts.failed > 0 {
            notes.append("\(fonts.failed.formatted()) couldn’t be written")
        }
        return (["Restored " + parts.formatted(.list(type: .and))] + notes).joined(separator: "; ")
    }
}

/// The save panel for an export, with a Format picker (Folder or ZIP Archive) in it.
private enum ExportPanel {
    static func run(name: String) -> (url: URL, format: FontExportFormat)? {
        let panel = NSSavePanel()
        panel.title = "Export Fonts"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.nameFieldLabel = "Export As:"
        panel.nameFieldStringValue = name
        let choice = ExportChoice()
        let picker = NSHostingView(rootView: FormatPicker(choice: choice) { apply($0, to: panel) })
        picker.setFrameSize(picker.fittingSize)
        panel.accessoryView = picker
        apply(choice.format, to: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // A name typed with .zip means an archive, whatever the picker says.
        return (url, url.pathExtension.lowercased() == "zip" ? .zip : choice.format)
    }

    /// A ZIP archive gets the .zip extension, a folder none.
    private static func apply(_ format: FontExportFormat, to panel: NSSavePanel) {
        let typed = panel.nameFieldStringValue as NSString
        let base = typed.pathExtension.lowercased() == "zip" ? typed.deletingPathExtension : typed as String
        switch format {
        case .folder:
            panel.allowedContentTypes = []
            panel.nameFieldStringValue = base
        case .zip:
            panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = base + ".zip"
        }
    }
}

@Observable
private final class ExportChoice {
    var format: FontExportFormat = .folder
}

private struct FormatPicker: View {
    @Bindable var choice: ExportChoice
    let onChange: (FontExportFormat) -> Void

    var body: some View {
        Picker("Format:", selection: $choice.format) {
            ForEach(FontExportFormat.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .fixedSize()
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .onChange(of: choice.format) { onChange(choice.format) }
    }
}
