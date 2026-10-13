import Foundation

/// Why an export or a backup didn't replace the item the save panel said to replace.
public struct KeptItemError: Error, Sendable {
    /// The item's name, e.g. "Fonts".
    public var name: String
    public var isFolder: Bool

    public var message: String {
        "“\(name)” \(isFolder ? "holds fonts Cicero uses" : "is a font Cicero uses"), so it wasn’t replaced. Choose another name or place."
    }
}

/// Where an export or a backup is written before it takes the place the save panel chose: a private
/// folder on the same disk. The new item moves into place only once it's complete, so a cancelled or
/// failed one leaves nothing behind and the item it replaces stays until then. That item goes to the
/// Trash, never under the new one, and never when it is, or holds, something Cicero must keep.
struct ItemReplacement {
    let destination: URL
    /// Where to write the new item: in the private folder, with the destination's name.
    let staged: URL
    private let folder: URL
    private let kept: [String]

    /// Fails before anything is written when the item at `destination` is, or holds, one of `kept`.
    init(for destination: URL, keeping kept: [String]) throws {
        try Self.check(destination, keeping: kept)
        let fm = FileManager.default
        // On the destination's disk, so moving the finished item there is instant and all at once.
        let folder = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination.deletingLastPathComponent(), create: true))
            ?? fm.temporaryDirectory.appendingPathComponent("Cicero \(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        self.destination = destination
        self.folder = folder
        self.kept = kept
        staged = folder.appendingPathComponent(destination.lastPathComponent, isDirectory: false)
    }

    /// Moves the finished item into place, after moving the one it replaces to the Trash.
    func commit(trash: (URL) throws -> Void) throws {
        try Self.check(destination, keeping: kept)
        if Self.exists(destination.path) { try trash(destination) }
        try FileManager.default.moveItem(at: staged, to: destination)
    }

    /// Removes the private folder and whatever is still in it; call when done, whether or not it was committed.
    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Throws when there's an item at `destination` that is one of `kept` or a folder holding one, by its path
    /// or the path symbolic links lead to.
    static func check(_ destination: URL, keeping kept: [String]) throws {
        let path = destination.standardizedFileURL.path
        guard exists(path) else { return }
        let forms = Set([path, realPath(path)])
        func holds(_ item: String) -> Bool { forms.contains { item == $0 || item.hasPrefix($0 + "/") } }
        var resolvedFolders: [String: String] = [:]
        for item in kept {
            let parent = (item as NSString).deletingLastPathComponent
            let resolved: String
            if let known = resolvedFolders[parent] {
                resolved = known
            } else {
                resolved = realPath(parent)
                resolvedFolders[parent] = resolved
            }
            if holds(item) || holds(resolved + "/" + (item as NSString).lastPathComponent) {
                var isFolder: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
                throw KeptItemError(name: destination.lastPathComponent, isFolder: isFolder.boolValue)
            }
        }
    }

    /// Whether anything is at the path, a symbolic link that leads nowhere included.
    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The path with every symbolic link resolved; the path itself when it doesn't exist.
    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
