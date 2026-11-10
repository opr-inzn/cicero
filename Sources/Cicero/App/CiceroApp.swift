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
        WhatsNew.shared.noteLaunch()
        let model = AppModel()
        let updates = Updates()
        let menuBarItem = MenuBarItem(model: model)
        _model = State(initialValue: model)
        _updates = State(initialValue: updates)
        _menuBarItem = State(initialValue: menuBarItem)
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Appearance.applySaved()
                model.appSets.start(model)
                model.openDocumentFonts.start(model)
                menuBarItem.start()
                // After the lock's message, SwiftUI doesn't open the Library window at launch by itself.
                if LaunchWait.showedMessage {
                    DispatchQueue.main.async { menuBarItem.openWindow?(id: WindowID.main) }
                }
            }
        }
    }

    var body: some Scene {
        Window("Library", id: WindowID.main) {
            MainWindow()
                .environment(model)
                .environment(preview)
                .environment(backup)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    TextEditingKeys.install()
                    SearchTokenTint.install()
                    model.start()
                    ApplicationsFolder.checkAtLaunch(model: model)
                    delegate.model = model
                    #if CICERO_MEASURE
                    MeasureRun.startIfAsked(model: model, preview: preview)
                    #endif
                }
                // SwiftUI hands the first of the fonts opened from the Finder here and the others to the delegate.
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

        Window("What’s New in Cicero", id: WindowID.whatsNew) {
            WhatsNewWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .commandsRemoved()

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
    @Environment(\.openSettings) private var openSettings
    @FocusedBinding(\.compareSize) private var compareSize

    private var opensSelection: Bool { model.openFamilyID == nil && !model.shownSelection.isEmpty }

    var body: some Commands {
        // The menu bar's commands are made at launch and have these even while no window is open.
        let _ = menuBarItem.connect(openWindow: openWindow, openSettings: openSettings)
        CommandGroup(replacing: .appInfo) {
            Button("About Cicero", systemImage: "info.circle") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
            Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            if CommandLineTool.State.shared.installed {
                Button("Cicero CLI installed", systemImage: "checkmark") { CommandLineTool.install(model: model) }
            } else {
                Button("Install Cicero CLI", systemImage: "terminal") { CommandLineTool.install(model: model) }
            }
        }
        CommandGroup(after: .newItem) {
            Button("Add Fonts", systemImage: "doc.badge.plus") { model.presentAddFontsPanel() }
                .keyboardShortcut(opensSelection ? nil : KeyboardShortcut("o"))
            Button("Add Location", systemImage: "folder.badge.plus") { model.presentAddFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Find Fonts in Document", systemImage: "doc.text.magnifyingglass") { model.presentFindFontsPanel() }
            Button(model.selectedFamilies.isEmpty ? "New Folder" : "New Folder from Selection", systemImage: "folder") {
                model.prompt("New Folder", confirm: "Create") { model.addSet(named: $0, with: model.selectedFamilies) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Smart Folder", systemImage: "gearshape") { model.ask { $0.editingSmartSet = SmartSet(name: "") } }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button(model.selectedFamilies.isEmpty ? "New App Folder" : "New App Folder from Selection", systemImage: "app.badge.checkmark") {
                model.newApplicationSet(with: model.selectedFamilies)
            }
            Divider()
            Button("Import from FontExplorer X", systemImage: "square.and.arrow.down") { model.importFromFontExplorer() }
            Button("Import from Font Book", systemImage: "square.and.arrow.down") { model.importFromFontBook() }
            Button("Import from FontBase", systemImage: "square.and.arrow.down") { model.importFromFontBase() }
            Divider()
            Button("Export Fonts", systemImage: "square.and.arrow.up") { model.exportSelectionOrList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Back Up Library", systemImage: "externaldrive") { backup.isBackingUp = true }
            Button("Restore Library", systemImage: "clock.arrow.circlepath") { Task { backup.restoring = await model.chooseBackupToRestore() } }
        }
        SidebarCommands()
        // The menu bar matches ⌘+ to the keyboard's own keys: ⌘= (or ⇧⌘=) on a US keyboard, the + key on a German one.
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Back", systemImage: "chevron.backward") { model.openFamilyID = nil }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(model.openFamilyID == nil)
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
            Button("Activate", systemImage: "checkmark.seal") { model.activate(selection) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!selection.contains(where: \.hasActivatable))
            Button("Activate Temporarily", systemImage: "clock") { model.activateTemporarily(selection) }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!selection.contains(where: \.hasTemporarilyActivatable))
            Button("Deactivate", systemImage: "xmark.seal") { model.deactivate(selection) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!selection.contains(where: \.hasDeactivatable))
            Divider()
            Button("Open", systemImage: "macwindow") { model.openFamilyID = selection.first?.id }
                .keyboardShortcut(opensSelection ? KeyboardShortcut("o") : KeyboardShortcut(.downArrow))
                .disabled(selection.count != 1 || model.openFamilyID != nil)
            let hidesInfo = model.isInfoPresented && model.shownInfoTab == .info
            Button(hidesInfo ? "Hide Info" : "Show Info", systemImage: "info.circle") { model.toggleInfo() }
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
                if selection.count > 1 { model.compare(selection) } else { _ = model.addToCompare(selection.map(\.id)) }
                openWindow(id: WindowID.compare)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Show Similar Fonts", systemImage: "sparkle.magnifyingglass") {
                model.showSimilar(to: selection[0], style: model.shownStyle(of: selection[0]))
            }
            .disabled(selection.count != 1 || !model.canShowSimilar(selection[0], style: model.shownStyle(of: selection[0])))
            Button("Character Toolbox", systemImage: "character.textbox") { openWindow(id: WindowID.toolbox) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Rescan Library", systemImage: "arrow.clockwise") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Rebuild Library", systemImage: "list.bullet.rectangle") { model.rebuildFontList() }
            Button("Clear Font Caches", systemImage: "eraser") { model.ask { $0.isClearingCaches = true } }
        }
        CommandGroup(replacing: .help) {
            Button("Cicero Help", systemImage: "questionmark.circle") {
                NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/blob/main/help/README.md")!)
            }
            .keyboardShortcut("?", modifiers: .command)
            Button("What’s New in Cicero", systemImage: "newspaper") {
                if WhatsNew.shared.showLatest() { openWindow(id: WindowID.whatsNew) }
            }
            Button("Version History", systemImage: "doc.text") {
                NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/blob/main/help/version-history.md")!)
            }
            Button("Privacy Policy", systemImage: "hand.raised") { NSWorkspace.shared.open(URL(string: "https://cicero.maximilianinzinger.com/privacy")!) }
            Divider()
            Button("Report an Issue", systemImage: "exclamationmark.bubble") { NSWorkspace.shared.open(URL(string: "https://github.com/opr-inzn/cicero/issues/new")!) }
        }
    }

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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var model: AppModel? {
        didSet { flush() }
    }
    private var waiting: [URL] = []
    private var addsFonts = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageStatistics.sendLaunch()
        PreferencesItem.keepNamed()
        WindowList.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        waiting += urls
        flush()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let addFonts = NSMenuItem(title: "Add Fonts", action: #selector(addFonts), keyEquivalent: "")
        addFonts.target = self
        menu.addItem(addFonts)
        return menu
    }

    @objc private func addFonts() {
        NSApp.bringForward()
        addsFonts = true
        flush()
    }

    @objc func paste(_ sender: Any?) {
        if canPaste { model?.pasteFiles() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(paste(_:)) ? canPaste : true
    }

    private var canPaste: Bool {
        model != nil && NSApp.keyWindow != nil && NSApp.keyWindow === TextEditingKeys.mainWindow && !AppModel.pastedFiles.isEmpty
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

enum PreferencesItem {
    static let title = "Preferences"
    private static var observers: [NSObjectProtocol] = []
    private static var mainMenu: NSKeyValueObservation?

    static func keepNamed() {
        guard observers.isEmpty else { return }
        // SwiftUI names the item Settings… again whenever it updates a menu, and gives that title to whatever holds ⌘, (a command group of Cicero's own too).
        for name in [NSMenu.didChangeItemNotification, NSMenu.didAddItemNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                MainActor.assumeIsolated { rename() }
            })
        }
        // A main menu SwiftUI makes anew is put in place whole, without telling about its items.
        mainMenu = NSApp.observe(\.mainMenu) { _, _ in
            MainActor.assumeIsolated { rename() }
        }
        rename()
    }

    private static var appMenu: NSMenu? { NSApp.mainMenu?.items.first?.submenu }

    private static func rename() {
        for item in appMenu?.items ?? [] where item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command && item.title != title {
            item.title = title
        }
    }
}

enum WindowList {
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard observers.isEmpty else { return }
        let changes = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didChangeOcclusionStateNotification]
        for name in changes {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { update() }
            })
        }
        update()
    }

    private static func update() {
        for window in NSApp.windows where window.isVisible || window.isMiniaturized {
            guard let title = title(of: window) else { continue }
            if NSApp.windowsMenu?.items.contains(where: { $0.target === window }) ?? false {
                NSApp.changeWindowsItem(window, title: title, filename: false)
            } else {
                NSApp.addWindowsItem(window, title: title, filename: false)
            }
        }
    }

    private static func title(of window: NSWindow) -> String? {
        guard window.styleMask.contains(.titled), !(window is NSPanel), window.sheetParent == nil else { return nil }
        switch window.identifier?.rawValue {
        case WindowID.main: return "Library"
        case WindowID.compare: return "Compare"
        case WindowID.toolbox: return "Character Toolbox"
        case let id? where id.contains("Settings"): return PreferencesItem.title
        default: return window.title.isEmpty ? nil : window.title
        }
    }
}
