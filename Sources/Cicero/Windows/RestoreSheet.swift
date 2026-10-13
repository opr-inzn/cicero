import CiceroCore
import SwiftUI

extension View {
    /// Presents the Restore sheet for a backup read from disk.
    func restoreSheet(contents: Binding<BackupContents?>) -> some View {
        sheet(item: contents) { RestoreSheet(contents: $0) }
    }
}

/// Confirms restoring a backup: what's in it, whether to replace the setup and put the fonts
/// back, and progress while the fonts are copied.
struct RestoreSheet: View {
    let contents: BackupContents
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = true
    @State private var fonts = true
    @State private var isRestoring = false
    /// Files put back so far, while the fonts are copied.
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
            Form {
                option("Sets, folders and settings", isOn: $settings, detail: settingsDetail)
                if includesFonts {
                    option("Font files", isOn: $fonts, detail: fontsDetail)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isRestoring)
            if isRestoring {
                VStack(alignment: .leading, spacing: 4) {
                    if let progress {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        Text("Putting fonts back… \(progress.done.formatted()) of \(progress.total.formatted())")
                    } else {
                        ProgressView()
                        Text("Restoring…")
                    }
                }
                .progressViewStyle(.linear)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            HStack {
                Spacer()
                // While restoring, the task closes the sheet once it has stopped: closing it discards
                // the unzipped folder, which a copy may still be reading.
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
        .onDisappear { contents.discard() }
    }

    private func option(_ title: String, isOn: Binding<Bool>, detail: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }

    /// "4 sets, 2 smart sets, 3 tags, 3 folders, 12 added fonts and 1 character set." and what restoring them does.
    private var settingsDetail: String {
        let data = contents.userData
        let counts = [
            (data.sets.count, "set", "sets"), (data.smartSets.count, "smart set", "smart sets"), (data.tags.count, "tag", "tags"),
            (data.folders.count, "folder", "folders"), (data.fontFiles.count, "added font", "added fonts"),
            (data.customCharacterSets.count, "character set", "character sets"),
        ]
        let parts = counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        let inside = parts.isEmpty ? "No sets or folders, just settings." : parts.formatted(.list(type: .and)) + "."
        return inside + " Replaces what’s set up now; the current setup is saved first in ~/Library/Application Support/Cicero/Backups."
    }

    private var fontsDetail: String {
        "\(contents.fontCount.formatted()) files. Puts each font back where it was, unless a file is already there."
    }

    private func restore() {
        let includeFonts = fonts && includesFonts
        isRestoring = true
        progress = includeFonts ? (0, contents.fontCount) : nil
        task = Task {
            await model.restore(contents, settings: settings, fonts: includeFonts) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
            dismiss()
        }
    }
}
