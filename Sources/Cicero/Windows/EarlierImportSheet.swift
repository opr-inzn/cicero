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
    /// How long the copying has left, from when Copy Fonts is pressed.
    @State private var estimate = CopyTimeEstimate(intoFontsFolder: true)
    /// Cicero's Library was chosen in this sheet, so it can be undone here.
    @State private var choseFontLibrary = false
    /// How many files it copies, counted again when they'd go elsewhere (see `EarlierImportPrompt.copying`).
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
                          : "The smart folders \(prompt.smartSets.map { "“\($0)”" }.formatted(.list(type: .and))) list the fonts in this location. "
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
        .task(id: model.data.installsIntoFontLibrary) {
            guard model.data.installsIntoFontLibrary != prompt.countedForFontLibrary else { return copying = prompt.copying }
            let engine = model.engine
            let files = prompt.files
            let work = Task.detached(priority: .userInitiated) { engine.copyPlan(files).toCopy.count }
            let count = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            if !Task.isCancelled { copying = count }
        }
    }

    private var name: String { model.data.folderNames[prompt.folder.id.uuidString] ?? prompt.folder.displayName }

    /// What happens: where the files go, what stays on, what's kept, and that the location goes.
    private var detail: String {
        let total = prompt.files.count
        let place = model.installPlace
        let files = switch copying {
        case total: total == 1 ? "Cicero copies its font file into \(place)." : "Cicero copies its \(total.formatted()) font files into \(place)."
        case 0: total == 1 ? "Its font file is in \(place) already." : "Its \(total.formatted()) font files are in \(place) already."
        case total - 1: "Cicero copies \(copying.formatted()) of its \(total.formatted()) font files into \(place). The other one is there already."
        default: "Cicero copies \(copying.formatted()) of its \(total.formatted()) font files into \(place). The others are there already."
        }
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
                // Too narrow for both on one line beside the buttons.
                CopyingProgressLine(done: done, total: total, estimate: estimate, stacked: true)
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
        stage = .copying(done: 0, total: copying)
        estimate = CopyTimeEstimate(intoFontsFolder: !model.data.installsIntoFontLibrary)
        task = Task {
            let copied = await model.copyEarlierImport(prompt) { stage in
                let now = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    if case .copying(let done, _) = stage { self.estimate.note(done: done, at: now) }
                    self.stage = stage
                }
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
