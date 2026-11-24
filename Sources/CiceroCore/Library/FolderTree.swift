import Foundation

public struct FolderTree: Equatable, Sendable {
    public struct Node: Hashable, Sendable {
        public let name: String
        public let relativePath: String
        public let children: [String]
        public let families: Set<String>
        public let faceCount: Int

        public init(name: String, relativePath: String, children: [String], families: Set<String>, faceCount: Int) {
            self.name = name
            self.relativePath = relativePath
            self.children = children
            self.families = families
            self.faceCount = faceCount
        }
    }

    public let rootChildren: [String]
    public let nodes: [String: Node]

    public init(rootChildren: [String] = [], nodes: [String: Node] = [:]) {
        self.rootChildren = rootChildren
        self.nodes = nodes
    }

    public var isEmpty: Bool { rootChildren.isEmpty }

    public func node(_ relativePath: String) -> Node? { nodes[relativePath] }

    public static func ancestors(of relativePath: String) -> [String] {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return [] }
        var result: [String] = []
        var current = ""
        for part in parts.dropLast() {
            current = current.isEmpty ? String(part) : current + "/" + part
            result.append(current)
        }
        return result
    }

    public static func build(families: [Family], folders: [WatchedFolder]) -> [UUID: FolderTree] {
        let watched = folders.filter {
            $0.id != WatchedFolder.adobeAppsID && $0.id != WatchedFolder.adobeFontsID
                && $0.id != WatchedFolder.addedFilesID && $0.id != WatchedFolder.fontLibraryID
                && $0.id != WatchedFolder.inactiveFolderID
        }
        guard !watched.isEmpty else { return [:] }
        struct Root {
            var id: UUID
            var prefixes: [String]
        }
        let roots = watched.map { Root(id: $0.id, prefixes: FolderPath.prefixes(of: $0)) }
        struct Builder {
            var rootChildren: Set<String> = []
            var children: [String: Set<String>] = [:]
            var families: [String: Set<String>] = [:]
            var faceCounts: [String: Int] = [:]
        }
        var builders: [UUID: Builder] = [:]
        for family in families {
            for face in family.faces {
                var paths = [face.face.path]
                for copy in face.copies { paths.append(copy.face.path) }
                for root in roots {
                    var hit: Set<String> = []
                    for path in paths {
                        guard let rel = relativeDirectory(of: path, prefixes: root.prefixes), !rel.isEmpty else { continue }
                        let parts = rel.split(separator: "/")
                        var current = ""
                        var parent = ""
                        for part in parts {
                            current = current.isEmpty ? String(part) : current + "/" + part
                            if hit.insert(current).inserted {
                                if parent.isEmpty {
                                    builders[root.id, default: Builder()].rootChildren.insert(current)
                                } else {
                                    builders[root.id, default: Builder()].children[parent, default: []].insert(current)
                                }
                                builders[root.id, default: Builder()].families[current, default: []].insert(family.id)
                                builders[root.id, default: Builder()].faceCounts[current, default: 0] += 1
                            }
                            parent = current
                        }
                    }
                }
            }
        }
        var trees: [UUID: FolderTree] = [:]
        for (id, builder) in builders where !builder.rootChildren.isEmpty {
            func sorted(_ paths: Set<String>) -> [String] {
                paths.sorted { a, b in
                    let nameA = (a as NSString).lastPathComponent
                    let nameB = (b as NSString).lastPathComponent
                    let order = nameA.localizedStandardCompare(nameB)
                    return order == .orderedSame ? a < b : order == .orderedAscending
                }
            }
            var nodes: [String: Node] = [:]
            nodes.reserveCapacity(builder.families.count)
            for (rel, familyIDs) in builder.families {
                let name = (rel as NSString).lastPathComponent
                let kids = sorted(builder.children[rel] ?? [])
                nodes[rel] = Node(name: name, relativePath: rel, children: kids, families: familyIDs, faceCount: builder.faceCounts[rel] ?? 0)
            }
            trees[id] = FolderTree(rootChildren: sorted(builder.rootChildren), nodes: nodes)
        }
        return trees
    }

    private static func relativeDirectory(of path: String, prefixes: [String]) -> String? {
        for prefix in prefixes where path.hasPrefix(prefix) {
            let relative = String(path.dropFirst(prefix.count))
            guard let slash = relative.lastIndex(of: "/") else { return nil }
            return String(relative[..<slash])
        }
        return nil
    }
}

public enum FolderPath {
    public static func prefixes(of folder: WatchedFolder, relativePath: String? = nil) -> [String] {
        let base = relativePath.map { folder.path + "/" + $0 } ?? folder.path
        let real = LibraryScanner.realPath(base)
        return real == base ? [base + "/"] : [base + "/", real + "/"]
    }

    public static func relationship(between directory: URL, and item: URL) -> FileManager.URLRelationship? {
        var relationship: FileManager.URLRelationship = .other
        do {
            try FileManager.default.getRelationship(&relationship, ofDirectoryAt: directory.standardizedFileURL, toItemAt: item.standardizedFileURL)
            return relationship
        } catch {
            let a = directory.standardizedFileURL.path
            let b = item.standardizedFileURL.path
            if a == b { return .same }
            if b.hasPrefix(a + "/") { return .contains }
            let ra = LibraryScanner.realPath(a), rb = LibraryScanner.realPath(b)
            if ra == rb { return .same }
            if rb.hasPrefix(ra + "/") { return .contains }
            return nil
        }
    }

    public static func relativePath(of item: URL, inside directory: URL) -> String? {
        guard relationship(between: directory, and: item) == .contains else { return nil }
        let dirPath = directory.standardizedFileURL.path
        let itemPath = item.standardizedFileURL.path
        if itemPath.hasPrefix(dirPath + "/") {
            return String(itemPath.dropFirst(dirPath.count + 1))
        }
        let realDir = LibraryScanner.realPath(dirPath)
        let realItem = LibraryScanner.realPath(itemPath)
        if realItem.hasPrefix(realDir + "/") {
            return String(realItem.dropFirst(realDir.count + 1))
        }
        let dirParts = dirPath.split(separator: "/")
        let itemParts = itemPath.split(separator: "/")
        guard itemParts.count > dirParts.count else { return nil }
        let matches = zip(dirParts, itemParts).allSatisfy { String($0).caseInsensitiveCompare(String($1)) == .orderedSame }
        return matches ? itemParts.dropFirst(dirParts.count).joined(separator: "/") : nil
    }

    public static func fileID(of path: String) -> UInt64? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return info.st_ino
    }
}
