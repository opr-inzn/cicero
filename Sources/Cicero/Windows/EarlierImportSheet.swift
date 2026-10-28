import CiceroCore
import SwiftUI

/// Offers to copy FontExplorer X's Font Library in, where an import up to 0.10.13 made it a location (see
/// `AppModel.offerEarlierImportCopy`), then shows the copying. Not Now leaves it a location until the next launch.
struct EarlierImportSheet: View {
    let prompt: EarlierImportPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var stage: ImportStage?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copy FontExplorer X’s Fonts Into Cicero?").font(.title2.bold())
                Text("When you imported from FontExplorer X, Cicero added its Font Library as the location “\(name)”. "
                    + "Imports copy fonts in now, so they keep working when FontExplorer X moves or deletes its files.")
                Text(detail).foregroundStyle(.secondary)
                if !prompt.smartSets.isEmpty {
                    Label(prompt.smartSets.count == 1
                          ? "The smart folder “\(prompt.smartSets[0])” lists the fonts in this location. Without the location, it will be empty."
                          : "The smart folders \(prompt.smartSets.map { "“\($0)”" }.formatted(.list(type: .and))) list the fonts in this location. "
                              + "Without the location, they will be empty.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let stage {
                    progress(stage)
                } else {
                    Text("Your current setup is saved first, in Backups.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(stage == nil ? "Not Now" : "Cancel", role: .cancel) {
                    if let task { task.cancel() } else { dismiss() }
                }
                .disabled(stage != nil && !isCopying)
                Button("Copy Fonts") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(stage != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(stage != nil)
    }

    private var name: String { model.data.folderNames[prompt.folder.id.uuidString] ?? prompt.folder.displayName }

    /// What happens: where the files go, what stays on, what's kept, and that the location goes.
    private var detail: String {
        let total = prompt.files.count
        let files = total == 1 ? "Cicero copies its font file into \(model.installPlace)." : "Cicero copies its \(total.formatted()) font files into \(model.installPlace)."
        // Which copies are on: as their fonts are now.
        let state = switch prompt.onCount {
        case 0: total == 1 ? " The copy is inactive, as the font is now." : " The copies are inactive, as the fonts are now."
        case total: total == 1 ? " The font is active now, and its copy will be too." : " The fonts are active now, and their copies will be too."
        case 1: " The font that’s active now will be active as its copy; the others come in inactive."
        default: " The \(prompt.onCount.formatted()) fonts that are active now will be active as their copies; the others come in inactive."
        }
        let office = model.data.installsIntoFontLibrary ? " Microsoft Office can’t use fonts in Cicero’s Library." : ""
        return "\(files)\(state)\(office) Your folders, tags, ratings and notes stay as they are. "
            + "Then the location is removed. FontExplorer X’s own files stay where they are."
    }

    @ViewBuilder
    private func progress(_ stage: ImportStage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch stage {
            case .copying(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Copying fonts, \(done.formatted()) of \(total.formatted())")
            case .reading(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Reading fonts, \(done.formatted()) of \(total.formatted())")
            case .starting:
                ProgressView()
                Text("Turning fonts on")
            }
        }
        .progressViewStyle(.linear)
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var isCopying: Bool {
        if case .copying = stage { true } else { false }
    }

    private func start() {
        stage = .copying(done: 0, total: prompt.files.count)
        task = Task {
            let copied = await model.copyEarlierImport(prompt) { stage in
                Task { @MainActor in self.stage = stage }
            }
            task = nil
            if let copied {
                model.showToast(copied == 0 ? "FontExplorer X’s fonts were in \(model.installPlace) already. Removed the location"
                    : "Copied \(copied == 1 ? "1 font file" : "\(copied.formatted()) font files") into \(model.installPlace) and removed the location")
            }
            dismiss()
        }
    }
}
