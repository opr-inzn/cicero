import Foundation

public struct BackupManifest: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format = Self.currentFormat
    public var created: Date
    public var appVersion: String
    public var home: String
    public var includesFonts: Bool
    public var fonts: [BackupFont]

    public init(created: Date, appVersion: String, home: String, includesFonts: Bool, fonts: [BackupFont]) {
        self.created = created
        self.appVersion = appVersion
        self.home = home
        self.includesFonts = includesFonts
        self.fonts = fonts
    }
}

public struct BackupFont: Codable, Equatable, Sendable {
    public var path: String
    public var archivePath: String?
    public var size: Int64
    public var activation: BackupActivation
    public var origin: String?
    public var isOff: Bool?

    public init(path: String, archivePath: String? = nil, size: Int64, activation: BackupActivation, origin: String? = nil, isOff: Bool? = nil) {
        self.path = path
        self.archivePath = archivePath
        self.size = size
        self.activation = activation
        self.origin = origin
        self.isOff = isOff
    }
}

public enum BackupActivation: String, Codable, Sendable {
    case fontsFolder
    case inPlace
    case installedCopy
    case inactive
}

public struct BackupContents: Identifiable, Sendable {
    public let id = UUID()
    public var manifest: BackupManifest
    public var userData: UserData
    public var folder: URL
    private let tempRoot: URL

    init(manifest: BackupManifest, userData: UserData, folder: URL, tempRoot: URL) {
        self.manifest = manifest
        self.userData = userData
        self.folder = folder
        self.tempRoot = tempRoot
    }

    public var fontCount: Int {
        manifest.includesFonts ? manifest.fonts.count { $0.archivePath != nil } : 0
    }

    public func discard() {
        try? FileManager.default.removeItem(at: tempRoot)
    }
}

public enum BackupProgress: Sendable, Equatable {
    case copying(done: Int, total: Int)
    case compressing
}

public struct FontRestoreResult: Sendable, Equatable {
    public var restored = 0
    public var skipped = 0
    public var fallback = 0
    public var failed = 0
    public var restoredPaths: Set<String> = []
    public var turningOff: [String: String] = [:]
    public var fallbackPaths: [String: String] = [:]
    public var cancelled = false

    public init() {}
}

public struct LibraryBackup: Sendable {
    public static let fileExtension = "cicerobackup"
    public static let fallbackFolderPath = "Cicero/Restored"

    public enum Failure: Error, Sendable {
        case notABackup
        case newerFormat
        case archive(String)

        public var message: String {
            switch self {
            case .notABackup: "This file isn’t a Cicero backup"
            case .newerFormat: "This backup was made by a newer version of Cicero"
            case .archive: "Couldn’t read or write the archive"
            }
        }
    }

    public var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    private let locations: Locations
    private let home: URL

    public init(locations: Locations, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.locations = locations
        self.home = home
    }

    public var fallbackFolder: URL { home.appendingPathComponent(Self.fallbackFolderPath, isDirectory: true) }
    public var snapshotsFolder: URL { locations.support.appendingPathComponent("Backups", isDirectory: true) }

    // MARK: Names

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

    public static func abbreviate(_ path: String, home: String) -> String {
        move(path, from: home, to: "~")
    }

    public static func expand(_ path: String, home: String) -> String {
        move(path, from: "~", to: home)
    }

    static func move(_ path: String, from old: String, to new: String) -> String {
        guard !old.isEmpty else { return path }
        if path == old { return new }
        return path.hasPrefix(old + "/") ? new + path.dropFirst(old.count) : path
    }

    func expand(_ path: String) -> String { Self.expand(path, home: home.path) }

    // MARK: Making

    @concurrent
    public func inventory(of library: Library, records: ActivationRecords) async -> [BackupFont] {
        var fonts: [BackupFont] = []
        var seen = Set<String>()
        func add(_ path: String, state: FaceState?) {
            guard seen.insert(path).inserted, !ActivationEngine.isProtected(path) else { return }
            let (activation, origin) = activation(of: path, state: state, records: records)
            let isOff = path.hasPrefix(locations.userFonts.path + "/")
                && (!(state?.isActive ?? library.activePaths.contains(path)) || records.temporary[path] != nil)
            fonts.append(BackupFont(
                path: Self.abbreviate(path, home: home.path), size: Self.size(of: path), activation: activation,
                origin: origin.map { Self.abbreviate($0, home: home.path) }, isOff: isOff ? true : nil
            ))
        }
        for family in library.families {
            for face in family.faces {
                add(face.face.path, state: face.state)
                for copy in face.otherCopies { add(copy, state: nil) }
            }
        }
        return fonts.sorted { $0.path < $1.path }
    }

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

    @concurrent
    public func write(
        to destination: URL, userData: UserData, fonts: [BackupFont], includeFonts: Bool, keeping kept: [String] = [],
        appVersion: String, progress: @escaping @Sendable (BackupProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        // Never replace an item that is or holds a font in the backup, a Fonts folder, Cicero's folder or a watched folder: it would go to the Trash.
        let kept = [locations.userFonts.path, locations.allUsersFonts.path, locations.support.path, locations.inactiveFolder.path]
            + userData.scannedFolders().map(\.path) + fonts.map { expand($0.path) } + kept
        let replacement = try ItemReplacement(for: destination, keeping: kept)
        defer { replacement.discard() }
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
        try await Archive.zip(folder, to: replacement.staged)
        try Task.checkCancellation()
        try replacement.commit(trash: trash)
    }

    public func saveSnapshot(_ data: UserData, named name: String = "Before Restore", date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: snapshotsFolder, withIntermediateDirectories: true)
        let url = snapshotsFolder.appendingPathComponent("\(name) \(Self.stamp(date, "yyyy-MM-dd HH.mm.ss")).json", isDirectory: false)
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

    private static func manifestFolder(in root: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("manifest.json").path) { return root }
        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)) ?? []
        return children.first { child in
            (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
                && fm.fileExists(atPath: child.appendingPathComponent("manifest.json").path)
        }
    }

    // MARK: Restoring

    @concurrent
    public func restoreFonts(_ contents: BackupContents, fontLibrary: String? = nil, progress: @escaping @Sendable (Int, Int) -> Void) async -> FontRestoreResult {
        let fm = FileManager.default
        var result = FontRestoreResult()
        let data = userData(from: contents, fontLibrary: fontLibrary)
        let roots = fontLocations(watching: data.folders, fontLibrary: data.fontLibraryPath)
        let libraries = fontLibraries(of: contents, restoringInto: fontLibrary)
        let fonts = contents.manifest.fonts.filter { $0.archivePath != nil }
        for (index, font) in fonts.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            progress(index, fonts.count)
            let target = restoredPath(expand(font.path), libraries: libraries)
            // A backup is a file anyone could have made: only font files go back, only into font locations, and never from outside the unzipped folder.
            guard Self.isFontFile(target), let source = Self.archivedFile(font.archivePath!, in: contents.folder) else {
                result.failed += 1
                continue
            }
            if Self.isPlainPath(target), fm.fileExists(atPath: target) {
                result.skipped += 1
                continue
            }
            if font.isOff == true, Self.isFontLocation(target, in: roots), target.hasPrefix(locations.userFonts.path + "/"),
               let folder = try? locations.inactiveFolderForNewFiles() {
                let parked = ActivationEngine.uniqueURL(for: (target as NSString).lastPathComponent, in: folder).path
                if (try? Self.place(source, at: parked)) != nil {
                    result.restored += 1
                    result.restoredPaths.insert(parked)
                    result.turningOff[parked] = target
                    continue
                }
            }
            if Self.isFontLocation(target, in: roots), canGoBack(target), (try? Self.place(source, at: target)) != nil {
                result.restored += 1
                result.restoredPaths.insert(target)
                continue
            }
            guard let relative = fallbackPath(for: target) else {
                result.failed += 1
                continue
            }
            let fallback = fallbackFolder.appendingPathComponent(relative, isDirectory: false).path
            if fm.fileExists(atPath: fallback) {
                result.skipped += 1
                result.fallbackPaths[target] = fallback
            } else if (try? Self.place(source, at: fallback)) != nil {
                result.fallback += 1
                result.fallbackPaths[target] = fallback
            } else {
                result.failed += 1
            }
        }
        progress(fonts.count, fonts.count)
        return result
    }

    private func canGoBack(_ path: String) -> Bool {
        guard !ActivationEngine.isProtected(path) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return !path.hasPrefix("/Applications/") || FileManager.default.fileExists(atPath: parent)
    }

    func fallbackPath(for path: String) -> String? {
        let prefix = home.path + "/"
        let relative = path.hasPrefix(prefix) ? path.dropFirst(prefix.count) : Substring(path)
        let parts = relative.split(separator: "/").filter { $0 != "." && $0 != ".." }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    private func fontLocations(watching folders: [WatchedFolder], fontLibrary: String) -> [String] {
        let paths = [
            locations.userFonts.path, locations.allUsersFonts.path, locations.inactiveFolder.path,
            "/Library/Application Support/Adobe/Fonts", home.appendingPathComponent("Library/Application Support/Adobe/Fonts").path,
        ] + folders.map(\.path) + (fontLibrary.isEmpty ? [] : [fontLibrary])
        return paths.filter { Self.isPlainPath($0) && !ActivationEngine.isProtected($0 + "/") }
    }

    func restoredPath(_ path: String) -> String {
        locations.formerInactiveFolders.reduce(path) { path, former in Self.move(path, from: former.path, to: locations.inactiveFolder.path) }
    }

    private func restoredPath(_ path: String, libraries: (backup: String, restored: String)) -> String {
        let path = restoredPath(path)
        return locations.isInInactiveFolder(path) ? path : Self.move(path, from: libraries.backup, to: libraries.restored)
    }

    func fontLibraries(of contents: BackupContents, restoringInto target: String?) -> (backup: String, restored: String) {
        let saved = contents.userData.fontLibraryPath
        guard !saved.isEmpty else { return ("", target ?? "") }
        let backup = Self.move(saved, from: contents.manifest.home, to: home.path)
        let current = backup == locations.formerDefaultFontLibrary.path ? locations.defaultFontLibrary.path : backup
        return (backup, target ?? current)
    }

    private static func isFontLocation(_ path: String, in roots: [String]) -> Bool {
        guard isPlainPath(path), isFontFile(path), !ActivationEngine.isProtected(path) else { return false }
        return roots.contains { path.hasPrefix($0 + "/") } || path.firstMatch(of: #/^/Applications/Adobe [^/]+/Fonts//#) != nil
    }

    static func isPlainPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count > 1 else { return false }
        return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isFontFile(_ path: String) -> Bool {
        FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static func archivedFile(_ archivePath: String, in folder: URL) -> URL? {
        guard isPlainPath("/" + archivePath) else { return nil }
        let parts = archivePath.split(separator: "/")
        var url = folder
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            url = url.appendingPathComponent(String(part), isDirectory: !isLast)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == (isLast ? S_IFREG : S_IFDIR) else { return nil }
        }
        return url
    }

    private static func place(_ source: URL, at path: String) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: path, isDirectory: false)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    public func userData(from contents: BackupContents, fontLibrary: String? = nil) -> UserData {
        let oldHome = contents.manifest.home
        let libraries = fontLibraries(of: contents, restoringInto: fontLibrary)
        func map(_ path: String) -> String {
            restoredPath(Self.move(path, from: oldHome, to: home.path), libraries: libraries)
        }
        func map(_ dictionary: [String: String]) -> [String: String] {
            Dictionary(dictionary.map { (map($0.key), map($0.value)) }, uniquingKeysWith: { first, _ in first })
        }
        var data = contents.userData
        data.folders = data.folders.map { WatchedFolder(id: $0.id, path: map($0.path), appName: $0.appName, isActive: $0.isActive) }
        data.fontFiles = data.fontFiles.map(map)
        data.missingFontFiles = [:]
        data.fontLibraryPath = libraries.restored
        // Records only about fonts in font locations: activating moves a file back to the folder its record names, so a backup's records must not lead anywhere else.
        let roots = fontLocations(watching: data.folders, fontLibrary: data.fontLibraryPath)
        func isFont(_ path: String) -> Bool { Self.isFontLocation(path, in: roots) }
        func isFont(_ path: String, in folder: URL) -> Bool { path.hasPrefix(folder.path + "/") && isFont(path) }
        let fontLibrary = data.fontLibraryPath.isEmpty ? nil : URL(fileURLWithPath: data.fontLibraryPath, isDirectory: true)
        data.records.installedCopies = map(data.records.installedCopies).filter { copy, origin in
            (isFont(copy, in: locations.userFonts) || fontLibrary.map { isFont(copy, in: $0) } == true) && isFont(origin)
        }
        let added = Set(data.fontFiles)
        data.records.inPlace = Set(data.records.inPlace.map(map).filter { path in
            isFont(path) || added.contains(path) && Self.isPlainPath(path) && Self.isFontFile(path) && !ActivationEngine.isProtected(path)
        })
        data.records.temporary = [:]
        data.records.appFolderOrigins = map(data.records.appFolderOrigins).filter { isFont($0.key, in: locations.inactiveFolder) && isFont($0.value) }
        return data
    }

    public static func mergedRecords(
        current: ActivationRecords, backup: ActivationRecords, written: Set<String> = [], exists: (String) -> Bool,
        identical: (String, String) -> Bool = ActivationEngine.isIdenticalCopy(_:of:)
    ) -> (records: ActivationRecords, reactivate: [String]) {
        var records = current
        records.installedCopies = current.installedCopies.filter { exists($0.key) }
        for (copy, origin) in backup.installedCopies where records.installedCopies[copy] == nil && exists(copy) && exists(origin) {
            // A different file this Mac already had at that path is no copy, and Cicero mustn't treat it as one.
            guard written.contains(copy) || identical(copy, origin) else { continue }
            records.installedCopies[copy] = origin
        }
        records.appFolderOrigins = current.appFolderOrigins.filter { exists($0.key) }
        // Only the ones this restore put back: activating would move a file this Mac already had into that app's folder, where the app's uninstaller removes it.
        for (path, origin) in backup.appFolderOrigins where records.appFolderOrigins[path] == nil && written.contains(path) && exists(path) {
            records.appFolderOrigins[path] = origin
        }
        let reactivate = backup.inPlace.filter { !current.inPlace.contains($0) && exists($0) }.sorted()
        return (records, reactivate)
    }
}

enum Archive {
    static func zip(_ folder: URL, to destination: URL) async throws {
        try await ditto(["-c", "-k", "--keepParent", "--norsrc", folder.path, destination.path])
    }

    static func unzip(_ archive: URL, to folder: URL) async throws {
        try await ditto(["-x", "-k", archive.path, folder.path])
    }

    private static func ditto(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        let errors = pipe.fileHandleForReading
        let (status, message): (Int32, Data) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    // Read before waiting: ditto, with more to say than a pipe holds, waits until it's read.
                    let message = errors.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, message))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard status == 0 else { throw LibraryBackup.Failure.archive(String(decoding: message, as: UTF8.self)) }
    }
}
