import AppKit
import CiceroCore
import SwiftUI

/// Cicero's icon in the menu bar, while Settings → General → Show Cicero in the menu bar is on (it is at first). A click
/// opens the main window. A right-click, a click with two fingers or a Control-click opens a menu: the fonts on for open
/// apps and until Cicero quits, the sets as the sidebar lists them, the switch for auto-activating fonts in Adobe apps,
/// and Quit. VoiceOver's Show Menu action opens it too. The sets are in the menu itself, not
/// a submenu: an item of a submenu can't bring Cicero to the front, as asking how to activate needs.
///
/// With the icon there, Show Cicero in the Dock can be off: Cicero is then in the Dock and the app switcher only while
/// one of its windows is open, so its menus and shortcuts are there while it's used, and leaves them when the last
/// one closes.
final class MenuBarItem: NSObject, NSMenuDelegate {
    static let showsIconKey = "menuBar.showsIcon"
    static let showsDockIconKey = "menuBar.showsDockIcon"

    /// Handed over by `CiceroCommands`, whose environment has it even while no window is open.
    var openWindow: OpenWindowAction?

    private let model: AppModel
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        defaults.register(defaults: [Self.showsIconKey: true, Self.showsDockIconKey: true])
        menu.delegate = self
    }

    /// Hands over the window action; returns nothing, so `CiceroCommands` can call it as it's made.
    func connect(openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    /// At launch.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // The switches in Settings write to the defaults.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        // A window that closes is still there as this comes. Menus are windows too, without a title bar: one closing as
        // its item opens a window would count before that window shows.
        let windowChanges = [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSApplication.didUnhideNotification]
        for name in windowChanges {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard (note.object as? NSWindow)?.styleMask.contains(.titled) ?? true else { return }
                Task { @MainActor in self?.updateDockIcon() }
            })
        }
        update()
    }

    private var showsIcon: Bool { defaults.bool(forKey: Self.showsIconKey) }

    /// Whether Cicero leaves the Dock while none of its windows is open: only with the icon in the menu bar, so it can
    /// always be found.
    private var hidesDockIcon: Bool { showsIcon && !defaults.bool(forKey: Self.showsDockIconKey) }

    private func update() {
        if showsIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Cicero"
            if let button = item.button {
                button.image = MenuBarIcon.image(height: 17)
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Show Menu") { [weak self] in
                    self?.showMenu()
                    return true
                }])
            }
            statusItem = item
        } else if !showsIcon, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        updateDockIcon()
    }

    private func updateDockIcon() {
        // Hidden with ⌘H, its windows aren't visible but still there.
        guard !NSApp.isHidden else { return }
        let hasWindow = NSApp.windows.contains { $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = hidesDockIcon && !hasWindow ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // The last window closed: back to the app that was in front before, rather than Cicero with nothing to show.
        if policy == .accessory, NSApp.isActive { NSApp.hide(nil) }
    }

    // MARK: Clicks

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            bringForward { openWindow?(id: WindowID.main) }
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        // Only for this click: with a menu, a click would open it rather than the window.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Opens a window and brings Cicero to the front, in the Dock and with its menus. macOS 26 turns down an app's own
    /// request to come forward, even from a click on its icon in the menu bar (`NSApp.activate()` and
    /// `NSRunningApplication.activate`, checked with real clicks), so Cicero also asks Launch Services, as the Dock does.
    /// That sends Cicero a reopen, which opens the main window only when no other window shows.
    private func bringForward(_ open: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate()
        open()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // This copy, as it runs: brought forward rather than opened again.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = statusLines()
        for title in status {
            let line = menuItem(title, action: nil)
            line.isEnabled = false
            menu.addItem(line)
        }
        if !status.isEmpty { menu.addItem(.separator()) }
        let sets = setItems()
        if !sets.isEmpty {
            menu.addItem(.sectionHeader(title: "Sets"))
            for item in sets { menu.addItem(item) }
            menu.addItem(.separator())
        }
        let documentFonts = menuItem("Auto-activate Fonts in Adobe Apps", action: #selector(toggleDocumentFonts))
        documentFonts.state = model.data.activatesDocumentFonts ? .on : .off
        menu.addItem(documentFonts)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Cicero", action: #selector(quit)))
    }

    private func menuItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// "Inter and Roboto on for InDesign", a line for each open app with fonts on for it (its application sets', and
    /// its documents'), then "12 families on until Cicero quits".
    private func statusLines() -> [String] {
        let session = ActivationEngine.currentSession()
        let temporary = model.data.records.temporary.filter { $0.value.session == session }
        guard !temporary.isEmpty else { return [] }
        // A file can have several styles: a collection's, or a variable font's named ones.
        var faces: [String: [LibraryFace]] = [:]
        for face in model.library.families.lazy.flatMap(\.faces) where temporary[face.face.path] != nil {
            faces[face.face.path, default: []].append(face)
        }
        var forApps: [String: [LibraryFace]] = [:]
        var untilQuit: [LibraryFace] = []
        for (path, record) in temporary {
            let inFile = faces[path] ?? []
            switch record.scope {
            case .untilQuit: untilQuit += inFile
            case .whileAppsRun: for app in record.apps ?? [] { forApps[app, default: []] += inFile }
            }
        }
        var lines = forApps.compactMap { app, faces -> String? in
            guard let name = appName(app), let fonts = FontNames.describe(faces) else { return nil }
            return "\(fonts) on for \(name)"
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let fonts = FontNames.describe(untilQuit) { lines.append("\(fonts) on until Cicero quits") }
        return lines
    }

    /// nil for an app that isn't open.
    private func appName(_ bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }

    /// The sets and smart sets the sidebar shows, in its order, checked when all their fonts are on.
    private func setItems() -> [NSMenuItem] {
        guard model.isVisible(SidebarSection.sets.key) else { return [] }
        return model.rows(for: .sets).filter { model.isVisible($0.key) }.map { row in
            let item = menuItem(row.title, action: #selector(toggleSet))
            let faces = model.faces(in: row.item)
            let on = faces.count { $0.position == .on }
            item.state = on == 0 ? .off : on == faces.count ? .on : .mixed
            item.isEnabled = !faces.isEmpty
            item.representedObject = row
            return item
        }
    }

    // MARK: Actions

    /// Turns a set's fonts off when they're all on, and on otherwise.
    @objc private func toggleSet(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? SidebarRow else { return }
        if sender.state == .on {
            model.deactivateFonts(in: row.item)
        } else {
            model.activateFonts(in: row.item, named: row.title)
        }
        // Asking how to activate, or whether to turn on so many, happens in the main window.
        if model.activationPrompt != nil || model.manyActivationPrompt != nil {
            bringForward { openWindow?(id: WindowID.main) }
        }
    }

    @objc private func toggleDocumentFonts() {
        model.data.activatesDocumentFonts.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
