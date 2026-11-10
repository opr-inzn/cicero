import AppKit
import CiceroCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let ciceroBackup = UTType(exportedAs: "com.maximilianinzinger.cicero.backup")
}

extension AppModel {
    // MARK: Export

    func exportSelectionOrList() {
        let selected = selectedFamilies
        if !selected.isEmpty {
            exportFonts(selected, named: nil)
        } else {
            exportFonts(visibleFamilies, named: selectedItems.count == 1 ? selectionTitle : nil)
        }
    }

    func canExport(_ item: SidebarItem) -> Bool {
        switch item {
        case .folder(WatchedFolder.adobeFontsID): false
        case .set, .smartSet, .tag, .folder, .foundry, .classification, .characterSet: true
        case .all, .active, .inactive, .temporary, .system, .recent, .problems: false
        }
    }

    func exportFonts(in rows: [SidebarRow]) {
        let items = rows.map(\.item)
        let faces = Set(faces(in: items).map(\.id))
        var seen = Set<String>()
        let families = items.flatMap { families(in: $0) }.filter { seen.insert($0.id).inserted }
        exportFonts(families, named: rows.count == 1 ? rows[0].title : nil) { faces.contains($1.id) }
    }

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

    // MARK: Backup

    private var backup: LibraryBackup { LibraryBackup(locations: locations) }

    func saveSetupSnapshot(named name: String, nothingWas done: String) async -> Bool {
        let backup = backup
        let current = data
        let saved = await Task.detached(priority: .userInitiated) { (try? backup.saveSnapshot(current, named: name)) != nil }.value
        if !saved { showToast("Couldn’t save the current setup first, so nothing was \(done)") }
        return saved
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    func backupInventory() async -> [BackupFont] {
        await backup.inventory(of: library, records: data.records)
    }

    func backUp(to destination: URL, fonts: [BackupFont], includeFonts: Bool, progress: @escaping @Sendable (BackupProgress) -> Void) async throws {
        guard startJob(.backingUp) else { throw CancellationError() }
        defer { endJob(.backingUp) }
        // Replace in the save panel must never trash a font, even when the sheet hasn't counted them yet.
        let kept = FontExporter.keptPaths(in: library, data: data, locations: locations)
        try await backup.write(to: destination, userData: data, fonts: fonts, includeFonts: includeFonts, keeping: kept,
                               appVersion: appVersion, progress: progress)
    }

    // MARK: Restore

    func chooseBackupToRestore() async -> BackupContents? {
        if let job {
            showToast(job.waitMessage)
            return nil
        }
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

    func restore(_ contents: BackupContents, settings: Bool, fonts: Bool, progress: @escaping @Sendable (Int, Int) -> Void) async {
        guard startJob(.restoring) else { return }
        defer { endJob(.restoring) }
        let backup = backup
        let current = data
        guard await saveSetupSnapshot(named: "Before Restore", nothingWas: "restored") else { return }

        let fontLibrary = settings && !contents.userData.fontLibraryPath.isEmpty ? nil : current.fontLibraryPath
        var fontResult: FontRestoreResult?
        if fonts { fontResult = await backup.restoreFonts(contents, fontLibrary: fontLibrary, progress: progress) }
        let fallbackFolder = (fontResult?.fallback ?? 0) > 0 ? backup.fallbackFolder : nil
        if let fontResult, fontResult.cancelled {
            if let fallbackFolder { addFallbackFolder(fallbackFolder) }
            rescan()
            return showToast("Stopped restoring")
        }

        var restored = backup.userData(from: contents, fontLibrary: fontLibrary)
        if let moved = fontResult?.fallbackPaths, !moved.isEmpty {
            restored.fontFiles = restored.fontFiles.map { moved[$0] ?? $0 }
            restored.records.inPlace = Set(restored.records.inPlace.map { moved[$0] ?? $0 })
        }
        await enqueued { [restored] model in
            if settings {
                var data = restored
                data.records = model.data.records
                data.updateLicenseTags()
                data.keepFormerFontLibraryAsLocation(hasFonts: model.fontLibraryHasFonts)
                model.data = data
                model.selection = .all
            }
            if let fallbackFolder { model.addFallbackFolder(fallbackFolder) }
            let off = await model.engine.moveIntoFontsFolderOff(fontResult?.turningOff ?? [:])
            let current = model.data.records
            let written = Set((fontResult?.restoredPaths ?? []).map { off.placed[$0] ?? $0 })
            let merged = await Task.detached(priority: .userInitiated) {
                LibraryBackup.mergedRecords(current: current, backup: restored.records, written: written) { FileManager.default.fileExists(atPath: $0) }
            }.value
            model.data.records = merged.records
            if !merged.reactivate.isEmpty {
                let input = model.scanInput
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

    private func addFallbackFolder(_ folder: URL) {
        guard !data.folders.contains(where: { $0.path == folder.path }) else { return }
        data.folders.append(WatchedFolder(path: folder.path))
        data.sidebar.hidden.remove(SidebarSection.folders.key)
    }

    func enqueued(_ work: @escaping (AppModel) async -> Void) async {
        await withCheckedContinuation { continuation in
            enqueue { model in
                await work(model)
                continuation.resume()
            }
        }
    }

    private static func restoreSummary(settings: Bool, data: UserData, fonts: FontRestoreResult?) -> String {
        var parts: [String] = []
        if settings {
            let folders = data.sets.count, smart = data.smartSets.count
            if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders.plain) folders") }
            if smart > 0 { parts.append(smart == 1 ? "1 smart folder" : "\(smart.plain) smart folders") }
            if parts.isEmpty { parts.append("your settings") }
        }
        if let fonts {
            let count = fonts.restored + fonts.fallback
            parts.append(count == 1 ? "1 font file" : "\(count.plain) font files")
        }
        var notes: [String] = []
        if let fonts, fonts.skipped > 0 {
            notes.append(fonts.skipped == 1 ? "1 was already there" : "\(fonts.skipped.plain) were already there")
        }
        if let fonts, fonts.fallback > 0 {
            notes.append("\(fonts.fallback.plain) couldn’t go back and are in ~/\(LibraryBackup.fallbackFolderPath)")
        }
        if let fonts, fonts.failed > 0 {
            notes.append("\(fonts.failed.plain) couldn’t be written")
        }
        return (["Restored " + parts.listed()] + notes).joined(separator: "; ")
    }
}

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
        return (url, url.pathExtension.lowercased() == "zip" ? .zip : choice.format)
    }

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
