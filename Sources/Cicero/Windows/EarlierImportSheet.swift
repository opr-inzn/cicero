import CiceroCore
import SwiftUI

struct EarlierImportSheet: View {
    let prompt: EarlierImportPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var stage: ImportStage?
    @State private var task: Task<Void, Never>?
    @State private var estimate = CopyTimeEstimate(intoFontsFolder: true)
    @State private var choseFontLibrary = false
    @State private var copying: Int

    init(prompt: EarlierImportPrompt) {
        self.prompt = prompt
        _copying = State(initialValue: prompt.copying)
    }

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
                          : "The smart folders \(prompt.smartSets.map { "“\($0)”" }.listed()) list the fonts in this location. "
                              + "Without the location, they will be empty.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if stage == nil, FontLibraryOffer.isShown(count: copying, chose: choseFontLibrary,
                                                      installsIntoFontLibrary: model.data.installsIntoFontLibrary) {
                FontLibraryOffer(count: copying, chose: $choseFontLibrary)
            }
            HStack(spacing: 12) {
                if let stage {
                    ImportProgress(stage: stage, starting: "Turning fonts on", estimate: estimate, stacked: true)
                } else {
                    Text("Your current setup is saved first, in ~/Library/Application Support/Cicero/Backups.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(stage == nil ? "Not Now" : "Cancel", role: .cancel) {
                    if let task {
                        stage = .stopping
                        task.cancel()
                    } else {
                        model.declineEarlierImport(prompt)
                        dismiss()
                    }
                }
                .disabled(stage.map { !$0.canStop } ?? false)
                Button("Copy Fonts") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(stage != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(stage != nil)
        .task(id: model.data.installsIntoFontLibrary) {
            guard model.data.installsIntoFontLibrary != prompt.countedForFontLibrary else { return copying = prompt.copying }
            let engine = model.importEngine
            let files = prompt.files
            let work = Task.detached(priority: .userInitiated) { engine.copyPlan(files).toCopy.count }
            let count = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            if !Task.isCancelled { copying = count }
        }
    }

    private var name: String { prompt.name }

    private var detail: String {
        let total = prompt.files.count
        let place = model.installPlace
        let files = switch copying {
        case total: total == 1 ? "Cicero copies its font file into \(place)." : "Cicero copies its \(total.plain) font files into \(place)."
        case 0: total == 1 ? "Its font file is in \(place) already." : "Its \(total.plain) font files are in \(place) already."
        case total - 1: "Cicero copies \(copying.plain) of its \(total.plain) font files into \(place). The other one is there already."
        default: "Cicero copies \(copying.plain) of its \(total.plain) font files into \(place). The others are there already."
        }
        let state = switch prompt.onCount {
        case 0: total == 1 ? " The copy is inactive, as the font is now." : " The copies are inactive, as the fonts are now."
        case total: total == 1 ? " The font is active now, and its copy will be too." : " The fonts are active now, and their copies will be too."
        case 1: " The font that’s active now stays active. The others come in inactive."
        default: " The \(prompt.onCount.plain) styles that are active now stay active. The others come in inactive."
        }
        let office = model.data.installsIntoFontLibrary ? " Microsoft Office can’t use fonts in Cicero’s Library." : ""
        return "\(files)\(state)\(office) Your folders, tags, ratings and notes stay as they are. "
            + "Then the location is removed. FontExplorer X’s own files stay where they are."
    }

    private func start() {
        stage = .copying(done: 0, total: copying)
        estimate = CopyTimeEstimate(intoFontsFolder: !model.data.installsIntoFontLibrary)
        task = Task {
            let copied = await model.copyEarlierImport(prompt) { stage in
                let now = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    guard self.stage != .stopping else { return }
                    if case .copying(let done, _) = stage { self.estimate.note(done: done, at: now) }
                    self.stage = stage
                }
            }
            task = nil
            if let copied {
                model.showToast(copied == 0 ? "FontExplorer X’s fonts were in \(model.installPlace) already"
                    : "Copied \(copied == 1 ? "1 font file" : "\(copied.plain) font files") into \(model.installPlace)")
            }
            dismiss()
        }
    }
}
