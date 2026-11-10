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
        case unknown

        var text: String {
            switch self {
            case .command: "command\n"
            case .app(let name): "app\n\(name)\n\(Int(Date.now.timeIntervalSince1970))\n"
            case .unknown: ""
            }
        }

        init(text: String) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            switch lines.first {
            case "app" where lines.count > 1: self = .app(name: String(lines[1]))
            case "command": self = .command
            default: self = .unknown
            }
        }
    }

    public enum Attempt {
        case taken(AppLock)
        case held
        case unavailable
    }

    public static func attempt(support: URL, holder: Holder = .command) -> Attempt {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let path = url(support: support).path
        var descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        // One left by `sudo cicero` belongs to root and can only be replaced, once no one holds it: holding no lock, Cicero and the command could write at once.
        if descriptor < 0, errno == EACCES || errno == EPERM {
            let readOnly = open(path, O_RDONLY | O_CLOEXEC)
            guard readOnly >= 0 else { return .unavailable }
            defer { close(readOnly) }
            guard flock(readOnly, LOCK_EX | LOCK_NB) == 0 else { return errno == EWOULDBLOCK ? .held : .unavailable }
            guard isNamed(path, by: readOnly) else { return .held }
            if unlink(path) == 0 { descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644) }
        }
        guard descriptor >= 0 else { return .unavailable }
        // Still the file at that path once locked, or another process replaced it meanwhile, and the lock would be on a file no one else opens.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(descriptor)
            return error == EWOULDBLOCK ? .held : .unavailable
        }
        guard isNamed(path, by: descriptor) else {
            close(descriptor)
            return .held
        }
        let text = Array(holder.text.utf8)
        ftruncate(descriptor, 0)
        _ = pwrite(descriptor, text, text.count, 0)
        return .taken(AppLock(descriptor: descriptor))
    }

    private static func isNamed(_ path: String, by descriptor: Int32) -> Bool {
        var held = stat(), named = stat()
        return fstat(descriptor, &held) == 0 && stat(path, &named) == 0 && held.st_dev == named.st_dev && held.st_ino == named.st_ino
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
