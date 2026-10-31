import AppKit
import Combine
import CiceroCore
import SwiftUI

extension View {
    /// Presents the Clear Font Caches sheet, and offers a restart afterwards when macOS’s caches were cleared.
    func fontCacheSheet(isPresented: Binding<Bool>) -> some View {
        modifier(FontCacheSheetModifier(isPresented: isPresented))
    }
}

private struct FontCacheSheetModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var clearedSystemCaches = false
    @State private var isOfferingRestart = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                // The alert waits for the sheet to go away.
                guard clearedSystemCaches else { return }
                clearedSystemCaches = false
                isOfferingRestart = true
            } content: {
                FontCacheSheet { clearedSystemCaches = $0 }
            }
            .alert("Font Caches Cleared", isPresented: $isOfferingRestart) {
                Button("Restart Now") {
                    if !Self.restart() { model.showToast("Couldn’t restart. Choose Apple menu → Restart") }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Apps that are open keep using the old caches until you restart your Mac.")
            }
    }

    /// Asks loginwindow to restart, which asks apps to quit first; false when macOS refused.
    private static func restart() -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: "tell application \"loginwindow\" to «event aevtrrst»")?.executeAndReturnError(&error)
        return error == nil
    }
}

/// Which font caches to clear: macOS’s for this account or every user, Adobe’s and Office’s.
struct FontCacheSheet: View {
    /// Called before the sheet closes with whether macOS’s caches were cleared.
    let onCleared: (Bool) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var currentUser = true
    @State private var allUsers = false
    @State private var apps: Set<AppFontCaches.App> = []
    @State private var adobeCaches: AppFontCaches.Found?
    /// The name of a running app that reads each cache, while one is running.
    @State private var runningApps: [AppFontCaches.App: String] = [:]
    @State private var isClearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clear Font Caches").font(.title2.bold())
                Text("macOS and some apps keep lists of fonts that can go stale after fonts change. Clearing them makes the lists get rebuilt. You may need to restart your Mac afterwards.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                DetailToggle("macOS (my account)", detail: "Removes your account’s font caches and restarts the font service.", isOn: $currentUser)
                DetailToggle("macOS (all users)", detail: "Needs an administrator password.", isOn: $allUsers)
                DetailToggle("Adobe apps", detail: adobeDetail, isOn: includes(.adobe))
                    .disabled(runningApps[.adobe] != nil || adobeCaches?.isEmpty == true)
                DetailToggle("Microsoft Office", detail: officeDetail, isOn: includes(.office))
                    .disabled(runningApps[.office] != nil)
            }
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isClearing)
            HStack {
                if isClearing {
                    ProgressView().controlSize(.small)
                    Text("Clearing").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isClearing)
                Button("Clear") { clear() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isClearing || (!currentUser && !allUsers && apps.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            adobeCaches = await Task.detached(priority: .utility) { AppFontCaches.find(.adobe) }.value
        }
        .onReceive(NSWorkspace.shared.publisher(for: \.runningApplications)) { running in
            var names: [AppFontCaches.App: String] = [:]
            for app in AppFontCaches.App.allCases {
                names[app] = running.first { $0.bundleIdentifier.map(app.bundleIDs.contains) ?? false }?.localizedName
            }
            runningApps = names
        }
    }

    private func includes(_ app: AppFontCaches.App) -> Binding<Bool> {
        Binding(get: { apps.contains(app) }, set: { if $0 { apps.insert(app) } else { apps.remove(app) } })
    }

    private var adobeDetail: String {
        if let name = runningApps[.adobe] { return "Quit \(name) first." }
        guard let found = adobeCaches else { return "Looking for caches" }
        if found.isEmpty { return "No caches found." }
        return "Moves \(found.size.formatted(.byteCount(style: .file))) of cache files to the Trash."
    }

    private var officeDetail: String {
        if let name = runningApps[.office] { return "Quit \(name) first." }
        return "macOS asks for permission before Cicero looks inside Office’s folders."
    }

    private func clear() {
        isClearing = true
        var scopes: [SystemFontCaches.Scope] = []
        if currentUser { scopes.append(.currentUser) }
        if allUsers { scopes.append(.allUsers) }
        let chosen = AppFontCaches.App.allCases.filter { apps.contains($0) && runningApps[$0] == nil }
        Task {
            let cleared = await model.clearCaches(scopes: scopes, apps: chosen)
            onCleared(cleared)
            dismiss()
        }
    }
}
