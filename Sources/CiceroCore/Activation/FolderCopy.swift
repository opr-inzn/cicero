import Foundation

public enum FolderCopy {
    public struct Result: Sendable {
        public var copiedRoot: URL
        public var copiedFonts: [String]
    }

    public struct FontGroup: Sendable {
        public var relativePath: String
        public var fontPaths: [String]
    }

    public static func fontStructure(in source: URL) -> [FontGroup] {
        let fm = FileManager.default
        let resolvedRoot = LibraryScanner.realPath(source.standardizedFileURL.path)
        let rootURL = URL(fileURLWithPath: resolvedRoot, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(
            at: rootURL, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let prefix = resolvedRoot + "/"
        var byDir: [String: [String]] = [:]
        for case let url as URL in enumerator {
            guard FontFormat.fileExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true
            else { continue }
            let path = url.path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            let dir = relative.lastIndex(of: "/").map { String(relative[..<$0]) } ?? ""
            let chosen = source.standardizedFileURL.path + "/" + relative
            byDir[dir, default: []].append(chosen)
        }
        return byDir.keys.sorted().map { FontGroup(relativePath: $0, fontPaths: byDir[$0] ?? []) }
    }

    public static func copyFontFolders(from source: URL, into destination: URL) throws -> Result? {
        let fm = FileManager.default
        let resolvedRoot = LibraryScanner.realPath(source.standardizedFileURL.path)
        let rootURL = URL(fileURLWithPath: resolvedRoot, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(
            at: rootURL, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let prefix = resolvedRoot + "/"
        var fontDirs = Set<String>()
        var filesByDir: [String: [URL]] = [:]
        for case let url as URL in enumerator {
            // Never follow symlinks out of a dropped folder.
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
            guard values.isRegularFile == true else { continue }
            let path = url.path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            let dir = relative.lastIndex(of: "/").map { String(relative[..<$0]) } ?? ""
            filesByDir[dir, default: []].append(url)
            if FontFormat.fileExtensions.contains(url.pathExtension.lowercased()) {
                fontDirs.insert(dir)
            }
        }
        guard !fontDirs.isEmpty else { return nil }
        let targetRoot = uniqueDirectoryURL(named: source.lastPathComponent, in: destination)
        var copiedFonts: [String] = []
        do {
            try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            for dir in fontDirs.sorted() {
                let targetDir = dir.isEmpty ? targetRoot : targetRoot.appendingPathComponent(dir, isDirectory: true)
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                for file in filesByDir[dir] ?? [] {
                    let target = targetDir.appendingPathComponent(file.lastPathComponent, isDirectory: false)
                    try fm.copyItem(at: file, to: target)
                    if FontFormat.fileExtensions.contains(target.pathExtension.lowercased()) {
                        copiedFonts.append(target.path)
                    }
                }
            }
            return Result(copiedRoot: targetRoot, copiedFonts: copiedFonts)
        } catch {
            try? fm.removeItem(at: targetRoot)
            throw error
        }
    }

    public static func uniqueDirectoryURL(named name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let first = folder.appendingPathComponent(name, isDirectory: true)
        if !fm.fileExists(atPath: first.path) { return first }
        var n = 2
        while true {
            let candidate = folder.appendingPathComponent("\(name) \(n)", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
