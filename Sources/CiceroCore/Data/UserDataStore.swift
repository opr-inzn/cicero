import Foundation
import Synchronization

public final class UserDataStore: Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "Cicero.UserDataStore", qos: .utility)
    private let pending = Mutex<Pending>(Pending())
    private let failureHandler = Mutex<(@Sendable () -> Void)?>(nil)
    private let readOnly = Mutex<String?>(nil)

    private struct Pending {
        var data: UserData?
        var generation = 0
    }

    static let coalescingDelay: TimeInterval = 0.25

    public init(locations: Locations) {
        fileURL = locations.support.appendingPathComponent("user-data.json", isDirectory: false)
    }

    public var hasSavedData: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public var isReadOnly: Bool { readOnly.withLock { $0 != nil } }

    public var readOnlyMessage: String { readOnly.withLock { $0 } ?? UserData.newerVersionMessage }

    public func load() -> UserData {
        var exists = stat()
        if lstat(fileURL.path, &exists) == 0 {
            // A file that is there but can't be read is never written over: the next save would replace the user's data.
            guard let data = try? Data(contentsOf: fileURL) else {
                readOnly.withLock { $0 = UserData.unreadableMessage }
                return .newLibrary
            }
            let newer = UserData.isFromNewerVersion(data)
            if newer { readOnly.withLock { $0 = UserData.newerVersionMessage } }
            if var decoded = try? JSONDecoder().decode(UserData.self, from: data) {
                decoded.updateLicenseTags()
                return decoded
            }
            // Never a newer Cicero's file, which only holds what this one can't read: it stays, untouched, for that Cicero.
            if newer { return UserData() }
            // Keep a damaged file for the user instead of silently writing over it.
            if !setAside() { readOnly.withLock { $0 = UserData.unreadableMessage } }
            return .newLibrary
        }
        return .newLibrary
    }

    private func setAside() -> Bool {
        let fm = FileManager.default
        for number in 1...1000 {
            let name = number == 1 ? "user-data.unreadable.json" : "user-data.unreadable \(number).json"
            let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
            guard !fm.fileExists(atPath: destination.path) else { continue }
            return (try? fm.moveItem(at: fileURL, to: destination)) != nil
        }
        return false
    }

    public func save(_ data: UserData) {
        let generation = pending.withLock { pending in
            pending.data = data
            pending.generation += 1
            return pending.generation
        }
        queue.asyncAfter(deadline: .now() + Self.coalescingDelay) { [self] in writePending(for: generation) }
    }

    public func onFailedWrite(_ handler: @escaping @Sendable () -> Void) {
        failureHandler.withLock { $0 = handler }
    }

    @discardableResult
    public func flush(durably: Bool = false) -> Bool {
        queue.sync { writePending(for: nil) && (!durably || Self.syncToDisk(fileURL)) }
    }

    public static func syncToDisk(_ url: URL) -> Bool {
        let file = open(url.path, O_RDONLY)
        guard file >= 0 else { return false }
        defer { close(file) }
        return fcntl(file, F_FULLFSYNC) == 0 || fsync(file) == 0
    }

    @discardableResult
    private func writePending(for generation: Int?) -> Bool {
        let taken = pending.withLock { pending -> (data: UserData, generation: Int)? in
            if let generation, generation != pending.generation { return nil }
            return pending.data.map { ($0, pending.generation) }
        }
        guard let taken else { return true }
        // Cleared only once written: a write that fails keeps the data for the next one, and flush says so, so no caller drops a journal the file doesn't yet cover.
        guard write(taken.data) else {
            failureHandler.withLock { $0 }?()
            return false
        }
        pending.withLock { pending in
            if pending.generation == taken.generation { pending.data = nil }
        }
        return true
    }

    @discardableResult
    private func write(_ data: UserData) -> Bool {
        guard !isReadOnly else { return false }
        var data = data
        data.version = UserData.currentVersion
        guard let encoded = try? Self.encoded(data) else { return false }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? encoded.write(to: fileURL, options: .atomic)) != nil
    }

    public static func encoded(_ data: UserData) throws -> Data {
        var data = data
        // JSONEncoder refuses a date that isn't a finite number, and would then refuse every later save too.
        for (family, history) in data.activations where history.last.map({ !$0.timeIntervalSinceReferenceDate.isFinite }) == true {
            data.activations[family]?.last = nil
        }
        data.missingFontFiles = data.missingFontFiles.filter { $0.value.timeIntervalSinceReferenceDate.isFinite }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
}
