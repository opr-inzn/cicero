import Darwin
import Foundation

/// Where Cicero runs from, and copying it into an Applications folder. A login item and Sparkle need a
/// copy that stays put: not one on a disk image (read-only, ejected later), in Downloads, or at the random
/// read-only path Gatekeeper's App Translocation runs a quarantined app from.
public enum AppLocation {
    public static let bundleName = "Cicero.app"

    /// /Applications, then ~/Applications.
    public static func applicationsFolders(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// Whether a bundle is in /Applications or ~/Applications, or a folder inside one of them.
    public static func isInApplicationsFolder(_ bundle: URL, home: URL) -> Bool {
        let path = bundle.standardizedFileURL.path
        return applicationsFolders(home: home).contains { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }

    /// What moving a copy of Cicero involves.
    public struct Move: Equatable, Sendable {
        /// Cicero.app in /Applications when the user can write there, otherwise in ~/Applications.
        public var destination: URL
        /// The copy the user opened, which goes to the Trash once it's copied: nil on a disk image or
        /// another read-only volume.
        public var originalToTrash: URL?
        /// The disk image it was opened from, detached once Cicero has quit.
        public var diskImageToDetach: URL?
    }

    /// - Parameters:
    ///   - original: the copy the user opened (see `originalURL(of:)`).
    ///   - volume: the volume it's on.
    public static func move(
        from original: URL, volume: URL?, volumeIsReadOnly: Bool, volumeIsDiskImage: Bool,
        home: URL, canWriteToApplications: Bool
    ) -> Move {
        let folders = applicationsFolders(home: home)
        let folder = canWriteToApplications ? folders[0] : folders[1]
        let onDiskImage = volumeIsDiskImage && volume != nil
        return Move(
            destination: folder.appendingPathComponent(bundleName, isDirectory: true),
            originalToTrash: onDiskImage || volumeIsReadOnly ? nil : original,
            diskImageToDetach: onDiskImage ? volume : nil
        )
    }

    /// The path a translocated app was opened from; any other URL as it is. The two functions are
    /// Security.framework SPI without a header, so they're looked up at run time.
    public static func originalURL(of bundle: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        typealias CreateOriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return bundle }
        defer { dlclose(security) }
        guard let isTranslocatedSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalPathSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return bundle }
        var isTranslocated = false
        guard unsafeBitCast(isTranslocatedSymbol, to: IsTranslocated.self)(bundle as CFURL, &isTranslocated, nil).boolValue,
              isTranslocated,
              let original = unsafeBitCast(originalPathSymbol, to: CreateOriginalPath.self)(bundle as CFURL, nil)
        else { return bundle }
        return original.takeRetainedValue() as URL
    }

    /// Copies a bundle to `destination`, putting anything already there in the Trash first, and takes the
    /// quarantine attribute off the copy, so Gatekeeper doesn't translocate it again.
    public static func install(
        _ bundle: URL, at destination: URL,
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try trash(destination) }
        try fm.copyItem(at: bundle, to: destination)
        removeQuarantine(destination)
    }

    /// Removes com.apple.quarantine from an item and everything inside it.
    public static func removeQuarantine(_ url: URL) {
        let inside = FileManager.default.enumerator(atPath: url.path)?.compactMap { $0 as? String } ?? []
        for path in [url.path] + inside.map({ url.appendingPathComponent($0).path }) {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}
