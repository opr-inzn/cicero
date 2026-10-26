import Foundation

/// What to do with a font file added one at a time when the library has its fonts already, from another file, like a
/// newer version of a font that's installed (Settings → General).
public enum DuplicateHandling: String, Codable, CaseIterable, Sendable {
    /// Ask, family by family, in a sheet.
    case ask
    /// List or install it beside the library's copy, as Cicero did before there was a choice.
    case addCopy
    /// Leave it out.
    case skip
    /// Put it in place of the library's copy, which goes to the Trash (see `AddedDuplicate.replacements`); asking first
    /// when that's more than one file, or can't be done. The choices there were before, which turned the library's copy
    /// off ("useAdded", and "keepNewer" for a newer one), are read as Ask, so nothing goes to the Trash unchosen.
    case replace
}

/// What's done with one added family the library has already.
public enum DuplicateChoice: String, CaseIterable, Sendable {
    case skip, addCopy, replace
}

/// How an added family's version compares with the library's copy of it.
public enum DuplicateVersion: Sendable {
    case newer, older, sameVersion
    /// The added files are the library's, byte for byte.
    case sameFile
}

/// One of the library's files an added one takes the place of: the old one goes to the Trash, and a copy of the added
/// one goes where it was, under its name.
public struct FileReplacement: Hashable, Sendable {
    public let old: String
    public let added: String

    public init(old: String, added: String) {
        self.old = old
        self.added = added
    }
}

/// Why an added family can't take the place of the library's copy.
public enum ReplaceBlock: Sendable {
    /// The library's files and the added ones hold the fonts differently, as one collection against a file each.
    case differentFiles
    /// Every copy is one Cicero doesn't change: macOS's, an app's, Adobe Fonts' or one in an app's own folder.
    case unchangeable
}

/// An added family the library has already, from other files: some of its styles, or all of them.
public struct AddedDuplicate: Identifiable, Hashable, Sendable {
    /// The family's name in the library.
    public let family: String
    /// The added files with styles of it the library has.
    public let paths: [String]
    /// The library's styles the added files have, as the library has them, with their other copies.
    public let styles: [LibraryFace]
    /// The added files' faces of those styles.
    public let addedFaces: [FontFace]
    public let version: DuplicateVersion
    /// What Replace does: each of the library's files with these styles that Cicero may change, and the added file with
    /// exactly its fonts. Empty when it can't be done (`replaceBlock`).
    public let replacements: [FileReplacement]
    public let replaceBlock: ReplaceBlock?

    public var id: String { family }

    public var canReplace: Bool { replaceBlock == nil }

    /// Whether Replace puts an added file in more than one place, as when the library has a font in a client's folder
    /// and a copy of it in ~/Library/Fonts: the user is warned first.
    public var replacesSeveralCopies: Bool {
        Dictionary(grouping: replacements, by: \.added).values.contains { $0.count > 1 }
    }

    /// What the sheet starts with: a newer one in place of the library's copy, or beside it when that can't be done;
    /// else leaving it out.
    public var suggestion: DuplicateChoice {
        guard version == .newer else { return .skip }
        return canReplace ? .replace : .addCopy
    }

    /// What `handling` does with it; nil for Ask, and for Replace when it can't be done, which leave it to the user.
    public func choice(for handling: DuplicateHandling) -> DuplicateChoice? {
        switch handling {
        case .ask: nil
        case .addCopy: .addCopy
        case .skip: .skip
        case .replace: canReplace ? .replace : nil
        }
    }

    /// The versions of the library's copies, newest last, without the label: ["1.002"].
    public var libraryVersions: [String] { Self.versions(styles.map(\.face)) }
    /// The versions of the added files' faces, newest last.
    public var addedVersions: [String] { Self.versions(addedFaces) }

    private static func versions(_ faces: [FontFace]) -> [String] {
        Set(faces.compactMap(\.version).map(FontFace.displayVersion)).sorted { FontVersion.precedes($0, $1) }
    }
}

/// Finds the fonts added files have that the library has already, from other files, and what using the added ones in
/// their place takes.
public enum AddedDuplicates {
    /// The faces in font files, by path. Reads the files: call it off the main thread.
    public static func faces(of paths: [String]) -> [String: [FontFace]] {
        Dictionary(paths.map { ($0, FontFileReader.faces(atPath: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// The families in `added` (added files the library doesn't list yet, with their faces) the library has already:
    /// a face counts when a style in the library has its PostScript name, from another file. In the order of the
    /// library's families. Compares files with the library's copies, so call it off the main thread.
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

    /// Replace, one to one: each of the library's files with these styles goes to the Trash for the added file with
    /// exactly its fonts, by PostScript name. Files Cicero doesn't change stay, beside it; when a file has no such match,
    /// it can't be done at all.
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

    /// Whether Cicero may put another file in a copy's place: not macOS's, an app's, Adobe Fonts', one in an app's own
    /// folder, one on for all users, nor one an application set has on while its app is open.
    static func mayReplace(_ copy: FaceCopy) -> Bool {
        guard copy.app == nil, !ActivationEngine.isProtected(copy.face.path) else { return false }
        switch copy.state.source {
        case .macOS?, .allUsers?, .app?, .adobeFonts?, .temporary(.whileAppsRun)?: return false
        default: return true
        }
    }

    /// The same files as the library's, else the newest added version against the newest of the library's copies.
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
