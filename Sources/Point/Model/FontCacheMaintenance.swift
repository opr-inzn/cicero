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

extension LibraryStore {
    /// Re-reads every font file instead of using Point's cached metadata.
    func rebuildFontList() {
        FaceCache.clear()
        rescan()
    }

    /// Returns true when the caches were cleared.
    func clearFontCaches(_ scope: FontCacheMaintenance.Scope) async -> Bool {
        do {
            try await FontCacheMaintenance.clear(scope)
            rebuildFontList()
            return true
        } catch FontCacheMaintenance.Failure.cancelled {
            return false
        } catch {
            showToast("Couldn't clear font caches: \(error.localizedDescription)")
            return false
        }
    }
}

/// The confirmation and follow-up restart prompt for clearing font caches, attachable to any window.
struct FontCacheDialogs: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Binding var isConfirming: Bool
    @State private var showsRestartPrompt = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Clear font caches?", isPresented: $isConfirming) {
                Button("Clear for My Account") { clear(.currentUser) }
                Button("Clear for All Users…") { clear(.allUsers) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use this when fonts look wrong, show an old version, or won't turn on or off. Clearing for all users needs an administrator password.")
            }
            .alert("Font caches cleared", isPresented: $showsRestartPrompt) {
                Button("Restart Now…") { FontCacheMaintenance.restartMac() }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Restart your Mac so every app picks up the rebuilt caches.")
            }
    }

    private func clear(_ scope: FontCacheMaintenance.Scope) {
        Task {
            if await library.clearFontCaches(scope) { showsRestartPrompt = true }
        }
    }
}
