import Foundation

/// Loads and saves `UserData` (`user-data.json` in `Locations.support`). The first load imports the
/// version 1 file (`library.json`) when there's no version 2 file yet, and never modifies it. Saves
/// are coalesced and written off the main thread, atomically, in order.
public final class UserDataStore: Sendable {
    public init(locations: Locations) {
        fatalError("Implemented in PointCore")
    }

    public func load() -> UserData {
        fatalError("Implemented in PointCore")
    }

    /// Schedules a save of this value (the latest one wins).
    public func save(_ data: UserData) {
        fatalError("Implemented in PointCore")
    }

    /// Writes any pending save now; call when the app quits.
    public func flush() {
        fatalError("Implemented in PointCore")
    }
}
