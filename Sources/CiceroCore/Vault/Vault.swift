import Foundation

public struct VaultLicense: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case desktop, web, app, trial, other
    }

    public struct Style: Codable, Hashable, Sendable {
        public var postScriptName: String
        public var family: String
        public var style: String
        public var version: String?
        public var file: String

        public init(postScriptName: String, family: String, style: String, version: String?, file: String) {
            self.postScriptName = postScriptName
            self.family = family
            self.style = style
            self.version = version
            self.file = file
        }
    }

    public var id: UUID
    public var owner: String
    public var name: String
    public var kinds: [Kind]
    public var project: String
    public var date: Date?
    public var ends: Date?
    public var note: String
    public var added: Date
    public var styles: [Style]
    public var folder: URL

    public init(id: UUID = UUID(), owner: String, name: String, kinds: [Kind] = [], project: String = "", date: Date? = nil,
                ends: Date? = nil, note: String = "", added: Date = Date(), styles: [Style] = [],
                folder: URL = URL(fileURLWithPath: "/", isDirectory: true)) {
        self.id = id
        self.owner = owner
        self.name = name
        self.kinds = kinds
        self.project = project
        self.date = date
        self.ends = ends
        self.note = note
        self.added = added
        self.styles = styles
        self.folder = folder
    }

    private enum CodingKeys: String, CodingKey { case id, owner, name, kinds, project, date, ends, note, added, styles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let kindNames = (try? c.decode([String].self, forKey: .kinds)) ?? []
        kinds = Kind.allCases.filter { kindNames.contains($0.rawValue) }
        project = (try? c.decode(String.self, forKey: .project)) ?? ""
        date = try? c.decode(Date.self, forKey: .date)
        ends = try? c.decode(Date.self, forKey: .ends)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        added = (try? c.decode(Date.self, forKey: .added)) ?? Date(timeIntervalSince1970: 0)
        styles = (try? c.decode([Style].self, forKey: .styles)) ?? []
        folder = URL(fileURLWithPath: "/", isDirectory: true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(owner, forKey: .owner)
        try c.encode(name, forKey: .name)
        try c.encode(kinds.map(\.rawValue), forKey: .kinds)
        try c.encode(project, forKey: .project)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(ends, forKey: .ends)
        try c.encode(note, forKey: .note)
        try c.encode(added, forKey: .added)
        try c.encode(styles, forKey: .styles)
    }

    public var families: [String] {
        var seen = Set<String>()
        return styles.map(\.family).filter { seen.insert($0).inserted }
    }

    public func covers(postScriptName: String) -> Bool {
        styles.contains { $0.postScriptName == postScriptName }
    }

    public func ends(within days: Int, of now: Date = Date()) -> Bool {
        guard let ends else { return false }
        return ends.timeIntervalSince(now) < Double(days) * 24 * 60 * 60
    }
}

public struct VaultFile: Hashable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case font, webFont, document, archive, other
    }

    public var path: String
    public var size: Int64
    public var kind: Kind
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public static func kind(ofExtension ext: String) -> Kind {
        switch ext.lowercased() {
        case "otf", "ttf", "ttc", "otc", "dfont": .font
        case "woff", "woff2", "eot": .webFont
        case "pdf", "txt", "rtf", "md", "html", "htm", "doc", "docx", "pages": .document
        case "zip": .archive
        default: .other
        }
    }
}

public struct VaultDraft: Sendable {
    public var staging: URL
    public var sources: [String]
    public var files: [VaultFile]
    public var styles: [VaultLicense.Style]
    public var kinds: [VaultLicense.Kind]
    public var suggestedName: String
    public var unpackedArchives: [String]
}

public enum VaultError: LocalizedError {
    case nothingToAdd
    case unpackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToAdd: "There are no files to add."
        case .unpackFailed(let name): "Cicero couldn’t open “\(name)”."
        }
    }
}

public struct Vault: Sendable {
    public let root: URL

    public static let detailsFile = ".cicero-license.json"
    static let stagingPrefix = ".adding-"
    static let renamingPrefix = ".renaming-"

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public init(locations: Locations) {
        self.init(root: locations.vault)
    }

    public var skippedPrefixes: [String] {
        let path = root.path
        return Array(Set([path + "/", LibraryScanner.realPath(path) + "/"]))
    }

    public func contains(_ path: String) -> Bool {
        skippedPrefixes.contains { path.hasPrefix($0) || path + "/" == $0 }
    }

    // MARK: Reading

    public func licenses() -> [VaultLicense] {
        var result: [VaultLicense] = []
        for ownerFolder in Self.visibleFolders(in: root) {
            for folder in Self.visibleFolders(in: ownerFolder) {
                var license: VaultLicense
                if let details = Self.details(in: folder) {
                    license = details
                } else {
                    let files = Self.files(in: folder)
                    license = VaultLicense(
                        owner: ownerFolder.lastPathComponent, name: folder.lastPathComponent, kinds: Self.kinds(of: files),
                        added: (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date(timeIntervalSince1970: 0),
                        styles: Self.styles(in: folder, files: files)
                    )
                    try? write(license, in: folder)
                }
                if Self.folderName(for: license.owner) != ownerFolder.lastPathComponent { license.owner = ownerFolder.lastPathComponent }
                if Self.folderName(for: license.name) != folder.lastPathComponent { license.name = folder.lastPathComponent }
                license.folder = folder
                result.append(license)
            }
        }
        var seen = Set<UUID>()
        for index in result.indices where !seen.insert(result[index].id).inserted {
            result[index].id = UUID()
        }
        return result.sorted {
            let owner = $0.owner.localizedStandardCompare($1.owner)
            return owner == .orderedSame ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : owner == .orderedAscending
        }
    }

    public var owners: [String] {
        var seen = Set<String>()
        return licenses().map(\.owner).filter { seen.insert($0.lowercased()).inserted }
    }

    public static func files(in folder: URL) -> [VaultFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        let base = folder.standardizedFileURL.path + "/"
        var files: [VaultFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
            files.append(VaultFile(path: relative, size: Int64(values.fileSize ?? 0), kind: VaultFile.kind(ofExtension: url.pathExtension)))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func styles(in folder: URL, files: [VaultFile]) -> [VaultLicense.Style] {
        var styles: [VaultLicense.Style] = []
        var seen = Set<String>()
        for file in files where file.kind == .font || file.kind == .webFont {
            let path = folder.appendingPathComponent(file.path).path
            if Reachability.isOnlineOnly(path) { continue }
            for face in FontFileReader.faces(atPath: path) where !face.postScriptName.isEmpty {
                guard seen.insert(face.postScriptName).inserted else { continue }
                styles.append(VaultLicense.Style(postScriptName: face.postScriptName, family: face.familyName,
                                                 style: face.styleName, version: face.version, file: file.path))
            }
        }
        return styles
    }

    public static func kinds(of files: [VaultFile]) -> [VaultLicense.Kind] {
        var kinds: [VaultLicense.Kind] = []
        if files.contains(where: { $0.kind == .font }) { kinds.append(.desktop) }
        if files.contains(where: { $0.kind == .webFont }) { kinds.append(.web) }
        return kinds
    }

    private static func details(in folder: URL) -> VaultLicense? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(detailsFile)) else { return nil }
        return try? decoder.decode(VaultLicense.self, from: data)
    }

    private static func visibleFolders(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items.filter {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isPackage != true
        }
    }

    // MARK: Adding

    public func stage(_ items: [URL]) throws -> VaultDraft {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            var unpacked: [String] = []
            for item in items {
                let name = item.lastPathComponent
                if item.pathExtension.lowercased() == "zip" {
                    let target = Self.unique(name: (name as NSString).deletingPathExtension, in: staging)
                    if let bytes = Archive.unzippedSize(of: item) { try LibraryBackup.checkSpace([(root, bytes)]) }
                    try Self.unzip(item, into: target)
                    unpacked.append(name)
                } else {
                    try fm.copyItem(at: item, to: Self.unique(name: name, in: staging))
                }
            }
            Self.removeLinks(in: staging)
            let files = Self.files(in: staging)
            guard !files.isEmpty else { throw VaultError.nothingToAdd }
            let styles = Self.styles(in: staging, files: files)
            return VaultDraft(staging: staging, sources: items.map(\.lastPathComponent), files: files, styles: styles,
                              kinds: Self.kinds(of: files), suggestedName: Self.suggestedName(styles: styles, items: items),
                              unpackedArchives: unpacked)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    public func discard(_ draft: VaultDraft) {
        guard draft.staging.deletingLastPathComponent().standardizedFileURL == root,
              draft.staging.lastPathComponent.hasPrefix(Self.stagingPrefix) else { return }
        try? FileManager.default.removeItem(at: draft.staging)
    }

    public func removeLeftoverStaging() {
        let fm = FileManager.default
        let owners = [root] + Self.visibleFolders(in: root)
        for folder in owners {
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                if folder == root, item.lastPathComponent.hasPrefix(Self.stagingPrefix) {
                    try? fm.removeItem(at: item)
                } else if item.lastPathComponent.hasPrefix(Self.renamingPrefix) {
                    // A license caught between two names: it comes back under a name of its own, never deleted.
                    try? fm.moveItem(at: item, to: Self.unique(name: "Recovered", in: folder))
                }
            }
        }
    }

    public func add(_ draft: VaultDraft, as license: VaultLicense) throws -> VaultLicense {
        var license = license
        license.styles = draft.styles
        let fm = FileManager.default
        let ownerFolder = root.appendingPathComponent(Self.folderName(for: license.owner, fallback: "Me"), isDirectory: true)
        try fm.createDirectory(at: ownerFolder, withIntermediateDirectories: true)
        let folder = Self.unique(name: Self.folderName(for: license.name, fallback: "License"), in: ownerFolder)
        try write(license, in: draft.staging)
        try fm.moveItem(at: draft.staging, to: folder)
        license.folder = folder
        return license
    }

    // MARK: Changing

    public func save(_ license: VaultLicense) throws -> VaultLicense {
        var license = license
        let fm = FileManager.default
        let ownerName = Self.folderName(for: license.owner, fallback: "Me")
        let name = Self.folderName(for: license.name, fallback: "License")
        var folder = license.folder
        var ownerFolder = folder.deletingLastPathComponent()
        if ownerFolder.lastPathComponent != ownerName {
            let wanted = root.appendingPathComponent(ownerName, isDirectory: true)
            if ownerFolder.lastPathComponent.lowercased() == ownerName.lowercased() {
                try Self.rename(ownerFolder, to: wanted)
                folder = wanted.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            } else {
                try fm.createDirectory(at: wanted, withIntermediateDirectories: true)
                let target = Self.unique(name: name, in: wanted)
                try fm.moveItem(at: folder, to: target)
                removeIfEmpty(ownerFolder)
                folder = target
            }
            ownerFolder = wanted
        }
        if folder.lastPathComponent != name {
            if folder.lastPathComponent.lowercased() == name.lowercased() {
                let target = ownerFolder.appendingPathComponent(name, isDirectory: true)
                try Self.rename(folder, to: target)
                folder = target
            } else {
                let target = Self.unique(name: name, in: ownerFolder)
                try fm.moveItem(at: folder, to: target)
                folder = target
            }
        }
        license.folder = folder
        try write(license, in: folder)
        return license
    }

    public func relink(_ license: VaultLicense) -> VaultLicense {
        var license = license
        license.styles = Self.styles(in: license.folder, files: Self.files(in: license.folder))
        return license
    }

    // Moves a license's folder to the Trash, never deletes it: the license may be the only proof of a purchase.
    public func trash(_ license: VaultLicense) throws -> URL {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: license.folder, resultingItemURL: &trashed)
        removeIfEmpty(license.folder.deletingLastPathComponent())
        return (trashed as URL?) ?? license.folder
    }

    public func putBack(_ license: VaultLicense, from trashed: URL) throws -> VaultLicense {
        var license = license
        let fm = FileManager.default
        let ownerFolder = license.folder.deletingLastPathComponent()
        try fm.createDirectory(at: ownerFolder, withIntermediateDirectories: true)
        let target = Self.unique(name: license.folder.lastPathComponent, in: ownerFolder)
        try fm.moveItem(at: trashed, to: target)
        license.folder = target
        return license
    }

    public func addFiles(_ items: [URL], to license: VaultLicense) throws -> VaultLicense {
        let fm = FileManager.default
        for item in items {
            let name = item.lastPathComponent
            if item.pathExtension.lowercased() == "zip" {
                if let bytes = Archive.unzippedSize(of: item) { try LibraryBackup.checkSpace([(root, bytes)]) }
                try Self.unzip(item, into: Self.unique(name: (name as NSString).deletingPathExtension, in: license.folder))
            } else {
                try fm.copyItem(at: item, to: Self.unique(name: name, in: license.folder))
            }
        }
        Self.removeLinks(in: license.folder)
        let license = relink(license)
        try write(license, in: license.folder)
        return license
    }

    private func write(_ license: VaultLicense, in folder: URL) throws {
        try Self.encoder.encode(license).write(to: folder.appendingPathComponent(Self.detailsFile), options: .atomic)
    }

    private func removeIfEmpty(_ folder: URL) {
        guard folder.deletingLastPathComponent().standardizedFileURL == root else { return }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? ["?"]
        guard items.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Names

    public static func folderName(for name: String, fallback: String = "") -> String {
        ActivationEngine.folderName(forFamily: name, fallback: fallback)
    }

    static func unique(name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    static func suggestedName(styles: [VaultLicense.Style], items: [URL]) -> String {
        var counts: [String: Int] = [:]
        for style in styles { counts[style.family, default: 0] += 1 }
        if let family = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key { return family }
        return items.first.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? ""
    }

    static func rename(_ item: URL, to target: URL) throws {
        let fm = FileManager.default
        let temporary = item.deletingLastPathComponent().appendingPathComponent(renamingPrefix + UUID().uuidString, isDirectory: true)
        try fm.moveItem(at: item, to: temporary)
        do {
            try fm.moveItem(at: temporary, to: target)
        } catch {
            try? fm.moveItem(at: temporary, to: item)
            throw error
        }
    }

    private static func removeLinks(in folder: URL) {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func unzip(_ archive: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: folder)
            throw VaultError.unpackFailed(archive.lastPathComponent)
        }
        let leftovers = folder.appendingPathComponent("__MACOSX")
        if FileManager.default.fileExists(atPath: leftovers.path) { try? FileManager.default.removeItem(at: leftovers) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
