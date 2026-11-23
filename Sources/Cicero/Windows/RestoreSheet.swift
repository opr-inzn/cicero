import CiceroCore
import SwiftUI

extension View {
    func restoreSheet(contents: Binding<BackupContents?>) -> some View {
        sheet(item: contents) { RestoreSheet(contents: $0) }
    }
}

struct RestoreSheet: View {
    let contents: BackupContents
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = true
    @State private var fonts = true
    @State private var isRestoring = false
    @State private var progress: (done: Int, total: Int)?
    @State private var task: Task<Void, Never>?

    private var includesFonts: Bool { contents.manifest.includesFonts && contents.fontCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore the Backup from \(contents.manifest.created.formatted(date: .long, time: .omitted))?").font(.title2.bold())
                Text("Made with Cicero \(contents.manifest.appVersion) at \(contents.manifest.created.formatted(date: .omitted, time: .shortened)).")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                DetailToggle("Folders, locations and settings", detail: settingsDetail, isOn: $settings)
                if includesFonts {
                    DetailToggle("Font files", detail: fontsDetail, isOn: $fonts)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isRestoring)
            if isRestoring {
                VStack(alignment: .leading, spacing: 4) {
                    if let progress {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        Text("Putting fonts back, \(progress.done.plain) of \(progress.total.plain)")
                    } else {
                        ProgressView()
                        Text("Restoring")
                    }
                }
                .progressViewStyle(.linear)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            HStack {
                Spacer()
                // While restoring, the task closes the sheet once it has stopped: closing it discards the unzipped folder, which a copy may still be reading.
                Button("Cancel", role: .cancel) {
                    if let task { task.cancel() } else { dismiss() }
                }
                Button("Restore") { restore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRestoring || (!settings && !(fonts && includesFonts)))
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(isRestoring)
        .onDisappear { if !isRestoring { contents.discard() } }
    }

    private var settingsDetail: String {
        let data = contents.userData
        let counts = [
            (data.sets.count, "folder", "folders"), (data.smartSets.count, "smart folder", "smart folders"), (data.tags.count, "tag", "tags"),
            (data.folders.count, "location", "locations"), (data.fontFiles.count, "added font", "added fonts"),
            (data.customCharacterSets.count, "coverage set", "coverage sets"),
        ]
        let parts = counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        let inside = parts.isEmpty ? "No folders or locations, just settings." : parts.listed() + "."
        return inside + " Replaces what’s set up now; the current setup is saved first, in ~/Library/Application Support/Cicero/Backups."
    }

    private var fontsDetail: String {
        "\(contents.fontCount == 1 ? "1 file" : "\(contents.fontCount.plain) files"). Puts each file back where it was, unless one is already there."
    }

    private func restore() {
        let includeFonts = fonts && includesFonts
        isRestoring = true
        progress = includeFonts ? (0, contents.fontCount) : nil
        task = Task {
            await model.restore(contents, settings: settings, fonts: includeFonts) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
            contents.discard()
            dismiss()
        }
    }
}
