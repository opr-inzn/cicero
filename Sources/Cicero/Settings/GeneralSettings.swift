import CiceroCore
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @AppStorage(UsageStatistics.defaultsKey) private var sharesUsageStatistics = true
    @AppStorage(MenuBarItem.showsIconKey) private var showsMenuBarIcon = true
    @AppStorage(MenuBarItem.showsDockIconKey) private var showsDockIcon = true
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
            Section("Menu Bar and Dock") {
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show Cicero in the menu bar")
                    Text("Click its icon to open Cicero, or drop fonts or a document on it. Right-click it to add fonts, find the fonts of the document you have open, turn folders on and off, see which fonts are on for apps, or quit Cicero.")
                }
                // On while the menu bar has no icon: Cicero can't leave the Dock then.
                Toggle(isOn: Binding(get: { showsDockIcon || !showsMenuBarIcon }, set: { showsDockIcon = $0 })) {
                    Text("Show Cicero in the Dock")
                    Text(showsMenuBarIcon
                        ? "When this is off, Cicero is in the Dock only while one of its windows is open."
                        : "Cicero can leave the Dock only while it’s in the menu bar.")
                }
                .disabled(!showsMenuBarIcon)
            }
            Section("Installation") {
                Toggle(isOn: Binding(get: { model.data.installsIntoFontLibrary }, set: { model.setInstallsIntoFontLibrary($0) })) {
                    Text("Install fonts into Cicero’s Library")
                    Text("Instead of putting the installed fonts into ~/Library/Fonts, Cicero keeps them in a folder of its own, and macOS uses them from there. A font you turn off stays in that folder. Microsoft Office can’t use these fonts. When you turn this off, the folder becomes one of your locations.")
                }
                LabeledContent {
                    Button("Change") { model.changeFontLibrary() }
                } label: {
                    Text("Cicero’s Library")
                    Text((model.data.fontLibraryPath as NSString).abbreviatingWithTildeInPath)
                }
                // Each pop-up menu as wide as its own choices.
                LabeledContent {
                    PopUpPicker(options: InstallMethod.allCases.map { (title: $0.title(intoFontLibrary: model.data.installsIntoFontLibrary), value: $0) },
                                selection: $model.data.installMethod)
                } label: {
                    Text("Activate fonts by")
                    Text(activationExplanation)
                }
                LabeledContent {
                    PopUpPicker(options: DuplicateHandling.allCases.map { (title: $0.title, value: $0) }, selection: $model.data.duplicateHandling)
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
                        : "App folders activate fonts only while Cicero is open.")
                }
                Toggle(isOn: $model.data.asksBeforeActivatingMany) {
                    Text("Ask before activating more than \(UserData.manyFamilies) families at once")
                    Text("Apps load every font that’s on as they open, so turning on many at once can slow them down.")
                }
                Toggle(isOn: $model.data.activatesDocumentFonts) {
                    HStack(spacing: 4) {
                        Text("Auto-activate fonts in Adobe apps")
                        Tag(text: "BETA", tint: .yellow, isFilled: true)
                            .help("New, and still being tried out with each app")
                    }
                    Text("When you open a document in InDesign, Illustrator or Photoshop, Cicero activates the fonts it needs from your library until the app quits. InDesign and Illustrator still show their Missing Fonts dialog, and the app can take a few seconds to use the fonts. macOS asks once for each app whether Cicero may control it. Use with caution.")
                }
            }
            Section("Library") {
                Toggle("Show system fonts", isOn: $model.data.showSystemFonts)
                Toggle(isOn: $model.data.showCreativeCloudFonts) {
                    Text("Show fonts from Creative Cloud")
                    Text("Creative Cloud activates and deactivates Adobe Fonts. Cicero lists them but can’t manage them.")
                }
                // The folders type designers export fonts to, to test them in Adobe apps.
                Toggle(isOn: $model.data.showAdobeAppFolders) {
                    Text("Show fonts installed for proofing in Adobe apps")
                    Text("[https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps)")
                }
                Toggle(isOn: $model.guessesClassifications) {
                    Text("Classify fonts automatically")
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
                    Text("Each time Cicero opens, it sends TelemetryDeck its version, the macOS version and a random number for this Mac. When you mark a family not similar, it sends Cicero’s website the names of the families in that list and the measurements of their letters, to improve similar fonts. No font files are sent.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: sharesUsageStatistics) {
            guard !sharesUsageStatistics else { return }
            UsageStatistics.forgetID()
            SimilarReports.forgetID()
        }
        .fontCacheSheet(isPresented: $isClearingCaches)
        .backupSheet(isPresented: $isBackingUp)
        .restoreSheet(contents: $restoring)
    }

    /// Follows Apple Intelligence as it's turned on or off (see `ClassificationGuesser.availability`).
    private var guessingExplanation: String {
        let what = "If a font doesn’t state its classification, Cicero recognizes it from its letter shapes and, with Apple Intelligence, from its name. Everything stays on this Mac."
        return switch ClassificationGuesser.availability {
        case .available: what
        case .notEnabled: what + " Turn on Apple Intelligence in System Settings to use names too."
        case .notReady: what + " Apple Intelligence is getting ready."
        case .unavailable: "If a font doesn’t state its classification, Cicero recognizes it from its letter shapes. Everything stays on this Mac."
        }
    }

    private var duplicateExplanation: String {
        switch model.data.duplicateHandling {
        case .ask: "Cicero shows each family you already have, and which version is newer, so you can skip the added file, add it as a copy or replace your copy with it."
        case .addCopy: "Both stay in your library, and your copy stays in use."
        case .skip: "The added file is left out, and your copy stays in use."
        case .replace: "Your copy goes to the Trash, and the added file takes its place, under its name and in its folder. If your library has it more than once, or in files that don’t match, Cicero asks first."
        }
    }

    private var activationExplanation: String {
        let place = model.data.installsIntoFontLibrary ? "Cicero’s Library" : "your user Fonts folder"
        // With any method (see `ActivationEngine.installedCopy`).
        let copiedBefore = "A font Cicero copied before goes on as that copy again."
        return switch model.data.installMethod {
        case .ask: "When you add font files, Cicero asks whether to copy them into \(place) or leave them where they are. Fonts you turn on yourself are activated where they are, and Microsoft Office can’t use them. \(copiedBefore)"
        case .copy: "Copying puts font files you add into \(place) and leaves the originals where they are. Fonts in your locations are activated where they are, and Microsoft Office can’t use them."
        case .move: "Moving takes font files you add out of their folders and puts them into \(place). Fonts in your locations are activated where they are, and Microsoft Office can’t use them."
        case .inPlace: "Fonts are activated from their current location, but they deactivate if the source moves. Microsoft Office can’t use them. \(copiedBefore)"
        }
    }
}

private extension DuplicateHandling {
    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .addCopy: "Add as a copy"
        case .skip: "Skip it"
        case .replace: "Replace your copy"
        }
    }
}

private extension InstallMethod {
    func title(intoFontLibrary: Bool) -> String {
        switch self {
        case .ask: "Ask each time"
        case .copy: intoFontLibrary ? "Copy into Cicero’s Library" : "Copy into ~/Library/Fonts"
        case .move: intoFontLibrary ? "Move into Cicero’s Library" : "Move into ~/Library/Fonts"
        case .inPlace: "Leave files where they are"
        }
    }
}
