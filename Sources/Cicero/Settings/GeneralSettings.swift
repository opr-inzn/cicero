import CiceroCore
import FoundationModels
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @AppStorage(UsageStatistics.defaultsKey) private var sharesUsageStatistics = true
    @State private var isClearingCaches = false
    @State private var loginItem = LoginItem.status
    @State private var isBackingUp = false
    @State private var restoring: BackupContents?

    var body: some View {
        @Bindable var model = model
        @Bindable var updates = updates
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .formRowCentered()
            }
            Section("Fonts") {
                LabeledContent {
                    PopUpPicker(options: InstallMethod.allCases.map { ($0.title, $0) }, selection: $model.data.installMethod)
                } label: {
                    Text("Activate fonts by")
                    Text(activationExplanation)
                }
                LabeledContent {
                    PopUpPicker(options: DuplicateHandling.allCases.map { ($0.title, $0) }, selection: $model.data.duplicateHandling)
                } label: {
                    Text("When an added font is already in your library")
                    Text(duplicateExplanation)
                }
                Toggle(isOn: Binding(
                    get: { loginItem == .enabled || loginItem == .requiresApproval },
                    set: { loginItem = LoginItem.set($0, model: model) }
                )) {
                    Text("Open at login")
                    Text(loginItem == .requiresApproval
                        ? "Allow Cicero in System Settings → General → Login Items."
                        : "Application sets activate fonts only while Cicero is open.")
                }
                Toggle("Show system fonts", isOn: $model.data.showSystemFonts)
                Toggle("Show fonts from Creative Cloud", isOn: $model.data.showCreativeCloudFonts)
                Toggle(isOn: $model.guessesClassifications) {
                    Text("Guess classifications from names")
                    Text(guessingExplanation)
                }
                .disabled(ClassificationGuesser.availability == .unavailable(.deviceNotEligible))
            }
            Section("Maintenance") {
                LabeledContent("Library") {
                    HStack {
                        Button("Rebuild") { model.rebuildFontList() }
                        Button("Back Up") { isBackingUp = true }
                        Button("Restore") { Task { restoring = await model.chooseBackupToRestore() } }
                    }
                }
                .formRowCentered()
                LabeledContent("macOS, Adobe and Office font caches") {
                    Button("Clear") { isClearingCaches = true }
                        .foregroundStyle(.red)
                }
                .formRowCentered()
            }
            // The folders type designers export fonts to, to test them in Adobe apps.
            Section("Type Designer Mode") {
                Toggle(isOn: $model.data.showAdobeAppFolders) {
                    Text("Show test fonts installed for Adobe apps")
                    Text("[https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps)")
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Toggle(isOn: $sharesUsageStatistics) {
                    Text("Share usage statistics")
                    Text("Each time Cicero opens, it sends TelemetryDeck its version, the macOS version and a random number for this Mac. Nothing about you or your fonts is sent.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: sharesUsageStatistics) { if !sharesUsageStatistics { UsageStatistics.forgetID() } }
        .fontCacheSheet(isPresented: $isClearingCaches)
        .backupSheet(isPresented: $isBackingUp)
        .restoreSheet(contents: $restoring)
    }

    /// Follows Apple Intelligence as it's turned on or off, the model observing its own availability.
    private var guessingExplanation: String {
        let what = "When nothing else classifies a font, Apple Intelligence guesses from its name, on this Mac. Nothing is sent."
        return switch ClassificationGuesser.availability {
        case .available: what
        case .unavailable(.appleIntelligenceNotEnabled): what + " Turn on Apple Intelligence in System Settings to use this."
        case .unavailable(.modelNotReady): what + " Apple Intelligence is getting ready."
        case .unavailable: "Guessing needs Apple Intelligence, which this Mac doesn’t have."
        }
    }

    private var duplicateExplanation: String {
        switch model.data.duplicateHandling {
        case .ask: "When a font file you add has fonts your library has from another file, Cicero asks what to do with each family."
        case .addCopy: "The added file is listed or installed next to the library’s copy, which stays in use."
        case .skip: "The added file is left out, and the library’s copy stays in use."
        case .useAdded: "The added file takes over: where the library’s copy is on, it goes off as deactivating does, and the added one goes on."
        case .keepNewer: "The added file takes over when its version is newer than the library’s copy, and is left out otherwise."
        }
    }

    private var activationExplanation: String {
        switch model.data.installMethod {
        case .ask: "Cicero asks each time whether to copy font files into your user Fonts folder or activate them from their current location."
        case .copy: "Copying duplicates font files into your user Fonts folder."
        case .move: "Moving puts font files into your user Fonts folder, and a folder they leave empty goes to the Trash."
        case .inPlace: "Fonts are activated from their current location, but they deactivate if the source moves."
        }
    }
}

private extension DuplicateHandling {
    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .addCopy: "Add it as another copy"
        case .skip: "Skip it"
        case .useAdded: "Use the added one"
        case .keepNewer: "Keep the newer version"
        }
    }
}

private extension InstallMethod {
    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .copy: "Copy into ~/Library/Fonts"
        case .move: "Move into ~/Library/Fonts"
        case .inPlace: "Leave the files where they are"
        }
    }
}
