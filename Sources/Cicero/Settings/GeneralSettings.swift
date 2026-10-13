import CiceroCore
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @State private var isClearingCaches = false
    @State private var isBackingUp = false
    @State private var restoring: BackupContents?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .formRowCentered()
            }
            Section {
                LabeledContent("Activate fonts by") {
                    PopUpPicker(options: InstallMethod.allCases.map { ($0.title, $0) }, selection: $model.data.installMethod)
                }
                .formRowCentered()
            } header: {
                Text("Activation")
            } footer: {
                Text(activationExplanation).formFooter()
            }
            Section {
                Toggle("Show system fonts", isOn: $model.data.showSystemFonts)
            } footer: {
                Text("Fonts that come with macOS. With this off, they’re hidden everywhere, System Fonts in the sidebar too.").formFooter()
            }
            Section {
                LabeledContent("Cicero’s font list") {
                    Button("Rebuild") { model.rebuildFontList() }
                }
                .formRowCentered()
                LabeledContent("macOS, Adobe and Office caches") {
                    Button("Clear") { isClearingCaches = true }
                        .foregroundStyle(.red)
                }
                .formRowCentered()
            } header: {
                Text("Font Caches")
            } footer: {
                Text("Rebuild reads every font file again. Clearing the caches helps when fonts don’t show up in apps or look wrong.").formFooter()
            }
            Section {
                LabeledContent("Your library") {
                    HStack {
                        Button("Back Up…") { isBackingUp = true }
                        Button("Restore…") { Task { restoring = await model.chooseBackupToRestore() } }
                    }
                }
                .formRowCentered()
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup holds your sets, smart sets, character sets, folders, foundry names, sidebar and settings, and can include your font files.").formFooter()
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .fontCacheSheet(isPresented: $isClearingCaches)
        .backupSheet(isPresented: $isBackingUp)
        .restoreSheet(contents: $restoring)
    }

    private var activationExplanation: String {
        let method = switch model.data.installMethod {
        case .ask: "Cicero asks each time whether to copy the fonts into your Fonts folder or use them where they are."
        case .copy: "Cicero copies the font files into your Fonts folder. The originals stay where they are, and the fonts keep working if you move them."
        case .inPlace: "Cicero tells macOS to use the font files from where they are. Nothing is copied, but the fonts stop working if the files move or their disk is unplugged."
        }
        return method + " Fonts from a folder an app loads itself, like Adobe’s, are always used where they are."
    }
}

private extension InstallMethod {
    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .copy: "Copy into ~/Library/Fonts"
        case .inPlace: "Use the files where they are"
        }
    }
}
