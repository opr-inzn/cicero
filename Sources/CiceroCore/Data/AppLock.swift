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

    /// The lock, if nothing holds it; nil when something does, or the file can't be made.
    public static func take(support: URL) -> AppLock? {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let descriptor = open(url(support: support).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return AppLock(descriptor: descriptor)
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
