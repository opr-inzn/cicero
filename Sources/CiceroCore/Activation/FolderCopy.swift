import Foundation

public enum FolderCopy {
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
}
