import Foundation

public struct KeptItemError: Error, Sendable {
    public var name: String
    public var isFolder: Bool
    public var noTrash = false

    public var message: String {
        if noTrash {
            return "“\(name)” \(isFolder ? "isn’t empty" : "is a font") and that disk has no Trash, so it wasn’t replaced. Choose another name or place"
        }
        return "“\(name)” \(isFolder ? "holds fonts Cicero uses" : "is a font Cicero uses"), so it wasn’t replaced. Choose another name or place"
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

    func commit(trash: (URL) throws -> URL?) throws {
        // The replaced item goes to the Trash, never under the new one, and never when it is, or holds, something Cicero must keep.
        try Self.check(destination, keeping: kept)
        let fm = FileManager.default
        var trashed: URL?
        if ActivationEngine.exists(destination.path) {
            do {
                trashed = try trash(destination)
            } catch let error where (error as? CocoaError)?.code == .featureUnsupported || !Self.hasTrash(for: destination) {
                try replaceWithoutTrash()
                return
            }
        }
        do {
            try fm.moveItem(at: staged, to: destination)
        } catch {
            if let trashed { try? fm.moveItem(at: trashed, to: destination) }
            throw error
        }
    }

    private func replaceWithoutTrash() throws {
        let fm = FileManager.default
        var info = stat()
        let isFolder = lstat(destination.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        let isLink = info.st_mode & S_IFMT == S_IFLNK
        // Deleted for good with no Trash to take it, so never a font, nor a folder with anything in it.
        let folderItems = isFolder ? ((try? fm.contentsOfDirectory(atPath: destination.path)) ?? [""]).filter { $0 != ".DS_Store" } : []
        let holdsFonts = !isLink && (isFolder ? !folderItems.isEmpty : FontFormat.fileExtensions.contains(destination.pathExtension.lowercased()))
        guard !holdsFonts else { throw KeptItemError(name: destination.lastPathComponent, isFolder: isFolder, noTrash: true) }
        let aside = destination.deletingLastPathComponent().appendingPathComponent(ActivationEngine.movingPrefix + UUID().uuidString)
        try fm.moveItem(at: destination, to: aside)
        do {
            try fm.moveItem(at: staged, to: destination)
        } catch {
            try? fm.moveItem(at: aside, to: destination)
            throw error
        }
        try? fm.removeItem(at: aside)
    }

    private static func hasTrash(for url: URL) -> Bool {
        (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)) != nil
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
