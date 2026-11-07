import Foundation

/// `app.lock` in Cicero's support folder, so one program at a time writes Cicero's data and moves its fonts: Cicero
/// holds it from launch until it quits, and the `cicero` command while it makes a change with Cicero closed. While
/// Cicero holds it, the command asks Cicero to make the change (see `Requests` in CiceroCommands). An advisory lock
/// (`flock`): macOS lets go of it when the program that holds it stops, also when it crashes.
public final class AppLock: @unchecked Sendable {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit { release() }

    public static func url(support: URL) -> URL {
        support.appendingPathComponent("app.lock", isDirectory: false)
    }

    /// What holds the lock, as written in the file by `take`: Cicero (by its name, for "Cicero (Beta)") or the command.
    public enum Holder: Equatable, Sendable {
        case command
        case app(name: String)

        var text: String {
            switch self {
            case .command: "command\n"
            case .app(let name): "app\n\(name)\n"
            }
        }

        init(text: String) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            self = lines.first == "app" && lines.count > 1 ? .app(name: String(lines[1])) : .command
        }
    }

    public enum Attempt {
        case taken(AppLock)
        /// Something else holds it.
        case held
        /// The file can't be made or opened, so no lock can be had at all.
        case unavailable
    }

    /// Takes the lock if nothing holds it, and writes who holds it in the file.
    public static func attempt(support: URL, holder: Holder = .command) -> Attempt {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let descriptor = open(url(support: support).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return .unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return .held
        }
        let text = Array(holder.text.utf8)
        ftruncate(descriptor, 0)
        _ = pwrite(descriptor, text, text.count, 0)
        return .taken(AppLock(descriptor: descriptor))
    }

    /// The lock, if nothing holds it; nil when something does, or the file can't be made.
    public static func take(support: URL, holder: Holder = .command) -> AppLock? {
        if case .taken(let lock) = attempt(support: support, holder: holder) { return lock }
        return nil
    }

    /// Who holds the lock, as the holder wrote it; worth asking only while `take` fails.
    public static func holder(support: URL) -> Holder {
        Holder(text: (try? String(contentsOf: url(support: support), encoding: .utf8)) ?? "")
    }

    /// The lock, once what holds it lets go, looking every 50 ms; nil when that takes longer than `timeout`.
    public static func wait(support: URL, timeout: Duration) -> AppLock? {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let lock = take(support: support) { return lock }
            if ContinuousClock.now >= deadline { return nil }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Whether something holds the lock now.
    public static func isHeld(support: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url(support: support).path) else { return false }
        guard let lock = take(support: support) else { return true }
        lock.release()
        return false
    }

    /// Lets go of it; the next `take` gets it.
    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
