import CiceroCore
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
                Toggle(isOn: Binding(get: { model.data.installsIntoFontLibrary }, set: { model.setInstallsIntoFontLibrary($0) })) {
                    Text("Install fonts into Cicero’s Library")
                    Text("Instead of putting the installed fonts into your Fonts folder, Cicero keeps them in a folder of its own, and macOS uses them from there. A font you turn off stays in that folder. Microsoft Office can’t use these fonts. When you turn this off, the folder becomes one of your locations.")
                }
                LabeledContent {
                    Button("Change") { model.changeFontLibrary() }
                } label: {
                    Text("Cicero’s Library")
                    Text((model.data.fontLibraryPath as NSString).abbreviatingWithTildeInPath)
                }
                LabeledContent {
                    PopUpPicker(options: InstallMethod.allCases.map { (title: $0.title(intoFontLibrary: model.data.installsIntoFontLibrary), value: $0) },
                                selection: $model.data.installMethod)
                } label: {
                    Text("When you add font files")
                    Text(addingExplanation)
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
                        ? "Allow Cicero in System Settings → General → Login Items & Extensions."
                        : "App folders activate fonts only while Cicero is open.")
                }
                Toggle(isOn: $model.data.asksBeforeActivatingMany) {
                    Text("Ask before activating more than \(UserData.manyFamilies.plain) families at once")
                    Text("Apps load every active font as they open, so activating many at once can slow them down.")
                }
                Toggle(isOn: $model.data.asksBeforeMovingOutOfSharedFolders) {
                    Text("Ask before moving fonts out of shared folders")
                    Text("To deactivate a font that an app like InDesign loads from its own folder, Cicero moves the file out. When the folder syncs with a cloud service or is on a server, the file is removed for everyone who shares it.")
                }
                Toggle(isOn: $model.data.activatesDocumentFonts) {
                    Text("Auto-activate fonts in Adobe apps")
                    Text("When you open a document in InDesign, Illustrator or Photoshop, Cicero activates the fonts it needs from your library until the app quits. InDesign and Illustrator still show their Missing Fonts dialog, and the app can take a few seconds to use the fonts. macOS asks once for each app whether Cicero may control it.")
                }
            }
            Section("Library") {
                Toggle("Show system fonts", isOn: $model.data.showSystemFonts)
                Toggle(isOn: $model.data.showCreativeCloudFonts) {
                    Text("Show fonts from Creative Cloud")
                    Text("Creative Cloud activates and deactivates Adobe Fonts. Cicero lists them but can’t manage them.")
                }
                Toggle(isOn: $model.data.showAdobeAppFolders) {
                    Text("Show fonts installed for proofing in Adobe apps")
                    Text("Lists the fonts in folders that Adobe apps load automatically for font testing.\n[Learn how to test fonts in Adobe apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps).")
                }
                Toggle(isOn: $model.guessesClassifications) {
                    Text("Classify fonts automatically")
                    Text(guessingExplanation)
                }
            }
            Section("Maintenance") {
                LabeledContent("Library") {
                    HStack {
                        Button("Back Up") { isBackingUp = true }
                        Button("Restore") {
                            Task {
                                guard let contents = await model.chooseBackupToRestore() else { return }
                                model.ask { $0.restorePrompt = contents }
                            }
                        }
                    }
                    .disabled(model.job != nil)
                }
                .formRowCentered()
                LabeledContent("macOS, Adobe and Office font caches") {
                    Button("Clear") { isClearingCaches = true }
                        .foregroundStyle(.red)
                        .disabled(model.job != nil)
                }
                .formRowCentered()
            }
            Section("Updates") {
                LabeledContent {
                    if updates.readyVersion != nil {
                        Button("Restart to Update") { updates.installReadyUpdate() }
                            .disabled(model.job != nil)
                    } else if case .available = updates.status {
                        Button("Update") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates || updates.switching != nil)
                    } else {
                        Button("Check Now") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates || updates.switching != nil)
                    }
                } label: {
                    Text("Version \(updates.version) (\(updates.build))")
                    Text(updateStatus)
                }
                LabeledContent {
                    PopUpPicker(options: Updates.Track.allCases.map { (title: $0.title, value: $0) }, selection: $updates.track,
                                accessibilityLabel: "Update track")
                } label: {
                    Text("Update track")
                }
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Toggle(isOn: $updates.installsAutomatically) {
                    Text("Install updates automatically")
                    Text("Downloads updates in the background and installs them when you quit Cicero.")
                }
                .disabled(!updates.checksAutomatically)
                Toggle(isOn: $sharesUsageStatistics) {
                    Text("Share usage statistics")
                    Text("Each time Cicero opens, it sends TelemetryDeck its version, the macOS version and a random number for this Mac.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            updates.switchOffer.map(switchTitle) ?? "",
            isPresented: Binding(get: { updates.switchOffer != nil }, set: { if !$0 { updates.switchOffer = nil } }),
            presenting: updates.switchOffer
        ) { release in
            Button(release.isNightly ? "Switch to \(release.version)" : "Go Back to \(release.version)") { switchTo(release) }
                .disabled(model.job != nil || updates.switching != nil)
            // Cancel is the default so Return never replaces the app by accident.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: { release in
            Text(switchMessage(release))
        }
        .alert(
            "Couldn’t switch to Cicero \(updates.switchFailure?.release.version ?? "")",
            isPresented: Binding(get: { updates.switchFailure != nil }, set: { if !$0 { updates.switchFailure = nil } }),
            presenting: updates.switchFailure
        ) { failure in
            Button("Download \(failure.release.version)") { NSWorkspace.shared.open(failure.release.url) }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text("\(failure.message) This version stays. You can download Cicero \(failure.release.version) and put it in place of this one yourself.")
        }
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: sharesUsageStatistics) {
            guard !sharesUsageStatistics else { return }
            UsageStatistics.forgetID()
        }
        .fontCacheSheet(isPresented: $isClearingCaches)
        .backupSheet(isPresented: $isBackingUp)
        .onAppear { loginItem = LoginItem.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = LoginItem.status
        }
    }

    private var updateStatus: String {
        if let switching = updates.switching { return switching.full }
        if let version = updates.readyVersion { return "Cicero \(version) is ready to install." }
        switch updates.status {
        case .idle: return updates.isNightly ? "Nightly version." : "Stable version."
        case .checking: return "Checking for updates"
        case .available(let version): return "Cicero \(version) is available."
        case .failed(let message): return "Couldn’t check for updates: \(message)"
        case .upToDate:
            if updates.isNightly, updates.track == .stable { return "Up to date. The next stable version replaces this nightly." }
            if !updates.isNightly, updates.track == .nightly { return "Up to date. The next nightly replaces this version." }
            return "Up to date."
        }
    }

    private func switchTo(_ release: Updates.Release) {
        guard model.job == nil else { return }
        Task {
            guard await model.saveSetupSnapshot(named: "Before Switching to \(release.version)", nothingWas: "changed") else { return }
            guard model.job == nil else { return }
            await updates.switchTo(release)
        }
    }

    private func switchTitle(_ release: Updates.Release) -> String {
        release.isNightly ? "Switch to Cicero \(release.version)?" : "Go back to Cicero \(release.version)?"
    }

    private func switchMessage(_ release: Updates.Release) -> String {
        let steps = "Cicero saves your setup to its Backups folder, replaces this version with Cicero \(release.version), and opens it again."
        return release.isNightly
            ? "No nightly is newer than this version. The latest nightly has new features, but may not have every fix this version has. \(steps)"
            : "No stable version is newer than this nightly. \(steps) Anything this nightly added to your setup that \(release.version) doesn’t know may be lost; the saved setup keeps it."
    }

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

    private var addingExplanation: String {
        let place = model.data.installsIntoFontLibrary ? "Cicero’s Library" : "your Fonts folder"
        return switch model.data.installMethod {
        case .ask: "Cicero asks whether to copy them into \(place), move them there or leave them where they are. Microsoft Office can’t use fonts left where they are."
        case .copy: "They’re copied into \(place) and activated. The originals stay where they are."
        case .move: "They’re moved into \(place) and activated. Fonts in your locations stay where they are."
        case .inPlace: "They’re listed under Added Fonts where they are, without being activated. Microsoft Office can’t use them."
        }
    }
}

private extension DuplicateHandling {
    var title: String {
        switch self {
        case .ask: "Ask Each Time"
        case .addCopy: "Add as a Copy"
        case .skip: "Skip"
        case .replace: "Replace Existing Copy"
        }
    }
}

private extension InstallMethod {
    func title(intoFontLibrary: Bool) -> String {
        switch self {
        case .ask: "Ask Each Time"
        case .copy: intoFontLibrary ? "Copy to Cicero’s Library" : "Copy to ~/Library/Fonts"
        case .move: intoFontLibrary ? "Move to Cicero’s Library" : "Move to ~/Library/Fonts"
        case .inPlace: "Leave Files in Place"
        }
    }
}
