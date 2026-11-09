import CoreServices
import Foundation

public final class FolderWatcher: @unchecked Sendable {
    private let onChange: @Sendable (Set<String>?) -> Void
    private var stream: FSEventStreamRef?
    private var watched: [String] = []
    private var folders: [String] = []
    private var fileFolders: [String] = []
    private var files: Set<String> = []
    private var hiddenFolders: [String] = []
    private var aliases: [(resolved: String, given: String)] = []

    public init(onChange: @escaping @Sendable (Set<String>?) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func watch(_ paths: [String], files: [String] = [], hidden: [String] = []) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parents = Set(files.map { ($0 as NSString).deletingLastPathComponent }).filter { !(home + "/").hasPrefix($0 + "/") }
        let watched = paths + hidden + parents.sorted()
        guard watched != self.watched else { return }
        stop()
        self.watched = watched
        // Every symlink resolved, as FSEvents reports paths (e.g. /private/var for /var).
        folders = (paths + hidden).map { LibraryScanner.realPath($0) + "/" }
        hiddenFolders = hidden.map { LibraryScanner.realPath($0) + "/" }
        fileFolders = parents.map { LibraryScanner.realPath($0) + "/" }
        self.files = Set(files.map(LibraryScanner.realPath))
        aliases = Set(watched).map { (LibraryScanner.realPath($0) + "/", $0 + "/") }.sorted { $0.resolved.count > $1.resolved.count }
        guard !watched.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            var changed: Set<String>? = []
            var matters = false
            for (path, flag) in zip(paths, flags) where watcher.matters(path, flag) {
                matters = true
                if let given = watcher.followed(path, flag) { changed?.insert(given) } else { changed = nil }
            }
            if matters { watcher.onChange(changed) }
        }
        // WatchRoot: also when a watched folder itself is moved, deleted or comes back (a disk remounted).
        // NoDefer: an event on its own comes at once rather than half a second later.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, watched as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func matters(_ path: String, _ flags: FSEventStreamEventFlags) -> Bool {
        let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
        if flags & rescan != 0 || files.contains(path) { return true }
        func isIn(_ folder: String) -> Bool { path.hasPrefix(folder) || path + "/" == folder }
        if fileFolders.contains(where: isIn), !folders.contains(where: isIn) { return false }
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix(".") || hiddenFolders.contains(where: isIn) else { return false }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 { return true }
        return FontFileReader.fontExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private func followed(_ path: String, _ flags: FSEventStreamEventFlags) -> String? {
        let whole = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemIsSymlink
        )
        guard flags & whole == 0, flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0,
              let alias = aliases.first(where: { path.hasPrefix($0.resolved) })
        else { return nil }
        return alias.given + path.dropFirst(alias.resolved.count)
    }
}
