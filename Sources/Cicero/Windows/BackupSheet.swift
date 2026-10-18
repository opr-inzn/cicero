import AppKit
import CiceroCore
import SwiftUI

extension View {
    /// Presents the Back Up Library sheet.
    func backupSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { BackupSheet() }
    }
}

/// Says what a backup holds, offers to include the font files with their count and size, asks
/// where to save it, and shows progress while it's written.
struct BackupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includeFonts = true
    /// nil while the library's files are still being counted.
    @State private var fonts: [BackupFont]?
    @State private var progress: BackupProgress?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Back Up Library").font(.title2.bold())
                Text("The backup has everything set up in Cicero: sets, smart sets, tags, coverage sets, folders and added fonts, foundry names, the sidebar, and the settings for activation, system fonts and Adobe fonts.")
                    .foregroundStyle(.secondary)
            }
            Form {
                Toggle(isOn: $includeFonts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include font files")
                        Text(fontsDetail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(fonts?.isEmpty == true)
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(progress != nil)
            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    switch progress {
                    case .copying(let done, let total):
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                        Text("Copying fonts, \(done.formatted()) of \(total.formatted())")
                    case .compressing:
                        ProgressView()
                        Text("Compressing")
                    }
                }
                .progressViewStyle(.linear)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    task?.cancel()
                    dismiss()
                }
                Button("Back Up") { backUp() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(progress != nil || (includeFonts && fonts == nil))
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { fonts = await model.backupInventory() }
    }

    private var fontsDetail: String {
        guard let fonts else { return "Counting" }
        if fonts.isEmpty { return "There are no font files in your library." }
        let size = fonts.reduce(Int64(0)) { $0 + $1.size }
        return "\(fonts.count.formatted()) files, \(size.formatted(.byteCount(style: .file)))"
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.title = "Back Up Library"
        panel.allowedContentTypes = [.ciceroBackup]
        panel.nameFieldStringValue = LibraryBackup.defaultName()
        panel.canCreateDirectories = true
        panel.prompt = "Back Up"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let fonts = fonts ?? []
        let include = includeFonts && !fonts.isEmpty
        progress = include ? .copying(done: 0, total: fonts.count) : .compressing
        task = Task {
            do {
                try await model.backUp(to: destination, fonts: fonts, includeFonts: include) { step in
                    Task { @MainActor in progress = step }
                }
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                model.showToast(include ? "Backed up your library and \(fonts.count.formatted()) font files" : "Backed up your library")
                dismiss()
            } catch is CancellationError {
                dismiss()
            } catch let refusal as KeptItemError {
                progress = nil
                model.showToast(refusal.message)
            } catch {
                progress = nil
                model.showToast("Couldn’t write the backup")
            }
        }
    }
}
