import AppKit
import CiceroCore
import ServiceManagement
import SwiftUI

/// The apps of an application set: while one of them is open, Cicero activates the set's fonts.
/// Changes apply as they're made.
struct AppSetEditor: View {
    let setID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loginItem = LoginItem.status
    @State private var selection: Set<String> = []

    var body: some View {
        let set = model.data.sets.first { $0.id == setID }
        VStack(alignment: .leading, spacing: 14) {
            Text("Activate “\(set?.name ?? "")” with Apps").font(.title2.bold())
            Text("When one of these apps opens, Cicero activates the set’s fonts that are off, and deactivates them when the app quits. Fonts you turned on yourself stay on. This works while Cicero is open.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(selection: $selection) {
                ForEach(Array((set?.apps ?? []).enumerated()), id: \.element.bundleID) { index, app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        if model.appSets.isRunning(app) {
                            Text("Open").foregroundStyle(.secondary)
                        }
                    }
                    .cardRow(index)
                }
            }
            .overlay {
                if set?.apps.isEmpty ?? true {
                    Text("No apps yet").foregroundStyle(.secondary)
                }
            }
            .inCard(
                add: CardListButton(title: "Add App", help: "Add the apps that need this set’s fonts") { model.presentAppPicker(for: setID) },
                remove: CardListButton(title: "Remove Apps", help: "Remove the selected apps") {
                    for bundleID in selection { model.removeApp(bundleID, from: setID) }
                    selection = []
                },
                canRemove: !selection.isEmpty
            )
            .frame(height: 170)
            HStack {
                loginToggle
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = LoginItem.status
        }
    }

    /// Application sets need Cicero to be open, so this offers to open it at login, next to Done.
    @ViewBuilder
    private var loginToggle: some View {
        Toggle("Open Cicero at login", isOn: Binding(
            get: { loginItem == .enabled || loginItem == .requiresApproval },
            set: { loginItem = LoginItem.set($0, model: model) }
        ))
        .toggleStyle(.checkbox)
        if loginItem == .requiresApproval {
            Button("Allow in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                .buttonStyle(.link)
        }
    }
}

/// Opening Cicero when the user logs in, so application sets work from the start.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Returns the status afterwards. Outside the Applications folder, turning it on offers to move Cicero
    /// there instead: a login item for a copy on a disk image or in Downloads breaks once that copy goes.
    static func set(_ enabled: Bool, model: AppModel) -> SMAppService.Status {
        if enabled, !ApplicationsFolder.isInApplicationsFolder {
            ApplicationsFolder.offerToMove(forOpenAtLogin: true)
            return status
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.showToast(enabled ? "Couldn’t add Cicero to your login items" : "Couldn’t remove Cicero from your login items")
        }
        return status
    }
}
