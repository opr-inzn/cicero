import Foundation
import Synchronization

public enum FolderAvailability: Hashable, Sendable {
    case notFound
    case disconnected(String)
    case noAccess

    public static func of(_ path: String) -> FolderAvailability? {
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == EACCES || errno == EPERM ? .noAccess : notFound(path) }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .notFound }
        // A cloud folder Cicero may not read can still be looked at; its contents can't.
        guard let directory = opendir(path) else { return errno == EACCES || errno == EPERM ? .noAccess : notFound(path) }
        closedir(directory)
        return nil
    }

    private static func notFound(_ path: String) -> FolderAvailability {
        Reachability.disconnectedVolume(of: path).map(FolderAvailability.disconnected) ?? .notFound
    }
}

public enum Reachability {
    public static func disconnectedVolume(of path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        let name = String(parts[1])
        var volume = stat(), volumes = stat()
        guard lstat("/Volumes/" + name, &volume) == 0 else { return name }
        // A folder left where the disk was mounted is on the same disk as /Volumes. (The startup disk is
        // there as a link.)
        guard volume.st_mode & S_IFMT == S_IFDIR, stat("/Volumes", &volumes) == 0 else { return nil }
        return volume.st_dev == volumes.st_dev ? name : nil
    }

    public static func isGone(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) != 0 else { return false }
        return (errno == ENOENT || errno == ENOTDIR) && disconnectedVolume(of: path) == nil
    }

    public static func isOnLocalDisk(_ path: String) -> Bool {
        var closest = (length: 0, isLocal: true)
        for mount in mounts() where mount.prefix.count > closest.length && path.hasPrefix(mount.prefix) {
            closest = (mount.prefix.count, mount.isLocal)
        }
        return closest.isLocal
    }

    private static func mounts() -> [(prefix: String, isLocal: Bool)] {
        let now = ContinuousClock.now
        if let listed = mountList.withLock({ $0 }), now - listed.at < .seconds(2) { return listed.mounts }
        // macOS's own list of mounted disks, which asks none of them: a server that stopped answering holds up whatever asks it anything.
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var entries: [statfs] = Array(repeating: .init(), count: Int(count))
        let listed = getfsstat(&entries, Int32(MemoryLayout<statfs>.stride * entries.count), MNT_NOWAIT)
        guard listed > 0 else { return [] }
        let mounts = entries.prefix(Int(listed)).map { entry in
            var entry = entry
            let point = withUnsafeBytes(of: &entry.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return (prefix: point.hasSuffix("/") ? point : point + "/", isLocal: entry.f_flags & UInt32(MNT_LOCAL) != 0)
        }
        mountList.withLock { $0 = (now, mounts) }
        return mounts
    }

    private static let mountList = Mutex<(at: ContinuousClock.Instant, mounts: [(prefix: String, isLocal: Bool)])?>(nil)

    public static func isOnlineOnly(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    private static let downloads: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Cicero downloads"
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    public static func download(_ paths: [String], progress: @escaping @Sendable (Int) -> Void) async -> [String] {
        await withTaskGroup(of: (String, Bool).self) { group in
            var pending = paths[...]
            func addNext() {
                guard let path = pending.popFirst() else { return }
                group.addTask { (path, await download(path, timeout: .seconds(120))) }
            }
            for _ in 0..<4 { addNext() }
            var failed: [String] = []
            var done = 0
            while let (path, downloaded) = await group.next() {
                done += 1
                if !downloaded { failed.append(path) }
                progress(done)
                addNext()
            }
            return failed.sorted()
        }
    }

    private static func download(_ path: String, timeout: Duration) async -> Bool {
        let intent = NSFileAccessIntent.readingIntent(with: URL(fileURLWithPath: path, isDirectory: false), options: [])
        return await withCheckedContinuation { continuation in
            let answer = Answer(continuation)
            // A coordinated read has the cloud service bring the file down first; reading it then makes sure it's all there.
            NSFileCoordinator().coordinate(with: [intent], queue: downloads) { error in
                answer.give(error == nil && (try? Data(contentsOf: intent.url)) != nil)
            }
            Task {
                try? await Task.sleep(for: timeout)
                answer.give(false)
            }
        }
    }

    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func give(_ value: Bool) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}
