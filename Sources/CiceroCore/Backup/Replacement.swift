import Foundation

public struct KeptItemError: Error, Sendable {
    public var name: String
    public var isFolder: Bool

    public var message: String {
        "“\(name)” \(isFolder ? "holds fonts Cicero uses" : "is a font Cicero uses"), so it wasn’t replaced. Choose another name or place"
    }
}

struct ItemReplacement {
    let destination: URL
    let staged: URL
    private let folder: URL
    private let kept: [String]

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

    func commit(trash: (URL) throws -> Void) throws {
        // The replaced item goes to the Trash, never under the new one, and never when it is, or holds, something Cicero must keep.
        try Self.check(destination, keeping: kept)
        if ActivationEngine.exists(destination.path) { try trash(destination) }
        try FileManager.default.moveItem(at: staged, to: destination)
    }

    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func check(_ destination: URL, keeping kept: [String]) throws {
        let path = destination.standardizedFileURL.path
        guard ActivationEngine.exists(path) else { return }
        let forms = Set([path, LibraryScanner.realPath(path)])
        func holds(_ item: String) -> Bool { forms.contains { item == $0 || item.hasPrefix($0 + "/") } }
        var resolvedFolders: [String: String] = [:]
        for item in kept {
            let parent = (item as NSString).deletingLastPathComponent
            let resolved: String
            if let known = resolvedFolders[parent] {
                resolved = known
            } else {
                resolved = LibraryScanner.realPath(parent)
                resolvedFolders[parent] = resolved
            }
            if holds(item) || holds(resolved + "/" + (item as NSString).lastPathComponent) {
                var isFolder: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
                throw KeptItemError(name: destination.lastPathComponent, isFolder: isFolder.boolValue)
            }
        }
    }
}
