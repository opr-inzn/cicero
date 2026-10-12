import Foundation

public enum ProblemKind: String, CaseIterable, Sendable {
    case installedTwice, sharedNames, missing, unreadable, external, duplicates

    public var title: String {
        switch self {
        case .installedTwice: "Installed Twice"
        case .sharedNames: "Different Fonts Share a Name"
        case .missing: "Missing Files"
        case .unreadable: "Damaged or Unreadable Files"
        case .external: "Fonts on External Disks"
        case .duplicates: "Duplicates"
        }
    }

    /// One or two plain sentences shown above the group.
    public var explanation: String {
        switch self {
        case .installedTwice:
            "The same font is active from more than one file. macOS uses only one of them, so apps may get an older version. Keep one and remove the other copies."
        case .sharedNames:
            "These are different fonts, but some of their styles use the same PostScript name, the name documents and PDFs use to find a font. Asked for one of those names, macOS may give either font. Updated versions from the foundry usually fix this; until then, turn one off while you use the other."
        case .missing:
            "Point remembers these files, but they’re gone. Fonts used where they were stop working when their files move or their disk is unplugged."
        case .unreadable:
            "Point couldn’t read these files. They may be damaged, or not font files at all."
        case .external:
            "These fonts are used from a disk that can be unplugged. They turn off when it’s gone."
        case .duplicates:
            "The same font is in your folders more than once."
        }
    }
}

/// One file involved in a problem.
public struct ProblemFile: Hashable, Sendable {
    public var path: String
    public var version: String?
    public var modified: Date?
    /// Where it is or how it's active, e.g. "In your Fonts folder", "Used where it is".
    public var detail: String

    public init(path: String, version: String?, modified: Date?, detail: String) {
        self.path = path
        self.version = version
        self.modified = modified
        self.detail = detail
    }
}

/// Something the user can do about a problem. The app carries these out.
public enum ProblemFix: Hashable, Sendable {
    case reveal(String)
    /// Deactivate this active copy (installed copies go to the Trash or the Deactivated folder).
    case deactivate(FaceID)
    /// Move these files to the Trash (never protected paths, never the only copy).
    case trash([String])
    /// Forget a missing in-place registration and unregister it.
    case forgetInPlace(String)
    /// Forget a missing installed copy.
    case forgetInstalledCopy(String)
    case removeFromSet(UUID, family: String)
    /// Copy a font used from an external disk into ~/Library/Fonts and stop using it in place.
    case installCopy(String)

    public var title: String {
        switch self {
        case .reveal: "Reveal"
        case .deactivate: "Deactivate"
        case .trash(let paths): paths.count == 1 ? "Move to Trash…" : "Move Extra Copies to Trash…"
        case .forgetInPlace, .forgetInstalledCopy: "Forget"
        case .removeFromSet: "Remove from Set"
        case .installCopy: "Install a Copy Instead"
        }
    }
}

public struct Problem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ProblemKind
    /// e.g. the family names involved.
    public var title: String
    /// e.g. "Active from 2 files."
    public var summary: String
    public var files: [ProblemFile]
    /// Fixes for the problem as a whole.
    public var fixes: [ProblemFix]
    /// Fixes for single files, by path.
    public var fileFixes: [String: [ProblemFix]]

    public init(id: String, kind: ProblemKind, title: String, summary: String, files: [ProblemFile], fixes: [ProblemFix], fileFixes: [String: [ProblemFix]]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.files = files
        self.fixes = fixes
        self.fileFixes = fileFixes
    }
}

public enum ProblemDetector {
    /// Finds problems in the library. Reads font versions from disk for the files involved, so call it off the main thread.
    public static func detect(in library: Library, data: UserData, locations: Locations) -> [Problem] {
        fatalError("Implemented in PointCore")
    }
}
