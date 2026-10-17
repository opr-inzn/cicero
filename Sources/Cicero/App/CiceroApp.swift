import AppKit
import CiceroCore
import SwiftUI

@main
struct CiceroApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var preview = PreviewSettings()
    @State private var backup = BackupPrompts()
    @State private var updates = Updates()

    var body: some Scene {
        Window("Cicero", id: WindowID.main) {
            MainWindow()
                .environment(model)
                .environment(preview)
                .environment(backup)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    Appearance.applySaved()
                    TextEditingKeys.install()
                    model.start()
                    model.appSets.start(model)
                    ApplicationsFolder.checkAtLaunch(model: model)
                    delegate.model = model
                }
                // Fonts opened from the Finder (Open With, or a double-click when Cicero opens fonts): SwiftUI
                // hands the first of them here and the others to the delegate.
                .onOpenURL { model.open([$0]) }
        }
        .defaultSize(width: 1440, height: 900)
        .handlesExternalEvents(matching: ["*"])
        .commands { CiceroCommands(model: model, backup: backup, updates: updates) }

        Window("Character Toolbox", id: WindowID.toolbox) {
            ToolboxWindow()
                .environment(model)
                .environment(preview)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 660)
        .handlesExternalEvents(matching: [])

        Window("Compare", id: WindowID.compare) {
            CompareWindow()
                .environment(model)
                .environment(preview)
        }
        .defaultSize(width: 960, height: 640)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsWindow()
                .environment(model)
                .environment(preview)
                .environment(updates)
        }
    }
}

struct CiceroCommands: Commands {
    let model: AppModel
    let backup: BackupPrompts
    let updates: Updates
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cicero", systemImage: "info.circle") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
            Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
        }
        CommandGroup(after: .newItem) {
            Button("Add Fonts", systemImage: "doc.badge.plus") { model.presentAddFontsPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Add Folder", systemImage: "folder.badge.plus") { model.presentAddFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Find Fonts in Document", systemImage: "doc.text.magnifyingglass") { model.presentFindFontsPanel() }
            Button("New Set", systemImage: "square.stack") {
                model.prompt("New Set", confirm: "Create") { model.addSet(named: $0, with: model.selectedFamilies) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Smart Set", systemImage: "gearshape") { model.editingSmartSet = SmartSet(name: "") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Application Set", systemImage: "app.badge.checkmark") { model.newApplicationSet(with: model.selectedFamilies) }
            Divider()
            Button("Export Fonts", systemImage: "square.and.arrow.up") { model.exportSelectionOrList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Back Up Library", systemImage: "externaldrive") { backup.isBackingUp = true }
            Button("Restore Library", systemImage: "clock.arrow.circlepath") { Task { backup.restoring = await model.chooseBackupToRestore() } }
        }
        // Show Sidebar and Hide Sidebar, ⌃⌘S. Editing the sidebar is in its own menu and its Edit button.
        SidebarCommands()
        CommandMenu("Fonts") {
            let selection = model.selectedFamilies
            Button("Activate", systemImage: "checkmark.circle") { model.activate(selection) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!selection.contains(where: \.hasActivatable))
            Button("Activate Temporarily", systemImage: "clock") { model.activateTemporarily(selection) }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!selection.contains(where: \.hasTemporarilyActivatable))
            Button("Deactivate", systemImage: "circle.dashed") { model.deactivate(selection) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!selection.contains(where: \.hasDeactivatable))
            Divider()
            Button("Open", systemImage: "macwindow") { model.openFamilyID = selection.first?.id }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(selection.count != 1 || model.openFamilyID != nil)
            Button("Show Info", systemImage: "info.circle") { model.toggleInfo() }
                .keyboardShortcut("i", modifiers: .command)
            Button(model.quickLook.isOpen ? "Close Quick Look" : "Quick Look", systemImage: "eye") { model.quickLook.toggle() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(!model.quickLook.isOpen && (selection.isEmpty || model.openFamilyID != nil))
            Button("Reveal in Finder", systemImage: "finder") { model.reveal(selection) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(selection.isEmpty)
            Button("Move to Trash", systemImage: "trash") { model.requestTrash(selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selection.isEmpty)
            Divider()
            Button("Compare", systemImage: "rectangle.split.1x2") {
                model.compare(selection)
                openWindow(id: WindowID.compare)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(selection.count < 2)
            Button("Character Toolbox", systemImage: "character.textbox") { openWindow(id: WindowID.toolbox) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Rescan Library", systemImage: "arrow.clockwise") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Rebuild Font List", systemImage: "list.bullet.rectangle") { model.rebuildFontList() }
            Button("Clear Font Caches", systemImage: "eraser") { model.isClearingCaches = true }
        }
        // The user guide, the project's pages on GitHub and the privacy policy on the website, opened in the
        // default browser.
        CommandGroup(replacing: .help) {
            Button("Cicero Help", systemImage: "questionmark.circle") {
                NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/blob/main/help/README.md")!)
            }
            .keyboardShortcut("?", modifiers: .command)
            Button("Release Notes", systemImage: "doc.text") { NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/releases")!) }
            Button("Privacy Policy", systemImage: "hand.raised") { NSWorkspace.shared.open(URL(string: "https://cicero.maximilianinzinger.com/privacy")!) }
            Divider()
            Button("Report an Issue", systemImage: "exclamationmark.bubble") { NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/issues/new")!) }
        }
    }

    /// A link to Cicero's website under the version in the About panel. The panel puts the copyright
    /// (NSHumanReadableCopyright, "© 2026 Maximilian Inzinger") below it, so the name isn't repeated here.
    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: "cicero.maximilianinzinger.com", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
            .link: URL(string: "https://cicero.maximilianinzinger.com")!,
        ])
    }
}

/// Takes the files opened from the Finder that SwiftUI doesn't give the main window's `onOpenURL`: with several,
/// that gets the first and this the rest, at about the same time, and `AppModel.open` adds them together.
/// Also counts the launch for the usage statistics.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the main window appears; files that come before wait for it.
    var model: AppModel? {
        didSet { flush() }
    }
    private var waiting: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageStatistics.sendLaunch()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        waiting += urls
        flush()
    }

    private func flush() {
        guard let model, !waiting.isEmpty else { return }
        model.open(waiting)
        waiting = []
    }
}
