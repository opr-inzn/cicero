import Foundation

/// The font caches macOS keeps.
public enum SystemFontCaches {
    public enum Scope: Sendable {
        case currentUser
        /// Needs an administrator; macOS asks for the password itself.
        case allUsers
    }

    public enum Failure: Error, Sendable {
        case cancelled
        case failed(String)
    }

    /// Removes the caches and restarts the font service, which rebuilds them on demand.
    public static func clear(_ scope: Scope) async throws {
        fatalError("Implemented in PointCore")
    }
}

/// Font caches other apps keep and rebuild the next time they open. Only the files and folders
/// matched here are ever touched, and only ever moved to the Trash.
public enum AppFontCaches {
    public enum App: String, CaseIterable, Identifiable, Sendable {
        case adobe, office

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .adobe: "Adobe apps"
            case .office: "Microsoft Office"
            }
        }

        /// Apps that read these caches and must be quit first.
        public var bundleIDs: Set<String> {
            switch self {
            case .adobe: ["com.adobe.InDesign", "com.adobe.illustrator", "com.adobe.Photoshop", "com.adobe.Acrobat.Pro", "com.adobe.Reader"]
            case .office: ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"]
            }
        }

        /// Office keeps its caches inside its app containers. Looking there makes macOS ask whether
        /// Point may access other apps' data, so only look when the user chooses to clear them.
        public var isGuardedByMacOS: Bool { self == .office }
    }

    public struct Found: Sendable {
        public var app: App
        public var items: [URL]
        public var size: Int64

        public init(app: App, items: [URL], size: Int64) {
            self.app = app
            self.items = items
            self.size = size
        }

        public var isEmpty: Bool { items.isEmpty }
    }

    /// What exists for `app`, with its size. Walks folders; call off the main thread.
    public static func find(_ app: App) -> Found {
        fatalError("Implemented in PointCore")
    }

    /// Moves every found item to the Trash; returns how many couldn't be moved.
    public static func trash(_ found: Found) -> Int {
        fatalError("Implemented in PointCore")
    }
}
