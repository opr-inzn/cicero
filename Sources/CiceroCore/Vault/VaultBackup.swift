import Foundation

extension Vault {
    public func backupInventory() -> [BackupVaultFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let base = root.standardizedFileURL.path + "/"
        var files: [BackupVaultFile] = []
        for ownerFolder in Self.visibleFolders(in: root) {
            for folder in Self.visibleFolders(in: ownerFolder) {
                guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { continue }
                for case let url as URL in enumerator where url.lastPathComponent != ".DS_Store" {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    let path = url.standardizedFileURL.path
                    guard path.hasPrefix(base) else { continue }
                    files.append(BackupVaultFile(path: String(path.dropFirst(base.count)), size: Int64(values.fileSize ?? 0)))
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func licenseCount(in files: [BackupVaultFile]) -> Int {
        Set(files.compactMap { file -> String? in
            let parts = file.path.split(separator: "/")
            return parts.count >= 3 ? parts[0] + "/" + parts[1] : nil
        }).count
    }
}

extension LibraryBackup {
    func copyVault(_ files: [BackupVaultFile], into folder: URL) throws -> [BackupVaultFile] {
        let fm = FileManager.default
        let vault = Vault(locations: locations)
        var written: [BackupVaultFile] = []
        for file in files {
            try Task.checkCancellation()
            guard Self.isPlainPath("/" + file.path) else { continue }
            let source = vault.root.appendingPathComponent(file.path, isDirectory: false)
            guard fm.fileExists(atPath: source.path) else { continue }
            let archivePath = "Vault/" + file.path
            let target = folder.appendingPathComponent(archivePath, isDirectory: false)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            var copied = file
            copied.archivePath = archivePath
            written.append(copied)
        }
        return written
    }

    public struct VaultRestoreResult: Sendable, Equatable {
        public var restored = 0
        public var skipped = 0
        public var failed = 0
    }

    // A backup is a file anyone could have made: only regular files from inside the unzipped folder, only into the Vault, and never over a license that's there.
    @concurrent
    public func restoreVault(_ contents: BackupContents) async -> VaultRestoreResult {
        var result = VaultRestoreResult()
        guard let files = contents.manifest.vault, !files.isEmpty else { return result }
        let fm = FileManager.default
        let vault = Vault(locations: locations)
        let existing = Set(vault.licenses().map(\.id))
        var groups: [String: [(rest: String, source: URL)]] = [:]
        var order: [String] = []
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard Self.isPlainPath("/" + file.path), parts.count >= 3, !parts[0].hasPrefix("."), !parts[1].hasPrefix("."),
                  let archivePath = file.archivePath, let source = Self.archivedFile(archivePath, in: contents.folder)
            else {
                result.failed += 1
                continue
            }
            let key = parts[0] + "/" + parts[1]
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((parts.dropFirst(2).joined(separator: "/"), source))
        }
        for key in order {
            let entries = groups[key]!
            let parts = key.split(separator: "/").map(String.init)
            if let details = entries.first(where: { $0.rest == Vault.detailsFile }),
               let data = try? Data(contentsOf: details.source),
               let id = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String,
               let uuid = UUID(uuidString: id), existing.contains(uuid) {
                result.skipped += 1
                continue
            }
            let staging = vault.root.appendingPathComponent(Vault.stagingPrefix + UUID().uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                for entry in entries {
                    let target = staging.appendingPathComponent(entry.rest, isDirectory: false)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: entry.source, to: target)
                }
                let ownerFolder = vault.root.appendingPathComponent(Vault.folderName(for: parts[0], fallback: "Me"), isDirectory: true)
                try fm.createDirectory(at: ownerFolder, withIntermediateDirectories: true)
                try fm.moveItem(at: staging, to: Vault.unique(name: Vault.folderName(for: parts[1], fallback: "License"), in: ownerFolder))
                result.restored += 1
            } catch {
                try? fm.removeItem(at: staging)
                result.failed += 1
            }
        }
        return result
    }
}
