import CiceroCore
import FoundationModels
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @AppStorage(UsageStatistics.defaultsKey) private var sharesUsageStatistics = true
    @AppStorage(SimilarReports.defaultsKey) private var sendsSimilarReports = true
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
            Section("Installation") {
                Toggle(isOn: $model.data.installsIntoFontLibrary) {
                    Text("Keep installed fonts in Cicero’s Font Library")
                    Text("Fonts Cicero installs go into the Font Library, in a folder for each family, and macOS uses them from there. Turned off, a font stays in the library.")
                }
                LabeledContent {
                    Button("Change") { model.changeFontLibrary() }
                } label: {
                    Text("Font Library")
                    Text((model.data.fontLibraryPath as NSString).abbreviatingWithTildeInPath)
                }
                let misplaced = model.misplacedInstalledFonts()
                if !misplaced.paths.isEmpty {
                    LabeledContent {
                        Button("Move Them") { model.moveInstalledFonts() }
                    } label: {
                        Text(misplacedNote(misplaced))
                    }
                }
                LabeledContent {
                    PopUpPicker(options: InstallMethod.allCases.map { ($0.title(intoFontLibrary: model.data.installsIntoFontLibrary), $0) },
                                selection: $model.data.installMethod)
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
            }
            Section("Activation") {
                Toggle(isOn: Binding(
                    get: { loginItem == .enabled || loginItem == .requiresApproval },
                    set: { loginItem = LoginItem.set($0, model: model) }
                )) {
                    Text("Open at login")
                    Text(loginItem == .requiresApproval
                        ? "Allow Cicero in System Settings → General → Login Items."
                        : "Application sets activate fonts only while Cicero is open.")
                }
                Toggle(isOn: $model.data.asksBeforeActivatingMany) {
                    Text("Ask before activating more than \(UserData.manyFamilies) families at once")
                    Text("Apps list every font that’s on in their font menus, and many at once can make them slower to open.")
                }
                Toggle(isOn: $model.data.activatesDocumentFonts) {
                    HStack(spacing: 4) {
                        Text("Activate the fonts documents use in Adobe apps")
                        Tag(text: "BETA", tint: .orange)
                            .help("New, and still being tried out with each app")
                    }
                    Text("When a document open in InDesign, Illustrator or Photoshop uses fonts from your library that are off, Cicero activates them until the app quits. It can take a few seconds, and you’ll still see the Missing Fonts dialog as the document opens. macOS asks once whether Cicero may ask each app. Use with caution.")
                }
                .onChange(of: model.data.activatesDocumentFonts) { model.openDocumentFonts.settingChanged() }
            }
            Section("Library") {
                Toggle("Show system fonts", isOn: $model.data.showSystemFonts)
                Toggle("Show fonts from Creative Cloud", isOn: $model.data.showCreativeCloudFonts)
                // The folders type designers export fonts to, to test them in Adobe apps.
                Toggle(isOn: $model.data.showAdobeAppFolders) {
                    Text("Show test fonts installed for Adobe apps")
                    Text("[https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps)")
                }
                Toggle(isOn: $model.guessesClassifications) {
                    HStack(spacing: 6) {
                        Text("Classify fonts automatically")
                        Tag(text: "On-device Intelligence", tint: .purple)
                            .help("Cicero’s own model reads the letters, and Apple Intelligence the names, on this Mac. Nothing is sent.")
                    }
                    Text(guessingExplanation)
                }
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
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Toggle(isOn: $sharesUsageStatistics) {
                    Text("Share usage statistics")
                    Text("Each time Cicero opens, it sends TelemetryDeck its version, the macOS version and a random number for this Mac. Nothing about you or your fonts is sent.")
                }
                Toggle(isOn: $sendsSimilarReports) {
                    Text("Send not-similar reports")
                    Text("When you mark a family not similar, Cicero sends the names of the families in that list and the measurements of their letters to Cicero’s website, to improve similar fonts. No font files are sent.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: sharesUsageStatistics) { if !sharesUsageStatistics { UsageStatistics.forgetID() } }
        .onChange(of: sendsSimilarReports) { if !sendsSimilarReports { SimilarReports.forgetID() } }
        .fontCacheSheet(isPresented: $isClearingCaches)
        .backupSheet(isPresented: $isBackingUp)
        .restoreSheet(contents: $restoring)
    }

    /// Follows Apple Intelligence as it's turned on or off, the model observing its own availability.
    private var guessingExplanation: String {
        let what = "When a font’s files don’t say, Cicero tells from the shapes of its letters and, with Apple Intelligence, from its name, on this Mac. Nothing is sent."
        return switch ClassificationGuesser.availability {
        case .available: what
        case .unavailable(.appleIntelligenceNotEnabled): what + " Turn on Apple Intelligence in System Settings to tell from names too."
        case .unavailable(.modelNotReady): what + " Apple Intelligence is getting ready."
        case .unavailable: "When a font’s files don’t say, Cicero tells from the shapes of its letters, on this Mac. Nothing is sent."
        }
    }

    /// "Cicero installed Inter and Roboto before, in ~/Library/Fonts."
    private func misplacedNote(_ misplaced: (paths: [String], families: [String: String])) -> String {
        let count = misplaced.paths.count
        let names = FontNames.describe(families: Array(Set(misplaced.families.values))) ?? (count == 1 ? "a font" : "\(count) fonts")
        return "Cicero installed \(names) before, in ~/Library/Fonts."
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
        let place = model.data.installsIntoFontLibrary ? "Cicero’s Font Library" : "your user Fonts folder"
        return switch model.data.installMethod {
        case .ask: "Cicero asks each time whether to copy font files into \(place) or activate them from their current location."
        case .copy: "Copying duplicates font files into \(place)."
        case .move: "Moving puts font files into \(place); the folders they were in stay."
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
    func title(intoFontLibrary: Bool) -> String {
        switch self {
        case .ask: "Ask each time"
        case .copy: intoFontLibrary ? "Copy into the Font Library" : "Copy into ~/Library/Fonts"
        case .move: intoFontLibrary ? "Move into the Font Library" : "Move into ~/Library/Fonts"
        case .inPlace: "Leave the files where they are"
        }
    }
}
