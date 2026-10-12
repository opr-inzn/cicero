import CoreText
import Foundation

/// Registers and unregisters font files with the system. The CoreText implementation is used by the
/// app; tests use a fake so they never change the Mac's fonts.
public protocol FontRegistrar: Sendable {
    /// Returns the paths that failed.
    func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    /// Returns the paths that failed.
    func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    /// Synchronous unregistering, for when the app is about to quit.
    func unregisterNow(_ urls: [URL], scope: CTFontManagerScope)
    /// Every font file the system has active.
    func activeFontURLs() -> [URL]
}

public struct CoreTextRegistrar: FontRegistrar {
    public init() {}

    public func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> { fatalError("Implemented in PointCore") }
    public func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> { fatalError("Implemented in PointCore") }
    public func unregisterNow(_ urls: [URL], scope: CTFontManagerScope) { fatalError("Implemented in PointCore") }
    public func activeFontURLs() -> [URL] { fatalError("Implemented in PointCore") }
}

/// What an activation, deactivation or trash did.
public struct ActivationResult: Sendable {
    /// Records after the operation; the caller stores them.
    public var records: ActivationRecords
    public var succeeded: Int
    /// Paths that couldn't be handled.
    public var failed: [String]
    /// A short toast, e.g. "Activated." or "Couldn’t activate 2 of 5 files."
    public var message: String

    public init(records: ActivationRecords, succeeded: Int, failed: [String], message: String) {
        self.records = records
        self.succeeded = succeeded
        self.failed = failed
        self.message = message
    }
}

/// Files to move to the Trash, worked out before asking for confirmation.
public struct TrashPlan: Sendable, Identifiable {
    public let id = UUID()
    /// e.g. "“Inter”" or "3 families".
    public var title: String
    public var paths: [String]
    /// Families that are not part of the request but have styles in those files (collections).
    public var otherFamilies: [String]
    /// Files that were left out because Point never touches them (macOS, apps, Adobe Fonts…).
    public var protectedCount: Int
    /// Families removed entirely, to drop from sets, tags and foundry overrides.
    public var removedFamilies: [String]

    public init(title: String, paths: [String], otherFamilies: [String], protectedCount: Int, removedFamilies: [String]) {
        self.title = title
        self.paths = paths
        self.otherFamilies = otherFamilies
        self.protectedCount = protectedCount
        self.removedFamilies = removedFamilies
    }
}

/// Turns fonts on and off. Never deletes a user's only copy: installed copies go to the Trash only
/// when another copy exists, other files in ~/Library/Fonts move to Point's Deactivated folder.
public struct ActivationEngine: Sendable {
    public init(locations: Locations, registrar: any FontRegistrar = CoreTextRegistrar()) {
        fatalError("Implemented in PointCore")
    }

    /// Copies into ~/Library/Fonts or registers in place (`method` is `.copy` or `.inPlace`). Faces
    /// from app-only folders are always registered in place. Temporarily active faces are made permanent.
    public func activate(_ faces: [LibraryFace], method: InstallMethod, records: ActivationRecords) async -> ActivationResult {
        fatalError("Implemented in PointCore")
    }

    public func activateTemporarily(_ faces: [LibraryFace], scope: TemporaryScope, records: ActivationRecords) async -> ActivationResult {
        fatalError("Implemented in PointCore")
    }

    /// Faces in ~/Library/Fonts that Point didn't install and that have no other copy: deactivating
    /// them moves the file into Point's Deactivated folder, so the app asks first.
    public func unmanaged(_ faces: [LibraryFace], records: ActivationRecords) -> [LibraryFace] {
        fatalError("Implemented in PointCore")
    }

    public func deactivate(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        fatalError("Implemented in PointCore")
    }

    /// nil when every file is protected (the app then says so).
    public func trashPlan(for faces: [LibraryFace], removing families: [String], in library: Library, title: String) -> TrashPlan? {
        fatalError("Implemented in PointCore")
    }

    public func moveToTrash(_ plan: TrashPlan, records: ActivationRecords) async -> ActivationResult {
        fatalError("Implemented in PointCore")
    }

    /// At launch: forgets temporary activations from an earlier login session and unregisters
    /// "until Point quits" ones left behind by a crash.
    public func reconcileTemporary(_ records: ActivationRecords) async -> ActivationRecords {
        fatalError("Implemented in PointCore")
    }

    /// At quit: unregisters "until Point quits" activations synchronously.
    public func endUntilQuit(_ records: ActivationRecords) -> ActivationRecords {
        fatalError("Implemented in PointCore")
    }

    /// Identifies the current login session (audit session ID plus boot time).
    public static func currentSession() -> String {
        fatalError("Implemented in PointCore")
    }

    /// Paths Point never moves, trashes or modifies.
    public static func isProtected(_ path: String) -> Bool {
        fatalError("Implemented in PointCore")
    }
}
