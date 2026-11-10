import Foundation

public enum FontExportFormat: String, CaseIterable, Sendable {
    case folder, zip

    public var title: String {
        switch self {
        case .folder: "Folder"
        case .zip: "ZIP Archive"
        }
    }
}

public struct FontExportPlan: Sendable {
    public struct Item: Sendable {
        public var family: String
        public var paths: [String]
    }

    public var items: [Item]
    public var exportedFamilies: [String]
    public var protectedCount: Int

    public init(families: [Family], including: (Family, LibraryFace) -> Bool = { _, _ in true }) {
        var seen = Set<String>()
        var items: [Item] = []
        var exportedFamilies: [String] = []
        var protectedCount = 0
        for family in families {
            var paths: [String] = []
            var exported = false
            for face in family.faces where including(family, face) {
                let path = face.face.path
                if ActivationEngine.isProtected(path) {
                    if seen.insert(path).inserted { protectedCount += 1 }
                    continue
                }
                exported = true
                if seen.insert(path).inserted { paths.append(path) }
            }
            if exported { exportedFamilies.append(family.name) }
            if !paths.isEmpty { items.append(Item(family: family.name, paths: paths)) }
        }
        self.items = items
        self.exportedFamilies = exportedFamilies
        self.protectedCount = protectedCount
    }

    public var isEmpty: Bool { items.isEmpty }

    public var completionMessage: String {
        var message = "Exported " + (FontNames.describe(families: exportedFamilies) ?? "the fonts")
        if protectedCount > 0 {
            message += protectedCount == 1
                ? ". Left out 1 font file that comes with macOS or an app"
                : ". Left out \(protectedCount) font files that come with macOS or an app"
        }
        return message
    }
}

public struct FontExporter: Sendable {
    public var trash: @Sendable (URL) throws -> URL? = { url in
        var location: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &location)
        return location as URL?
    }

    public init() {}

    @concurrent
    public func export(_ plan: FontExportPlan, to destination: URL, format: FontExportFormat, keeping kept: [String] = []) async throws -> URL {
        let fm = FileManager.default
        // The exported files are kept too: replacing a folder that holds them would move the library's own fonts to the Trash.
        let replacement = try ItemReplacement(for: destination, keeping: kept + plan.items.flatMap(\.paths))
        defer { replacement.discard() }
        switch format {
        case .folder:
            try Self.copy(plan, into: replacement.staged)
        case .zip:
            let staging = fm.temporaryDirectory.appendingPathComponent("Cicero Export \(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            let folder = staging.appendingPathComponent(destination.deletingPathExtension().lastPathComponent, isDirectory: true)
            try Self.copy(plan, into: folder)
            try await Archive.zip(folder, to: replacement.staged)
        }
        try Task.checkCancellation()
        try replacement.commit(trash: trash)
        return destination
    }

    // An export or backup must never move any of these to the Trash to make room.
    public static func keptPaths(in library: Library, data: UserData, locations: Locations) -> [String] {
        var paths = [locations.userFonts.path, locations.allUsersFonts.path, locations.support.path, locations.inactiveFolder.path]
            + data.scannedFolders().map(\.path)
        for family in library.families {
            for face in family.faces { paths += [face.face.path] + face.otherCopies }
        }
        let records = data.records
        paths += records.inPlace
        paths += records.installedCopies.flatMap { [$0.key, $0.value] }
        paths += records.appFolderOrigins.flatMap { [$0.key, $0.value] }
        return paths
    }

    private static func copy(_ plan: FontExportPlan, into folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in plan.items {
            let target = plan.items.count == 1 ? folder : folder.appendingPathComponent(folderName(for: item.family), isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for path in item.paths {
                try Task.checkCancellation()
                let source = URL(fileURLWithPath: path, isDirectory: false)
                try fm.copyItem(at: ActivationEngine.realFile(source), to: ActivationEngine.uniqueURL(for: source.lastPathComponent, in: target))
            }
        }
    }

    static func folderName(for family: String) -> String {
        family.replacingOccurrences(of: "/", with: ":")
    }
}
