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

    var body: some View {
        let set = model.data.sets.first { $0.id == setID }
        VStack(alignment: .leading, spacing: 14) {
            Text("Activate “\(set?.name ?? "")” with Apps").font(.title2.bold())
            Text("When one of these apps opens, Cicero activates the set’s fonts that are off, and deactivates them when the app quits. Fonts you turned on yourself stay on.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(set?.apps ?? []) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        if model.appSets.isRunning(app) {
                            Text("Open").foregroundStyle(.secondary)
                        }
                        Button("Remove \(app.name)", systemImage: "minus.circle") { model.removeApp(app.bundleID, from: setID) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.bordered)
            .frame(height: 150)
            .overlay {
                if set?.apps.isEmpty ?? true {
                    Text("No apps yet").foregroundStyle(.secondary)
                }
            }
            Button("Add App") { model.presentAppPicker(for: setID) }
            loginNote
            HStack {
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

    /// Application sets need Cicero to be open, so this offers to open it at login.
    @ViewBuilder
    private var loginNote: some View {
        HStack(alignment: .firstTextBaseline) {
            switch loginItem {
            case .enabled:
                Text("Cicero opens when you log in, so this works from the start.")
            case .requiresApproval:
                Text("Allow Cicero in Login Items to have it open when you log in.")
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            default:
                Text("This works while Cicero is open.")
                Spacer()
                Button("Open at Login") { loginItem = LoginItem.set(true, model: model) }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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
