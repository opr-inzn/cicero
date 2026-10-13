import CoreServices
import Foundation

/// Says when font files come or go in some folders (FSEvents), so the library follows files added or
/// removed in Finder. Events arrive on the main queue, coalesced over half a second. Use it from the
/// main thread only.
public final class FolderWatcher: @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var paths: [String] = []

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Watches these folders instead of the ones before.
    public func watch(_ paths: [String]) {
        guard paths != self.paths else { return }
        stop()
        self.paths = paths
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            if zip(paths, flags).contains(where: FolderWatcher.matters) { watcher.onChange() }
        }
        // WatchRoot: also when a watched folder itself is moved, deleted or comes back (a disk remounted).
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
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

    /// A font file, a folder (which may hold fonts), or a change FSEvents couldn't follow file by file.
    private static func matters(_ path: String, _ flags: FSEventStreamEventFlags) -> Bool {
        let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
        if flags & rescan != 0 { return true }
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 { return true }
        return FontFileReader.fontExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
