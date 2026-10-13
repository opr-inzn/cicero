import Foundation

/// What a backup says about itself: `manifest.json` at the top of the archive.
public struct BackupManifest: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format = Self.currentFormat
    public var created: Date
    /// CFBundleShortVersionString of the Cicero that made it.
    public var appVersion: String
    /// The home folder of the account it was made in, which "~" stands for in every path.
    public var home: String
    /// Whether the files in `fonts` are in the archive.
    public var includesFonts: Bool
    /// Every font file in the library when the backup was made, protected ones left out.
    public var fonts: [BackupFont]

    public init(created: Date, appVersion: String, home: String, includesFonts: Bool, fonts: [BackupFont]) {
        self.created = created
        self.appVersion = appVersion
        self.home = home
        self.includesFonts = includesFonts
        self.fonts = fonts
    }
}

/// One font file in a backup.
public struct BackupFont: Codable, Equatable, Sendable {
    /// Where the file was, with the home folder written as "~".
    public var path: String
    /// Where it is in the archive ("Fonts/12/Name.otf"); nil when the files weren't included.
    public var archivePath: String?
    public var size: Int64
    public var activation: BackupActivation
    /// For an installed copy, the file it was copied from (with "~").
    public var origin: String?

    public init(path: String, archivePath: String? = nil, size: Int64, activation: BackupActivation, origin: String? = nil) {
        self.path = path
        self.archivePath = archivePath
        self.size = size
        self.activation = activation
        self.origin = origin
    }
}

/// How a file was active when the backup was made.
public enum BackupActivation: String, Codable, Sendable {
    /// In ~/Library/Fonts.
    case fontsFolder
    /// Registered where it is by Cicero.
    case inPlace
    /// A copy Cicero installed in ~/Library/Fonts; `origin` says from where.
    case installedCopy
    case inactive
}

/// What's in a backup, read from the archive unzipped into a temporary folder.
public struct BackupContents: Identifiable, Sendable {
    public let id = UUID()
    public var manifest: BackupManifest
    public var userData: UserData
    /// The unzipped folder with `manifest.json` in it.
    public var folder: URL
    private let tempRoot: URL

    init(manifest: BackupManifest, userData: UserData, folder: URL, tempRoot: URL) {
        self.manifest = manifest
        self.userData = userData
        self.folder = folder
        self.tempRoot = tempRoot
    }

    /// Files in the archive, ready to put back.
    public var fontCount: Int {
        manifest.includesFonts ? manifest.fonts.count { $0.archivePath != nil } : 0
    }

    /// Removes the unzipped folder; call when done with it.
    public func discard() {
        try? FileManager.default.removeItem(at: tempRoot)
    }
}

public enum BackupProgress: Sendable, Equatable {
    case copying(done: Int, total: Int)
    case compressing
}

/// What putting a backup's fonts back did.
public struct FontRestoreResult: Sendable, Equatable {
    /// Files put back where they were.
    public var restored = 0
    /// Files already there, left alone.
    public var skipped = 0
    /// Files that couldn't go back and went to the fallback folder instead.
    public var fallback = 0
    /// Files that couldn't be written anywhere.
    public var failed = 0
    /// The task was cancelled; the counts are what was done until then.
    public var cancelled = false

    public init() {}
}

/// Writes and reads `.cicerobackup` archives: a ZIP with `manifest.json`, `user-data.json` and,
/// when chosen, `Fonts/<n>/<file>` for every font file in the library. Paths are written with the
/// home folder as "~", so a backup restores on another Mac or account.
public struct LibraryBackup: Sendable {
    public static let fileExtension = "cicerobackup"
    /// In the home folder: where fonts go that can't go back where they were.
    public static let fallbackFolderName = "Fonts Restored from Cicero"

    public enum Failure: Error, Sendable {
        case notABackup
        case newerFormat
        case archive(String)

        public var message: String {
            switch self {
            case .notABackup: "This file isn’t a Cicero backup."
            case .newerFormat: "This backup was made by a newer version of Cicero."
            case .archive: "Couldn’t read or write the archive."
            }
        }
    }

    /// Moves the item the user chose to replace to the Trash. Tests replace it so they don't fill the user's Trash.
    public var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    private let locations: Locations
    private let home: URL

    public init(locations: Locations, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.locations = locations
        self.home = home
    }

    /// Where fonts go that can't go back where they were.
    public var fallbackFolder: URL { home.appendingPathComponent(Self.fallbackFolderName, isDirectory: true) }
    /// Where the current setup is saved before a restore replaces it.
    public var snapshotsFolder: URL { locations.support.appendingPathComponent("Backups", isDirectory: true) }

    // MARK: Names

    /// "Cicero Backup 2026-10-13.cicerobackup".
    public static func defaultName(for date: Date = Date()) -> String {
        "Cicero Backup \(stamp(date, "yyyy-MM-dd")).\(fileExtension)"
    }

    private static func stamp(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: Paths

    /// "/Users/me/Fonts/A.otf" → "~/Fonts/A.otf".
    public static func abbreviate(_ path: String, home: String) -> String {
        move(path, from: home, to: "~")
    }

    /// "~/Fonts/A.otf" → "/Users/me/Fonts/A.otf".
    public static func expand(_ path: String, home: String) -> String {
        move(path, from: "~", to: home)
    }

    /// The path with one home folder swapped for another; other paths as they are.
    static func move(_ path: String, from old: String, to new: String) -> String {
        if path == old { return new }
        return path.hasPrefix(old + "/") ? new + path.dropFirst(old.count) : path
    }

    func expand(_ path: String) -> String { Self.expand(path, home: home.path) }

    // MARK: Making

    /// Every file in the library (faces' own files and their other copies) once, with how it's
    /// active, protected files left out. Reads file sizes; runs off the main thread.
    @concurrent
    public func inventory(of library: Library, records: ActivationRecords) async -> [BackupFont] {
        var fonts: [BackupFont] = []
        var seen = Set<String>()
        func add(_ path: String, state: FaceState?) {
            guard seen.insert(path).inserted, !ActivationEngine.isProtected(path) else { return }
            let (activation, origin) = activation(of: path, state: state, records: records)
            fonts.append(BackupFont(
                path: Self.abbreviate(path, home: home.path), size: Self.size(of: path), activation: activation,
                origin: origin.map { Self.abbreviate($0, home: home.path) }
            ))
        }
        for family in library.families {
            for face in family.faces {
                add(face.face.path, state: face.state)
                // Other copies have no state of their own; the records and the path say enough.
                for copy in face.otherCopies { add(copy, state: nil) }
            }
        }
        return fonts.sorted { $0.path < $1.path }
    }

    /// Judged by the records first, since a face's state doesn't say whether Cicero installed it.
    private func activation(of path: String, state: FaceState?, records: ActivationRecords) -> (BackupActivation, origin: String?) {
        if let origin = records.installedCopies[path] { return (.installedCopy, origin) }
        if path.hasPrefix(locations.userFonts.path + "/") { return (.fontsFolder, nil) }
        if records.inPlace.contains(path) || state?.source == .inPlace { return (.inPlace, nil) }
        return (.inactive, nil)
    }

    private static func size(of path: String) -> Int64 {
        var info = stat()
        return stat(path, &info) == 0 ? Int64(info.st_size) : 0
    }

    /// Writes the archive: the font files first (unless `includeFonts` is off), then the manifest
    /// and user data, then ditto zips it all. A file that disappeared since the inventory is left
    /// out. Replaces an item at `destination` only by moving it to the Trash first, right before the
    /// zip step, so a cancelled backup leaves it alone.
    @concurrent
    public func write(
        to destination: URL, userData: UserData, fonts: [BackupFont], includeFonts: Bool, appVersion: String,
        progress: @escaping @Sendable (BackupProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("Cicero Backup \(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let folder = staging.appendingPathComponent(destination.deletingPathExtension().lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var manifest = BackupManifest(created: Date(), appVersion: appVersion, home: home.path, includesFonts: includeFonts, fonts: fonts)
        if includeFonts {
            for (index, font) in fonts.enumerated() {
                try Task.checkCancellation()
                progress(.copying(done: index, total: fonts.count))
                let source = URL(fileURLWithPath: expand(font.path), isDirectory: false)
                guard fm.fileExists(atPath: source.path) else { continue }
                let archivePath = "Fonts/\(index)/\(source.lastPathComponent)"
                let target = folder.appendingPathComponent(archivePath, isDirectory: false)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                manifest.fonts[index].archivePath = archivePath
            }
            progress(.copying(done: fonts.count, total: fonts.count))
        }
        try Self.manifestEncoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json", isDirectory: false))
        try UserDataStore.encoded(userData).write(to: folder.appendingPathComponent("user-data.json", isDirectory: false))

        try Task.checkCancellation()
        progress(.compressing)
        if fm.fileExists(atPath: destination.path) { try trash(destination) }
        try await Archive.zip(folder, to: destination)
    }

    /// Saves the current setup as `Backups/Before Restore <date>.json` and returns the file.
    public func saveSnapshot(_ data: UserData, date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: snapshotsFolder, withIntermediateDirectories: true)
        let url = snapshotsFolder.appendingPathComponent("Before Restore \(Self.stamp(date, "yyyy-MM-dd HH.mm.ss")).json", isDirectory: false)
        try UserDataStore.encoded(data).write(to: url, options: .atomic)
        return url
    }

    private static var manifestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var manifestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Reading

    /// Unzips the archive into a temporary folder and reads what's in it. The caller discards the
    /// contents when done with them.
    @concurrent
    public static func open(_ archive: URL) async throws -> BackupContents {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Cicero Restore \(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try await Archive.unzip(archive, to: root)
            guard let folder = manifestFolder(in: root) else { throw Failure.notABackup }
            let manifest: BackupManifest
            do {
                manifest = try manifestDecoder.decode(BackupManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
            } catch {
                throw Failure.notABackup
            }
            guard manifest.format <= BackupManifest.currentFormat else { throw Failure.newerFormat }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("user-data.json")),
                  let userData = try? JSONDecoder().decode(UserData.self, from: data)
            else { throw Failure.notABackup }
            return BackupContents(manifest: manifest, userData: userData, folder: folder, tempRoot: root)
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    /// The archive's top folder (ditto keeps it) or the root itself, whichever has the manifest.
    private static func manifestFolder(in root: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("manifest.json").path) { return root }
        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return children.first { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }

    // MARK: Restoring

    /// Puts each font back where it was, "~" meaning this account's home folder, creating folders
    /// as needed; a file already at the path is left alone. A file that can't go back (no
    /// permission, or the folder belongs to an app that isn't installed) goes into the fallback
    /// folder with its path kept under it. Runs off the main thread; cancelling stops it between files.
    @concurrent
    public func restoreFonts(_ contents: BackupContents, progress: @escaping @Sendable (Int, Int) -> Void) async -> FontRestoreResult {
        let fm = FileManager.default
        var result = FontRestoreResult()
        let fonts = contents.manifest.fonts.filter { $0.archivePath != nil }
        for (index, font) in fonts.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            progress(index, fonts.count)
            let source = contents.folder.appendingPathComponent(font.archivePath!, isDirectory: false)
            let target = expand(font.path)
            if fm.fileExists(atPath: target) {
                result.skipped += 1
                continue
            }
            if canGoBack(target), (try? Self.place(source, at: target)) != nil {
                result.restored += 1
                continue
            }
            let fallback = fallbackFolder.appendingPathComponent(fallbackPath(for: target), isDirectory: false).path
            if fm.fileExists(atPath: fallback) {
                result.skipped += 1
            } else if (try? Self.place(source, at: fallback)) != nil {
                result.fallback += 1
            } else {
                result.failed += 1
            }
        }
        progress(fonts.count, fonts.count)
        return result
    }

    /// Never into macOS's or an app's folders, and not into an app that isn't installed: the folder
    /// next to a gone app would otherwise be made, and never looked at by anything.
    private func canGoBack(_ path: String) -> Bool {
        guard !ActivationEngine.isProtected(path) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return !path.hasPrefix("/Applications/") || FileManager.default.fileExists(atPath: parent)
    }

    /// "~/Library/Fonts/A.otf" keeps "Library/Fonts/A.otf" under the fallback folder; any other path its whole path.
    func fallbackPath(for path: String) -> String {
        let prefix = home.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : String(path.drop(while: { $0 == "/" }))
    }

    private static func place(_ source: URL, at path: String) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: path, isDirectory: false)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    /// The backup's user data with every path moved from the home folder it was made in to this
    /// one. Temporary activations are over; the other records are merged by `mergedRecords`.
    public func userData(from contents: BackupContents) -> UserData {
        let oldHome = contents.manifest.home
        func map(_ path: String) -> String { Self.move(path, from: oldHome, to: home.path) }
        func map(_ dictionary: [String: String]) -> [String: String] {
            Dictionary(dictionary.map { (map($0.key), map($0.value)) }, uniquingKeysWith: { first, _ in first })
        }
        var data = contents.userData
        data.folders = data.folders.map { WatchedFolder(id: $0.id, path: map($0.path), appName: $0.appName) }
        data.records.installedCopies = map(data.records.installedCopies)
        data.records.inPlace = Set(data.records.inPlace.map(map))
        data.records.temporary = [:]
        data.records.appFolderOrigins = map(data.records.appFolderOrigins)
        return data
    }

    /// Records for this Mac after a restore. The current ones stay where their file still exists;
    /// the backup's installed copies count when both files exist, its files kept out of an app's
    /// folder when they exist, and its in-place registrations are returned for activating again,
    /// since macOS on this Mac doesn't know them.
    public static func mergedRecords(
        current: ActivationRecords, backup: ActivationRecords, exists: (String) -> Bool
    ) -> (records: ActivationRecords, reactivate: [String]) {
        var records = current
        records.installedCopies = current.installedCopies.filter { exists($0.key) }
        for (copy, origin) in backup.installedCopies where records.installedCopies[copy] == nil && exists(copy) && exists(origin) {
            records.installedCopies[copy] = origin
        }
        records.appFolderOrigins = current.appFolderOrigins.filter { exists($0.key) }
        for (path, origin) in backup.appFolderOrigins where records.appFolderOrigins[path] == nil && exists(path) {
            records.appFolderOrigins[path] = origin
        }
        let reactivate = backup.inPlace.filter { !current.inPlace.contains($0) && exists($0) }.sorted()
        return (records, reactivate)
    }
}

/// ZIP archives made and read with ditto, which handles big folders and long names where
/// Foundation has nothing built in.
enum Archive {
    /// Zips `folder` as `destination`, with the folder itself at the top of the archive. No
    /// resource forks or Finder metadata, so there's no __MACOSX folder for other systems to wonder about.
    static func zip(_ folder: URL, to destination: URL) async throws {
        try await ditto(["-c", "-k", "--keepParent", "--norsrc", folder.path, destination.path])
    }

    static func unzip(_ archive: URL, to folder: URL) async throws {
        try await ditto(["-x", "-k", archive.path, folder.path])
    }

    /// Runs ditto to completion; cancelling the task stops it.
    private static func ditto(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard status == 0 else {
            throw LibraryBackup.Failure.archive(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
    }
}
