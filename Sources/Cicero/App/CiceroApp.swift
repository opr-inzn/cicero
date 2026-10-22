import AppKit
import CiceroCore
import SwiftUI

@main
struct CiceroApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model: AppModel
    @State private var preview = PreviewSettings()
    @State private var backup = BackupPrompts()
    @State private var updates: Updates
    @State private var menuBarItem: MenuBarItem

    init() {
        let model = AppModel()
        let updates = Updates()
        let menuBarItem = MenuBarItem(model: model)
        _model = State(initialValue: model)
        _updates = State(initialValue: updates)
        _menuBarItem = State(initialValue: menuBarItem)
        // At launch rather than as the main window appears: Cicero can open without it, at login or in the menu bar.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Appearance.applySaved()
                model.appSets.start(model)
                model.openDocumentFonts.start(model)
                menuBarItem.start()
            }
        }
    }

    var body: some Scene {
        Window("Cicero", id: WindowID.main) {
            MainWindow()
                .environment(model)
                .environment(preview)
                .environment(backup)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    TextEditingKeys.install()
                    model.start()
                    ApplicationsFolder.checkAtLaunch(model: model)
                    delegate.model = model
                }
                // Fonts opened from the Finder (Open With, or a double-click when Cicero opens fonts): SwiftUI
                // hands the first of them here and the others to the delegate.
                .onOpenURL { model.open([$0]) }
        }
        .defaultSize(width: 1440, height: 900)
        .handlesExternalEvents(matching: ["*"])
        .commands { CiceroCommands(model: model, backup: backup, updates: updates, menuBarItem: menuBarItem) }

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
    let menuBarItem: MenuBarItem
    @Environment(\.openWindow) private var openWindow
    @FocusedBinding(\.compareSize) private var compareSize

    var body: some Commands {
        // The menu bar's commands are made at launch and have this even while no window is open.
        let _ = menuBarItem.connect(openWindow: openWindow)
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
            Button("Export Font List", systemImage: "tablecells") { model.exportFontListOfSelectionOrList() }
            Divider()
            Button("Back Up Library", systemImage: "externaldrive") { backup.isBackingUp = true }
            Button("Restore Library", systemImage: "clock.arrow.circlepath") { Task { backup.restoring = await model.chooseBackupToRestore() } }
            Divider()
            Button("Import from FontExplorer X", systemImage: "square.and.arrow.down") { model.importFromFontExplorer() }
            Button("Import from Font Book", systemImage: "square.and.arrow.down") { model.importFromFontBook() }
        }
        // Show Sidebar and Hide Sidebar, ⌃⌘S. Editing the sidebar is in its own menu and its Edit button.
        SidebarCommands()
        // Compare's size, while its window is in front, the one in its Preview Options. The menu bar matches ⌘+ to the
        // keyboard's own keys: ⌘= (or ⇧⌘=) on a US keyboard, the + key on a German one.
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                if let size = compareSize { compareSize = CompareWindow.bigger(than: size) }
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(compareSize.map { $0 >= CompareWindow.sizes.upperBound } ?? true)
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                if let size = compareSize { compareSize = CompareWindow.smaller(than: size) }
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(compareSize.map { $0 <= CompareWindow.sizes.lowerBound } ?? true)
        }
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
            // Several families start over; one joins those there, so families far apart in the library can be put
            // together one by one; none just opens the window.
            Button("Compare", systemImage: "rectangle.split.1x2") {
                if selection.count > 1 { model.compare(selection) } else { _ = model.addToCompare(selection.map(\.id)) }
                openWindow(id: WindowID.compare)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Show Similar Fonts", systemImage: "sparkle.magnifyingglass") { model.showSimilar(to: selection[0]) }
                .disabled(selection.count != 1 || !model.canShowSimilar(selection[0]))
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
/// Makes the Dock icon's menu, with Add Fonts, and counts the launch for the usage statistics.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the main window appears; files that come before wait for it, and so does Add Fonts in the Dock icon's menu.
    var model: AppModel? {
        didSet { flush() }
    }
    private var waiting: [URL] = []
    private var addsFonts = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageStatistics.sendLaunch()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        waiting += urls
        flush()
    }

    /// Above the system's items: Add Fonts, as in the File menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let addFonts = NSMenuItem(title: "Add Fonts", action: #selector(addFonts), keyEquivalent: "")
        addFonts.target = self
        menu.addItem(addFonts)
        return menu
    }

    /// Brings Cicero forward, which opens the main window when none shows, so the fonts added show there, and asks
    /// for them.
    @objc private func addFonts() {
        NSApp.bringForward()
        addsFonts = true
        flush()
    }

    private func flush() {
        guard let model else { return }
        if !waiting.isEmpty {
            model.open(waiting)
            waiting = []
        }
        if addsFonts {
            addsFonts = false
            // Not while the main window is still appearing: the panel runs a loop of its own.
            DispatchQueue.main.async { model.presentAddFontsPanel() }
        }
    }
}
