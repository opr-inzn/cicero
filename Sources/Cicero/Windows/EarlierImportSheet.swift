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
                    Label("\(prompt.smartSets.map { "“\($0)”" }.formatted(.list(type: .and))) "
                          + "\(prompt.smartSets.count == 1 ? "has a rule" : "have rules") about this location, and will find nothing without it.",
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
        let files = prompt.files.count == 1 ? "Its font file is copied" : "Its \(prompt.files.count.formatted()) font files are copied"
        let on = switch prompt.onCount {
        case 0: ""
        case 1: " The one that’s on stays on, as its copy."
        default: " The \(prompt.onCount.formatted()) that are on stay on, as their copies."
        }
        let office = model.data.installsIntoFontLibrary ? " Microsoft Office can’t use fonts in Cicero’s Library." : ""
        return "\(files) into \(model.installPlace), inactive.\(on)\(office) Your folders, tags, ratings and notes stay as they are. "
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
