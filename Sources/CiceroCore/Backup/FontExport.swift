import Foundation

/// A folder of font files, or a ZIP archive of one.
public enum FontExportFormat: String, CaseIterable, Sendable {
    case folder, zip

    public var title: String {
        switch self {
        case .folder: "Folder"
        case .zip: "ZIP Archive"
        }
    }
}

/// The files an export copies, worked out before the save panel: each face's own file once (a
/// collection shared by several faces, or families, once), with the files Cicero never touches
/// (macOS's fonts, fonts inside apps, Adobe Fonts) left out.
public struct FontExportPlan: Sendable {
    public struct Item: Sendable {
        public var family: String
        public var paths: [String]
    }

    /// Families with files to copy, in the order given.
    public var items: [Item]
    /// Families with at least one file in the export, including ones whose only file is in another family's folder.
    public var familyCount: Int
    /// Files left out because they come with macOS or an app.
    public var protectedCount: Int

    public init(families: [Family]) {
        var seen = Set<String>()
        var items: [Item] = []
        var familyCount = 0
        var protectedCount = 0
        for family in families {
            var paths: [String] = []
            var exported = false
            for face in family.faces {
                let path = face.face.path
                if ActivationEngine.isProtected(path) {
                    if seen.insert(path).inserted { protectedCount += 1 }
                    continue
                }
                exported = true
                if seen.insert(path).inserted { paths.append(path) }
            }
            if exported { familyCount += 1 }
            if !paths.isEmpty { items.append(Item(family: family.name, paths: paths)) }
        }
        self.items = items
        self.familyCount = familyCount
        self.protectedCount = protectedCount
    }

    public var isEmpty: Bool { items.isEmpty }
    public var fileCount: Int { items.reduce(0) { $0 + $1.paths.count } }

    /// "Exported 12 families." with a note about files left out, for a toast.
    public var completionMessage: String {
        var message = familyCount == 1 ? "Exported 1 family." : "Exported \(familyCount) families."
        if protectedCount > 0 {
            message += protectedCount == 1
                ? " Left out 1 font that comes with macOS or an app."
                : " Left out \(protectedCount) fonts that come with macOS or an app."
        }
        return message
    }
}

/// Copies font files into a folder, or a ZIP archive of one, for sending them to someone or a printer.
public struct FontExporter: Sendable {
    /// Moves the item the user chose to replace to the Trash. Tests replace it so they don't fill the user's Trash.
    public var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    public init() {}

    /// Writes the plan's files to `destination`: a folder (or, for `.zip`, an archive of one) with a
    /// subfolder per family, or the files themselves when there's one family. The save panel has
    /// already confirmed replacing an item at `destination`; it goes to the Trash first, never over.
    @concurrent
    public func export(_ plan: FontExportPlan, to destination: URL, format: FontExportFormat) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try trash(destination) }
        switch format {
        case .folder:
            do {
                try Self.copy(plan, into: destination)
            } catch {
                // Only ever a folder this export just made.
                try? fm.removeItem(at: destination)
                throw error
            }
        case .zip:
            let staging = fm.temporaryDirectory.appendingPathComponent("Cicero Export \(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            let folder = staging.appendingPathComponent(destination.deletingPathExtension().lastPathComponent, isDirectory: true)
            try Self.copy(plan, into: folder)
            try await Archive.zip(folder, to: destination)
        }
        return destination
    }

    /// Copies with FileManager, which clones on APFS. `folder` doesn't exist yet.
    private static func copy(_ plan: FontExportPlan, into folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in plan.items {
            let target = plan.items.count == 1 ? folder : folder.appendingPathComponent(folderName(for: item.family), isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for path in item.paths {
                try Task.checkCancellation()
                let source = URL(fileURLWithPath: path, isDirectory: false)
                try fm.copyItem(at: source, to: uniqueURL(for: source.lastPathComponent, in: target))
            }
        }
    }

    /// A family name as a folder name: Finder shows ":" as "/".
    static func folderName(for family: String) -> String {
        family.replacingOccurrences(of: "/", with: ":")
    }
}

/// "Name.otf", then "Name 2.otf", "Name 3.otf"…
func uniqueURL(for name: String, in folder: URL) -> URL {
    let fm = FileManager.default
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = folder.appendingPathComponent(name, isDirectory: false)
    var number = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)", isDirectory: false)
        number += 1
    }
    return candidate
}
