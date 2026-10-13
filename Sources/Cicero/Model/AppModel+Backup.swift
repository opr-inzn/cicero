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
    nonisolated static let ciceroBackup = UTType(exportedAs: "local.cicero.backup")
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

    /// Sidebar rows whose fonts can be exported: sets, folders, foundries, classifications and character sets.
    func canExport(_ item: SidebarItem) -> Bool {
        switch item {
        case .set, .smartSet, .folder, .foundry, .classification, .characterSet: true
        case .all, .active, .inactive, .system, .problems: false
        }
    }

    /// Exports the families a sidebar row shows, named after the row.
    func exportFonts(in item: SidebarItem, named name: String) {
        let test = filter(for: item)
        exportFonts(library.families.filter { (data.showSystemFonts || $0.state != .system) && test($0) }, named: name)
    }

    /// Asks where to put the files (and whether as a folder or a ZIP archive), copies them off the
    /// main thread and reveals the result. `name` is what the export is called unless it's one family.
    func exportFonts(_ families: [Family], named name: String?) {
        let plan = FontExportPlan(families: families)
        guard !plan.isEmpty else {
            return showToast(families.isEmpty ? "No fonts to export." : "Fonts that come with macOS or an app can’t be exported.")
        }
        let defaultName = families.count == 1 ? families[0].name : name ?? "\(families.count) Families"
        guard let choice = ExportPanel.run(name: defaultName) else { return }
        Task {
            do {
                let result = try await FontExporter().export(plan, to: choice.url, format: choice.format)
                NSWorkspace.shared.activateFileViewerSelecting([result])
                showToast(plan.completionMessage)
            } catch {
                showToast("Couldn’t export the fonts.")
            }
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
        try await backup.write(to: destination, userData: data, fonts: fonts, includeFonts: includeFonts, appVersion: appVersion, progress: progress)
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
            showToast("Couldn’t read the backup.")
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
        guard saved else { return showToast("Couldn’t save the current setup first, so nothing was restored.") }

        var fontResult: FontRestoreResult?
        if fonts { fontResult = await backup.restoreFonts(contents, progress: progress) }
        let fallbackFolder = (fontResult?.fallback ?? 0) > 0 ? backup.fallbackFolder : nil
        if let fontResult, fontResult.cancelled {
            if let fallbackFolder { addFallbackFolder(fallbackFolder) }
            rescan()
            return showToast("Stopped restoring.")
        }

        let restored = backup.userData(from: contents)
        await enqueued { model in
            if settings {
                var data = restored
                // This Mac's activation state, merged below.
                data.records = model.data.records
                model.data = data
                model.selection = .all
            }
            if let fallbackFolder { model.addFallbackFolder(fallbackFolder) }
            let current = model.data.records
            let merged = await Task.detached(priority: .userInitiated) {
                LibraryBackup.mergedRecords(current: current, backup: restored.records) { FileManager.default.fileExists(atPath: $0) }
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
    private func enqueued(_ work: @escaping (AppModel) async -> Void) async {
        await withCheckedContinuation { continuation in
            enqueue { model in
                await work(model)
                continuation.resume()
            }
        }
    }

    /// "Restored 4 sets and 3,790 fonts; 22 were already there."
    private static func restoreSummary(settings: Bool, data: UserData, fonts: FontRestoreResult?) -> String {
        var parts: [String] = []
        if settings {
            let sets = data.sets.count + data.smartSets.count
            parts.append(sets == 0 ? "your settings" : sets == 1 ? "1 set" : "\(sets) sets")
        }
        if let fonts {
            let count = fonts.restored + fonts.fallback
            parts.append(count == 1 ? "1 font" : "\(count.formatted()) fonts")
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
        return (["Restored " + parts.formatted(.list(type: .and))] + notes).joined(separator: "; ") + "."
    }
}

/// The save panel for an export, with a Format picker (Folder or ZIP Archive) in it.
private enum ExportPanel {
    static func run(name: String) -> (url: URL, format: FontExportFormat)? {
        let panel = NSSavePanel()
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
        return (url, choice.format)
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
