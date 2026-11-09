import CryptoKit
import Foundation

public struct ActivationJournal: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var path: String
        public var digest: String?
    }

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

    public func write(support: URL) throws {
        let url = Self.url(support: support)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // Whole and onto the disk itself before anything turns, or a command stopped halfway leaves changes the records never learn of.
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        _ = UserDataStore.syncToDisk(url)
    }

    public static func remove(support: URL) {
        try? FileManager.default.removeItem(at: url(support: support))
    }

    public func repair(_ records: ActivationRecords, registrar: any FontRegistrar, locations: Locations) -> ActivationRecords {
        var records = records
        let fm = FileManager.default
        let fontsFolders = [locations.userFonts.path + "/", locations.allUsersFonts.path + "/"]
        let inactive = locations.inactiveFolders
        for entry in entries {
            let path = entry.path
            if let origin = records.appFolderOrigins[path] {
                if !fm.fileExists(atPath: path), fm.fileExists(atPath: origin) { records.appFolderOrigins[path] = nil }
                continue
            }
            if fontsFolders.contains(where: path.hasPrefix) { continue }
            let exists = fm.fileExists(atPath: path)
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

public struct AppFolderMoves: Codable, Sendable {
    struct Move: Codable, Sendable {
        var moved: String
        var origin: String
        var digest: String?
    }

    var moves: [Move] = []

    static func url(support: URL) -> URL {
        support.appendingPathComponent("moved-out-of-app-folders.json", isDirectory: false)
    }

    static func note(moved: String, origin: String, support: URL) {
        let url = url(support: support)
        var list = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AppFolderMoves.self, from: $0) } ?? AppFolderMoves()
        list.moves.append(Move(moved: moved, origin: origin, digest: ActivationJournal.digest(of: origin)))
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        guard (try? JSONEncoder().encode(list).write(to: url, options: .atomic)) != nil else { return }
        _ = UserDataStore.syncToDisk(url)
    }

    public static func exists(support: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(support: support).path)
    }

    public static func recover(_ records: ActivationRecords, support: URL) -> ActivationRecords {
        guard let data = try? Data(contentsOf: url(support: support)),
              let list = try? JSONDecoder().decode(AppFolderMoves.self, from: data) else { return records }
        var records = records
        let fm = FileManager.default
        for move in list.moves where records.appFolderOrigins[move.moved] == nil && fm.fileExists(atPath: move.moved) {
            // The Inactive folder has other files too, set aside by Replace or a restore, which may have taken the same name since.
            guard let digest = move.digest, ActivationJournal.digest(of: move.moved) == digest else { continue }
            records.appFolderOrigins[move.moved] = move.origin
        }
        return records
    }

    public static func remove(support: URL) {
        try? FileManager.default.removeItem(at: url(support: support))
    }
}
