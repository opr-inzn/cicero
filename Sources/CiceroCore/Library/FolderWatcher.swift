import CoreServices
import Foundation

/// Says when font files come or go in some folders (FSEvents), so the library follows files added or
/// removed in Finder, and when some single files change. Events arrive on the main queue, coalesced over
/// half a second. Use it from the main thread only.
public final class FolderWatcher: @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var watched: [String] = []
    /// The watched folders, the folders watched only for files in them, and those files, symlinks resolved
    /// as FSEvents reports them.
    private var folders: [String] = []
    private var fileFolders: [String] = []
    private var files: Set<String> = []

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Watches these folders, and these files, instead of the ones before. A file is watched through its
    /// folder, which only says something when the file changes; files right in the home folder (or above
    /// it) aren't watched, as everything in it would go through the watcher.
    public func watch(_ paths: [String], files: [String] = []) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parents = Set(files.map { ($0 as NSString).deletingLastPathComponent }).filter { !(home + "/").hasPrefix($0 + "/") }
        let watched = paths + parents.sorted()
        guard watched != self.watched else { return }
        stop()
        self.watched = watched
        folders = paths.map { Self.realPath($0) + "/" }
        fileFolders = parents.map { Self.realPath($0) + "/" }
        self.files = Set(files.map(Self.realPath))
        guard !watched.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            if zip(paths, flags).contains(where: watcher.matters) { watcher.onChange() }
        }
        // WatchRoot: also when a watched folder itself is moved, deleted or comes back (a disk remounted).
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
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

    /// A font file, a folder (which may hold fonts), or a change FSEvents couldn't follow file by file; in a
    /// folder watched only for files in it, just those files.
    private func matters(_ path: String, _ flags: FSEventStreamEventFlags) -> Bool {
        let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
        if flags & rescan != 0 || files.contains(path) { return true }
        func isIn(_ folder: String) -> Bool { path.hasPrefix(folder) || path + "/" == folder }
        if fileFolders.contains(where: isIn), !folders.contains(where: isIn) { return false }
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 { return true }
        return FontFileReader.fontExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// The path with every symlink resolved, as FSEvents reports it (e.g. /private/var for /var); as it is
    /// when it doesn't exist.
    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
