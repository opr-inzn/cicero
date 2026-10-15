import Foundation

/// Why a watched folder's fonts are out of reach for now.
public enum FolderAvailability: Hashable, Sendable {
    /// It isn't there: its disk or server isn't connected, or it was moved, renamed or deleted.
    case notFound
    /// macOS doesn't let Cicero read it, as for a cloud folder Cicero wasn't allowed into.
    case noAccess

    /// nil when the folder can be read.
    public static func of(_ path: String) -> FolderAvailability? {
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == EACCES || errno == EPERM ? .noAccess : .notFound }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .notFound }
        // A cloud folder Cicero may not read can still be looked at; its contents can't.
        guard let directory = opendir(path) else { return errno == EACCES || errno == EPERM ? .noAccess : .notFound }
        closedir(directory)
        return nil
    }
}

/// Font files that are on the Mac only some of the time: on a disk or server that comes and goes, or in a
/// folder a cloud service (iCloud Drive, Dropbox, Google Drive) keeps in sync, which can leave a file online
/// only, its name on the Mac but not its contents.
public enum Reachability {
    /// The name of the disk a path is on when that's one under /Volumes that isn't connected, like a server
    /// or an external disk that was ejected.
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

    /// Whether a file is gone for good: deleted, or its folder moved. Not when macOS won't let Cicero look (it
    /// may well be there), nor when its disk isn't connected.
    public static func isGone(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) != 0 else { return false }
        return (errno == ENOENT || errno == ENOTDIR) && disconnectedVolume(of: path) == nil
    }

    /// Whether a cloud service has taken the file's contents off the Mac. Reading it would download it.
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

    /// Downloads online-only files by reading them, as an app opening them would, four at a time, and
    /// returns the ones that didn't download (offline, say). `progress` gets the number done so far. A file
    /// the cloud service hasn't brought down in two minutes counts as not downloaded.
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

    /// A coordinated read has the cloud service bring the file down first; reading it makes sure it's all there.
    private static func download(_ path: String, timeout: Duration) async -> Bool {
        let intent = NSFileAccessIntent.readingIntent(with: URL(fileURLWithPath: path, isDirectory: false), options: [])
        return await withCheckedContinuation { continuation in
            let answer = Answer(continuation)
            NSFileCoordinator().coordinate(with: [intent], queue: downloads) { error in
                answer.give(error == nil && (try? Data(contentsOf: intent.url)) != nil)
            }
            Task {
                try? await Task.sleep(for: timeout)
                answer.give(false)
            }
        }
    }

    /// Resumes a continuation with the first answer only: the download's, or the timeout's.
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
