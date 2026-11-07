import CryptoKit
import Foundation

/// What the `cicero` command is turning on or off while Cicero is closed, written down (onto the disk itself) before it
/// starts and taken away once the activation records are saved. A command that stops in between (killed, the Mac
/// switched off) leaves fonts on or off, or files moved, that the records don't know about. The next program to hold
/// `AppLock`, the command or Cicero at launch, repairs the records from what's true now (`repair`) and takes the journal
/// away. Nothing turns on or off again: the records follow what macOS and the files say.
public struct ActivationJournal: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var path: String
        /// The file's contents, to find it again if it moves into the Inactive folder (out of an app's folder).
        public var digest: String?
    }

    /// On, or off.
    public var turningOn: Bool
    public var entries: [Entry]

    public init(turningOn: Bool, paths: [String]) {
        self.turningOn = turningOn
        var seen = Set<String>()
        entries = paths.filter { seen.insert($0).inserted }.map { Entry(path: $0, digest: Self.digest(of: $0)) }
    }

    public static func url(support: URL) -> URL {
        support.appendingPathComponent("command-activation.json", isDirectory: false)
    }

    public static func read(support: URL) -> ActivationJournal? {
        (try? Data(contentsOf: url(support: support))).flatMap { try? JSONDecoder().decode(ActivationJournal.self, from: $0) }
    }

    /// Written whole and onto the disk, before anything turns.
    public func write(support: URL) throws {
        let url = Self.url(support: support)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        _ = UserDataStore.syncToDisk(url)
    }

    public static func remove(support: URL) {
        try? FileManager.default.removeItem(at: url(support: support))
    }

    /// The records as they'd be had the command finished: each file turned on where it is that macOS has on is in
    /// `inPlace`, each turned off isn't (nor on for a while); a file that went from an app's folder into the Inactive
    /// folder has its origin noted, found by its contents; one that went back has it forgotten. Files in a Fonts folder
    /// need nothing: macOS keeps whether they're on. Doing it again changes nothing more.
    public func repair(_ records: ActivationRecords, registrar: any FontRegistrar, locations: Locations) -> ActivationRecords {
        var records = records
        let fm = FileManager.default
        let fontsFolders = [locations.userFonts.path + "/", locations.allUsersFonts.path + "/"]
        let inactive = locations.inactiveFolders
        for entry in entries {
            let path = entry.path
            // Turned on out of the Inactive folder, back into its app's folder.
            if let origin = records.appFolderOrigins[path] {
                if !fm.fileExists(atPath: path), fm.fileExists(atPath: origin) { records.appFolderOrigins[path] = nil }
                continue
            }
            if fontsFolders.contains(where: path.hasPrefix) { continue }
            let exists = fm.fileExists(atPath: path)
            // Turned off out of an app's folder, into the Inactive folder.
            if !turningOn, !exists, WatchedFolder.detectAppName(forPath: path) != nil, let digest = entry.digest {
                let known = Set(records.appFolderOrigins.keys)
                let moved = inactive.lazy.flatMap { folder in Self.files(in: folder) }.first { candidate in
                    !known.contains(candidate) && Self.digest(of: candidate) == digest
                }
                if let moved { records.appFolderOrigins[moved] = path }
                continue
            }
            guard exists else { continue }
            let on = registrar.isActive(URL(fileURLWithPath: path, isDirectory: false))
            if turningOn, on {
                records.inPlace.insert(path)
            } else if !turningOn, !on {
                records.inPlace.remove(path)
                records.temporary[path] = nil
            }
        }
        return records
    }

    static func digest(of path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path, isDirectory: false), options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func files(in folder: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        return walker.compactMap { ($0 as? String).map { folder.appendingPathComponent($0).path } }
    }
}
