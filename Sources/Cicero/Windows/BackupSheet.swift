import AppKit
import CiceroCore
import SwiftUI

extension View {
    func backupSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { BackupSheet() }
    }
}

struct BackupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includeFonts = true
    @State private var fonts: [BackupFont]?
    @State private var progress: BackupProgress?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Back Up Library").font(.title2.bold())
                Text("The backup has everything set up in Cicero: folders, smart folders, tags, ratings and notes, coverage sets, locations and added fonts, foundry names, the sidebar, and the settings for activation, system fonts, Adobe Fonts and Proofing.")
                    .foregroundStyle(.secondary)
            }
            DetailToggle("Include font files", detail: fontsDetail, isOn: $includeFonts)
                .disabled(fonts?.isEmpty == true || progress != nil)
            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    switch progress {
                    case .copying(let done, let total):
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                        Text("Copying fonts, \(done.plain) of \(total.plain)")
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
        return "\(fonts.count == 1 ? "1 file" : "\(fonts.count.plain) files"), \(size.formatted(.byteCount(style: .file)))"
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
                if !Task.isCancelled { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                model.showToast(include ? "Backed up your library and \(fonts.count == 1 ? "1 font file" : "\(fonts.count.plain) font files")" : "Backed up your library")
                dismiss()
            } catch is CancellationError {
                dismiss()
            } catch let refusal as KeptItemError {
                progress = nil
                model.showToast(refusal.message)
            } catch let failure as LibraryBackup.Failure {
                progress = nil
                model.showToast(failure.message)
            } catch {
                progress = nil
                model.showToast("Couldn’t write the backup")
            }
        }
    }
}
