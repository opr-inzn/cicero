import Darwin
import Foundation

public enum AppLocation {
    public static let bundleName = "Cicero.app"

    public static func applicationsFolders(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appendingPathComponent("Applications", isDirectory: true)]
    }

    public static func isInApplicationsFolder(_ bundle: URL, home: URL) -> Bool {
        let path = bundle.standardizedFileURL.path
        return applicationsFolders(home: home).contains { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }

    public struct Move: Equatable, Sendable {
        public var destination: URL
        public var originalToTrash: URL?
        public var diskImageToDetach: URL?
    }

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

    public static func install(
        _ bundle: URL, at destination: URL,
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Copied beside it first: the Cicero there goes to the Trash only once there's a whole one to take its place.
        let copy = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.copyItem(at: bundle, to: copy)
            if fm.fileExists(atPath: destination.path) { try trash(destination) }
            try fm.moveItem(at: copy, to: destination)
        } catch {
            try? fm.removeItem(at: copy)
            throw error
        }
        // Without the quarantine attribute, or Gatekeeper translocates the copy again.
        removeQuarantine(destination)
    }

    public static func removeQuarantine(_ url: URL) {
        let inside = FileManager.default.enumerator(atPath: url.path)?.compactMap { $0 as? String } ?? []
        for path in [url.path] + inside.map({ url.appendingPathComponent($0).path }) {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}
