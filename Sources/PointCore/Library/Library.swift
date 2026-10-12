import Foundation

/// Where Point keeps and finds things.
public struct Locations: Sendable {
    /// ~/Library/Application Support/Point
    public var support: URL
    /// ~/Library/Caches/Point
    public var caches: URL
    /// ~/Library/Fonts
    public var userFonts: URL
    /// /Library/Fonts
    public var allUsersFonts: URL

    public init(support: URL, caches: URL, userFonts: URL, allUsersFonts: URL) {
        self.support = support
        self.caches = caches
        self.userFonts = userFonts
        self.allUsersFonts = allUsersFonts
    }

    public static var standard: Locations {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return Locations(
            support: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Point", isDirectory: true),
            caches: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Point", isDirectory: true),
            userFonts: home.appendingPathComponent("Library/Fonts", isDirectory: true),
            allUsersFonts: URL(fileURLWithPath: "/Library/Fonts", isDirectory: true)
        )
    }

    /// Fonts Point moved out of ~/Library/Fonts because it had no other copy.
    public var deactivated: URL { support.appendingPathComponent("Deactivated", isDirectory: true) }
}

/// An immutable snapshot of every font Point knows about, built off the main thread by
/// `LibraryScanner` with everything views need precomputed.
public struct Library: Sendable {
    /// Sorted by name (Finder order).
    public let families: [Family]
    /// Font files CoreText couldn't read.
    public let unreadableFiles: [String]
    /// Every file macOS currently has active.
    public let activePaths: Set<String>
    /// Changes whenever anything visible about the library changes (files, stamps, states, folders).
    public let fingerprint: Int

    public init(families: [Family], unreadableFiles: [String], activePaths: Set<String>, fingerprint: Int) {
        self.families = families
        self.unreadableFiles = unreadableFiles
        self.activePaths = activePaths
        self.fingerprint = fingerprint
        var index: [String: Int] = [:]
        for (position, family) in families.enumerated() { index[family.id] = position }
        self.index = index
        searchText = families.map { family in
            ([family.name, family.manufacturer ?? ""] + family.faces.map(\.face.postScriptName)).joined(separator: " ").lowercased()
        }
    }

    public static let empty = Library(families: [], unreadableFiles: [], activePaths: [], fingerprint: 0)

    private let index: [String: Int]
    private let searchText: [String]

    public func family(_ id: String) -> Family? {
        index[id].map { families[$0] }
    }

    public func position(of id: String) -> Int? { index[id] }

    /// Whether a family matches a search: name, foundry or a PostScript name contains the (lowercased) query.
    public func matches(_ family: Family, search lowercasedQuery: String) -> Bool {
        guard !lowercasedQuery.isEmpty, let position = index[family.id] else { return true }
        return searchText[position].contains(lowercasedQuery)
    }
}

public enum ScanProgress: Sendable, Equatable {
    case finding
    case identifying(done: Int, total: Int)
}

/// What a scan needs to know besides the disk.
public struct ScanInput: Sendable {
    public var folders: [WatchedFolder]
    public var records: ActivationRecords

    public init(folders: [WatchedFolder], records: ActivationRecords) {
        self.folders = folders
        self.records = records
    }
}

/// Finds every font file (CoreText's active fonts, ~/Library/Fonts, /Library/Fonts, the watched
/// folders and Point's Deactivated folder), reads new or changed files, and builds a `Library`.
/// Parsed faces and Date Added are cached in `Locations.caches` by path, modification date and size;
/// the decoded cache stays in memory between scans. Cancellation stops it between phases.
public final class LibraryScanner: Sendable {
    public init(locations: Locations) {
        fatalError("Implemented in PointCore")
    }

    public func scan(_ input: ScanInput, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Library {
        fatalError("Implemented in PointCore")
    }

    /// Forgets parsed faces so the next scan reads every file again.
    public func clearCache() {
        fatalError("Implemented in PointCore")
    }
}

/// Foundry names as the files give them, tidied for display.
public enum Foundry {
    /// Drops "Inc."/"LLC"/"GmbH"…, URLs, copyright lines and over-long strings; nil when nothing useful is left.
    public static func normalized(_ raw: String?) -> String? {
        fatalError("Implemented in PointCore")
    }
}
