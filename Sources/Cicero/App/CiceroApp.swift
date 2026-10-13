import AppKit
import CiceroCore
import SwiftUI

@main
struct CiceroApp: App {
    @State private var model = AppModel()
    @State private var preview = PreviewSettings()
    @State private var backup = BackupPrompts()

    var body: some Scene {
        Window("Cicero", id: WindowID.main) {
            MainWindow()
                .environment(model)
                .environment(preview)
                .environment(backup)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    Appearance.applySaved()
                    model.start()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { CiceroCommands(model: model, backup: backup) }

        Window("Character Toolbox", id: WindowID.toolbox) {
            ToolboxWindow()
                .environment(model)
                .environment(preview)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 660)

        Window("Compare", id: WindowID.compare) {
            CompareWindow()
                .environment(model)
                .environment(preview)
        }
        .defaultSize(width: 960, height: 640)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            SettingsWindow()
                .environment(model)
                .environment(preview)
        }
    }
}

struct CiceroCommands: Commands {
    let model: AppModel
    let backup: BackupPrompts
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cicero") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
        }
        CommandGroup(after: .newItem) {
            Button("Add Folder…") { model.presentAddFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("New Set…") {
                model.prompt("New Set", confirm: "Create") { model.addSet(named: $0, with: model.selectedFamilies) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Smart Set…") { model.editingSmartSet = SmartSet(name: "") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Export Fonts…") { model.exportSelectionOrList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Back Up Library…") { backup.isBackingUp = true }
            Button("Restore Library…") { Task { backup.restoring = await model.chooseBackupToRestore() } }
        }
        CommandGroup(after: .sidebar) {
            Button(model.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") {
                withAnimation(.snappy) { model.isEditingSidebar.toggle() }
            }
            Divider()
        }
        CommandMenu("Fonts") {
            let selection = model.selectedFamilies
            Button("Activate") { model.activate(selection) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!selection.contains(where: \.hasActivatable))
            Menu("Activate Temporarily") {
                ForEach(TemporaryScope.allCases, id: \.self) { scope in
                    Button(scope.menuTitle) { model.activateTemporarily(selection, scope: scope) }
                        .keyboardShortcut(scope == .untilQuit ? KeyboardShortcut(.return, modifiers: [.command, .option]) : nil)
                }
            }
            .disabled(!selection.contains(where: \.hasActivatable))
            Button("Deactivate") { model.deactivate(selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!selection.contains(where: \.hasDeactivatable))
            Divider()
            Button("Open") { model.openFamilyID = selection.first?.id }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(selection.count != 1 || model.openFamilyID != nil)
            Button("Show Info") { model.toggleInfo() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Reveal in Finder") { model.reveal(selection) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(selection.isEmpty)
            Button("Move to Trash…") { model.requestTrash(selection) }
                .disabled(selection.isEmpty)
            Divider()
            Button("Compare") {
                model.compare(selection)
                openWindow(id: WindowID.compare)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(selection.count < 2)
            Button("Character Toolbox") { openWindow(id: WindowID.toolbox) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Rescan Library") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Rebuild Font List") { model.rebuildFontList() }
            Button("Clear Font Caches…") { model.isClearingCaches = true }
        }
    }

    /// "Built by Maximilian Inzinger" under the version in the About panel, the name linking to the website.
    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "Built by ", attributes: base)
        var link = base
        link[.link] = URL(string: "https://maximilianinzinger.com")!
        credits.append(NSAttributedString(string: "Maximilian Inzinger", attributes: link))
        return credits
    }
}
