import AppKit
import SwiftUI

/// Picks which font caches to clear: macOS's own, for this account or every user, and the ones
/// Adobe and Microsoft Office keep. App caches can't be cleared while those apps are open.
struct FontCacheSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// Called after clearing, with whether the macOS caches were among them.
    let onCleared: (Bool) -> Void

    @State private var macOSUser = true
    @State private var macOSAllUsers = false
    @State private var apps: Set<AppFontCaches.App> = []
    @State private var found: [AppFontCaches.App: AppFontCaches.Found] = [:]
    @State private var running: [AppFontCaches.App: [String]] = [:]
    @State private var isClearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear Font Caches")
                .font(.headline)
            Text("Use this when fonts look wrong, show an old version, or won't turn on or off. Apps rebuild their caches the next time they open.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                row("macOS (my account)", isOn: $macOSUser, detail: nil)
                row("macOS (all users)", isOn: $macOSAllUsers, detail: "Needs an administrator password")
                ForEach(AppFontCaches.App.allCases) { app in
                    row(app.title, isOn: binding(for: app), detail: detail(for: app))
                        .disabled(!canClear(app))
                }
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear") { clear() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isClearing || (!macOSUser && !macOSAllUsers && apps.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 440)
        .task { await refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunning()
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>, detail: String?) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for app: AppFontCaches.App) -> Binding<Bool> {
        Binding(
            get: { apps.contains(app) },
            set: { if $0 { apps.insert(app) } else { apps.remove(app) } }
        )
    }

    private func canClear(_ app: AppFontCaches.App) -> Bool {
        running[app]?.isEmpty != false && found[app]?.isEmpty == false
    }

    private func detail(for app: AppFontCaches.App) -> String {
        if let names = running[app], !names.isEmpty {
            return "Quit \(names.formatted(.list(type: .and))) first"
        }
        return found[app]?.summary ?? "Looking…"
    }

    private func refresh() async {
        refreshRunning()
        let results = await Task.detached(priority: .userInitiated) {
            AppFontCaches.App.allCases.map(AppFontCaches.find)
        }.value
        for result in results { found[result.app] = result }
    }

    private func refreshRunning() {
        for app in AppFontCaches.App.allCases {
            running[app] = AppFontCaches.runningApps(for: app)
            if !canClear(app) { apps.remove(app) }
        }
    }

    private func clear() {
        isClearing = true
        let selection = FontCacheSelection(
            scopes: (macOSUser ? [.currentUser] : []) + (macOSAllUsers ? [.allUsers] : []),
            apps: apps.compactMap { found[$0] }
        )
        Task {
            let clearedMacOS = await library.clearFontCaches(selection)
            isClearing = false
            dismiss()
            onCleared(clearedMacOS)
        }
    }
}
