import Foundation

public final class AppLock: @unchecked Sendable {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit { release() }

    public static func url(support: URL) -> URL {
        support.appendingPathComponent("app.lock", isDirectory: false)
    }

    public enum Holder: Equatable, Sendable {
        case command
        case app(name: String)

        var text: String {
            switch self {
            case .command: "command\n"
            case .app(let name): "app\n\(name)\n\(Int(Date.now.timeIntervalSince1970))\n"
            }
        }

        init(text: String) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            self = lines.first == "app" && lines.count > 1 ? .app(name: String(lines[1])) : .command
        }
    }

    public enum Attempt {
        case taken(AppLock)
        case held
        case unavailable
    }

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

    public static func take(support: URL, holder: Holder = .command) -> AppLock? {
        if case .taken(let lock) = attempt(support: support, holder: holder) { return lock }
        return nil
    }

    public static func holder(support: URL) -> Holder {
        Holder(text: (try? String(contentsOf: url(support: support), encoding: .utf8)) ?? "")
    }

    public static func appStarted(support: URL) -> Date? {
        let lines = ((try? String(contentsOf: url(support: support), encoding: .utf8)) ?? "").split(separator: "\n")
        guard lines.first == "app", lines.count > 2, let seconds = TimeInterval(lines[2]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func wait(support: URL, timeout: Duration) async -> AppLock? {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let lock = take(support: support) { return lock }
            if ContinuousClock.now >= deadline || Task.isCancelled { return nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    public static func isHeld(support: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url(support: support).path) else { return false }
        guard let lock = take(support: support) else { return true }
        lock.release()
        return false
    }

    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
