import AppKit
import SwiftUI

/// Clearing the font caches macOS keeps, for when fonts render wrongly, show an old version, or
/// won't turn on or off.
enum FontCacheMaintenance {
    enum Scope {
        case currentUser
        case allUsers
    }

    enum Failure: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Cancelled."
            case .failed(let message): message.isEmpty ? "The command failed." : message
            }
        }
    }

    /// Removes the caches and restarts the font service, which rebuilds them on demand.
    /// Clearing for all users needs an administrator; macOS asks for the password itself.
    static func clear(_ scope: Scope) async throws {
        switch scope {
        case .currentUser:
            try await run("/usr/bin/atsutil", ["databases", "-removeUser"])
            try? await run("/usr/bin/killall", ["fontd"])
        case .allUsers:
            let command = "/usr/bin/atsutil databases -remove; /usr/bin/killall fontd || true"
            try await run("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
        }
    }

    /// Shows the standard restart confirmation, as if chosen from the Apple menu.
    static func restartMac() {
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevtrrst»")?.executeAndReturnError(nil)
    }

    private static func run(_ path: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else {
                    continuation.resume()
                    return
                }
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // osascript reports a cancelled password prompt as error -128.
                continuation.resume(throwing: message.contains("-128") ? Failure.cancelled : Failure.failed(message))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// What the Clear Font Caches sheet asked for.
struct FontCacheSelection {
    var scopes: [FontCacheMaintenance.Scope] = []
    var apps: [AppFontCaches.Found] = []
}

extension LibraryStore {
    /// Re-reads every font file instead of using Point's cached metadata.
    func rebuildFontList() {
        FaceCache.clear()
        rescan()
    }

    /// Clears the chosen caches: app caches go to the Trash, macOS ones through atsutil. Returns true
    /// when any of the macOS caches were cleared, which is when a restart helps.
    func clearFontCaches(_ selection: FontCacheSelection) async -> Bool {
        var trashed: [String] = []
        var failures = 0
        for found in selection.apps where !found.isEmpty {
            failures += await Task.detached { AppFontCaches.trash(found) }.value
            trashed.append(found.app.title)
        }
        var clearedMacOS = false
        for scope in selection.scopes {
            do {
                try await FontCacheMaintenance.clear(scope)
                clearedMacOS = true
            } catch FontCacheMaintenance.Failure.cancelled {
            } catch {
                showToast("Couldn't clear the macOS font caches: \(error.localizedDescription)")
            }
        }
        if failures > 0 {
            showToast("Couldn't move \(failures == 1 ? "1 cache item" : "\(failures) cache items") to the Trash.")
        } else if !trashed.isEmpty && !clearedMacOS {
            showToast("Moved the \(trashed.formatted(.list(type: .and))) font caches to the Trash.")
        }
        if clearedMacOS || !trashed.isEmpty { rebuildFontList() }
        return clearedMacOS
    }
}

/// The Clear Font Caches sheet and its follow-up restart prompt, attachable to any window.
struct FontCacheDialogs: ViewModifier {
    @Binding var isConfirming: Bool
    @State private var showsRestartPrompt = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isConfirming) {
                FontCacheSheet { clearedMacOS in
                    if clearedMacOS { showsRestartPrompt = true }
                }
            }
            .alert("Font caches cleared", isPresented: $showsRestartPrompt) {
                Button("Restart Now…") { FontCacheMaintenance.restartMac() }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Restart your Mac so every app picks up the rebuilt caches.")
            }
    }
}
