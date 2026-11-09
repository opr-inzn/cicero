import Foundation

public enum DuplicateHandling: String, Codable, CaseIterable, Sendable {
    case ask
    case addCopy
    case skip
    // The choices before it, "useAdded" and "keepNewer", must never read as Replace: saved, they're read as Ask, so nothing goes to the Trash unchosen.
    case replace
}

public enum DuplicateChoice: String, CaseIterable, Sendable {
    case skip, addCopy, replace
}

public enum DuplicateVersion: Sendable {
    case newer, older, sameVersion
    case sameFile
}

public struct FileReplacement: Hashable, Sendable {
    public let old: String
    public let added: String

    public init(old: String, added: String) {
        self.old = old
        self.added = added
    }
}

public enum ReplaceBlock: Sendable {
    case differentFiles
    case unchangeable
}

public struct AddedDuplicate: Identifiable, Hashable, Sendable {
    public let family: String
    public let paths: [String]
    public let styles: [LibraryFace]
    public let addedFaces: [FontFace]
    public let version: DuplicateVersion
    public let replacements: [FileReplacement]
    public let replaceBlock: ReplaceBlock?

    public var id: String { family }

    public var canReplace: Bool { replaceBlock == nil }

    public var replacesSeveralCopies: Bool {
        Dictionary(grouping: replacements, by: \.added).values.contains { $0.count > 1 }
    }

    public var suggestion: DuplicateChoice {
        guard version == .newer else { return .skip }
        return canReplace ? .replace : .addCopy
    }

    public func startingChoice(for handling: DuplicateHandling) -> DuplicateChoice {
        choice(for: handling) ?? suggestion
    }

    public func choice(for handling: DuplicateHandling) -> DuplicateChoice? {
        switch handling {
        case .ask: nil
        case .addCopy: .addCopy
        case .skip: .skip
        case .replace: canReplace ? .replace : nil
        }
    }

    public var libraryVersions: [String] { Self.versions(styles.map(\.face)) }
    public var addedVersions: [String] { Self.versions(addedFaces) }

    private static func versions(_ faces: [FontFace]) -> [String] {
        Set(faces.compactMap(\.version).map(FontFace.displayVersion)).sorted { FontVersion.precedes($0, $1) }
    }
}

public enum AddedDuplicates {
    public static func faces(of paths: [String]) -> [String: [FontFace]] {
        Dictionary(paths.map { ($0, FontFileReader.faces(atPath: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    public static func find(in added: [String: [FontFace]], library: Library) -> [AddedDuplicate] {
        var styles: [String: (family: Int, style: LibraryFace)] = [:]
        for (index, family) in library.families.enumerated() {
            for face in family.faces where styles[face.face.postScriptName] == nil {
                styles[face.face.postScriptName] = (index, face)
            }
        }
        var matched: [Int: (paths: [String], styles: [LibraryFace], faces: [FontFace])] = [:]
        for path in added.keys.sorted() {
            for face in added[path] ?? [] {
                guard let (family, style) = styles[face.postScriptName],
                      style.face.path != path, !style.otherCopies.contains(path)
                else { continue }
                var entry = matched[family] ?? ([], [], [])
                if !entry.paths.contains(path) { entry.paths.append(path) }
                if !entry.styles.contains(where: { $0.id == style.id }) { entry.styles.append(style) }
                entry.faces.append(face)
                matched[family] = entry
            }
        }
        guard !matched.isEmpty else { return [] }
        // Every file the library has: the fonts in it, and one of its copies, to tell whether Cicero may change it.
        var namesIn: [String: Set<String>] = [:]
        var copyAt: [String: FaceCopy] = [:]
        for family in library.families {
            for face in family.faces {
                for copy in [FaceCopy(face)] + face.copies {
                    namesIn[copy.face.path, default: []].insert(copy.face.postScriptName)
                    if copyAt[copy.face.path] == nil { copyAt[copy.face.path] = copy }
                }
            }
        }
        return matched.keys.sorted().map { index in
            let entry = matched[index]!
            let (replacements, block) = replacements(of: entry.styles, by: entry.paths, added: added, namesIn: namesIn, copyAt: copyAt)
            return AddedDuplicate(family: library.families[index].name, paths: entry.paths, styles: entry.styles, addedFaces: entry.faces,
                                  version: compare(entry.faces, with: entry.styles), replacements: replacements, replaceBlock: block)
        }
    }

    private static func replacements(of styles: [LibraryFace], by paths: [String], added: [String: [FontFace]],
                                     namesIn: [String: Set<String>], copyAt: [String: FaceCopy]) -> ([FileReplacement], ReplaceBlock?) {
        let addedNames = Dictionary(uniqueKeysWithValues: paths.map { ($0, Set((added[$0] ?? []).map(\.postScriptName))) })
        var olds: [String] = []
        for path in styles.flatMap({ [$0.face.path] + $0.otherCopies }) where !olds.contains(path) && addedNames[path] == nil {
            olds.append(path)
        }
        var replacements: [FileReplacement] = []
        for old in olds {
            guard let copy = copyAt[old], mayReplace(copy) else { continue }
            guard let match = paths.first(where: { addedNames[$0] == namesIn[old] }) else { return ([], .differentFiles) }
            replacements.append(FileReplacement(old: old, added: match))
        }
        return replacements.isEmpty ? ([], .unchangeable) : (replacements, nil)
    }

    static func mayReplace(_ copy: FaceCopy) -> Bool {
        guard copy.app == nil, !ActivationEngine.isProtected(copy.face.path) else { return false }
        switch copy.state.source {
        case .macOS?, .allUsers?, .app?, .adobeFonts?: return false
        default: return true
        }
    }

    static func compare(_ added: [FontFace], with styles: [LibraryFace]) -> DuplicateVersion {
        let identical = added.allSatisfy { face in
            guard let style = styles.first(where: { $0.face.postScriptName == face.postScriptName }) else { return false }
            return ([style.face.path] + style.otherCopies).contains { isSameFile(face.path, $0) }
        }
        if identical { return .sameFile }
        func newest(_ faces: [FontFace]) -> [Double] {
            faces.compactMap(\.version).map(FontVersion.number).max { $0.lexicographicallyPrecedes($1) } ?? []
        }
        let (mine, theirs) = (newest(added), newest(styles.map(\.face)))
        if mine == theirs { return .sameVersion }
        return theirs.lexicographicallyPrecedes(mine) ? .newer : .older
    }

    private static func isSameFile(_ a: String, _ b: String) -> Bool {
        let fm = FileManager.default
        guard let sizeA = (try? fm.attributesOfItem(atPath: a))?[.size] as? Int,
              let sizeB = (try? fm.attributesOfItem(atPath: b))?[.size] as? Int,
              sizeA == sizeB
        else { return false }
        return fm.contentsEqual(atPath: a, andPath: b)
    }
}
