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
    /// Use it in place of the library's copy, which goes off.
    case useAdded
    /// Use it in place of the library's copy when its version is newer, else leave it out.
    case keepNewer
}

/// What's done with one added family the library has already.
public enum DuplicateChoice: String, CaseIterable, Sendable {
    case skip, addCopy, useAdded
}

/// How an added family's version compares with the library's copy of it.
public enum DuplicateVersion: Sendable {
    case newer, older, sameVersion
    /// The added files are the library's, byte for byte.
    case sameFile
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

    public var id: String { family }

    /// What the sheet starts with: the added copy when it's newer, else leaving it out.
    public var suggestion: DuplicateChoice { version == .newer ? .useAdded : .skip }

    /// What `handling` does with it; nil for Ask, which leaves it to the user.
    public func choice(for handling: DuplicateHandling) -> DuplicateChoice? {
        switch handling {
        case .ask: nil
        case .addCopy: .addCopy
        case .skip: .skip
        case .useAdded: .useAdded
        case .keepNewer: version == .newer ? .useAdded : .skip
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

/// Turning the library's copies of styles off for the added files to take over (Replace).
public struct DuplicateReplacement: Sendable {
    /// Per style of an added file that takes over a copy that's on: the added face to turn on and the library's copies
    /// to turn off. Added files that take over none are added as any other.
    public var switches: [CopySwitch]
    /// The families whose copies go off, in the order of the library's.
    public var families: [String]
    /// Files under Added Fonts whose every face an added file takes over: they stop being listed.
    public var forgotten: [String]
    /// The library's copy of a style stays on as well, being one Cicero can't turn off (macOS's, an app's or Adobe
    /// Fonts'), so apps may get that one.
    public var leavesOtherCopiesOn: Bool
    /// The library's copy of a style was in a Fonts folder, so the added one goes there too when Cicero asks each
    /// time how to activate.
    public var replacesInstalledCopy: Bool

    public var isEmpty: Bool { switches.allSatisfy { $0.target == nil && $0.others.isEmpty } }
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
        return matched.keys.sorted().map { index in
            let entry = matched[index]!
            return AddedDuplicate(family: library.families[index].name, paths: entry.paths, styles: entry.styles, addedFaces: entry.faces,
                                  version: compare(entry.faces, with: entry.styles))
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

    /// What using the added files of `duplicates` in place of the library's copies takes. Where the library has a style
    /// on, its copies Cicero can turn off go off (as deactivating does: a copy Cicero installed goes to the Trash when
    /// its original is in the library, any other in a Fonts folder to the Deactivated folder, one used where it is just
    /// goes off) and the added face goes on. `installing`, as when fonts are activated by copying or moving, an added
    /// file that takes over some style goes on whole; else only its styles that take over go on. Files under Added
    /// Fonts (`fontFiles`) that the added ones take over stop being listed. A copy in the Font Library (`fontLibrary`)
    /// counts as installed, like one in ~/Library/Fonts, and just goes off.
    public static func replacement(of duplicates: [AddedDuplicate], installing: Bool, library: Library, fontFiles: [String],
                                   fontLibrary: String = "") -> DuplicateReplacement {
        guard !duplicates.isEmpty else {
            return DuplicateReplacement(switches: [], families: [], forgotten: [], leavesOtherCopiesOn: false, replacesInstalledCopy: false)
        }
        struct Style {
            var family: String
            var face: FontFace
            var all: [FaceCopy]
            var off: [FaceCopy]
        }
        var styles: [Style] = []
        var leavesOtherCopiesOn = false
        var replaced = Set<String>()
        var candidates = Set<String>()
        let added = Set(duplicates.flatMap(\.paths))
        for duplicate in duplicates {
            for style in duplicate.styles {
                guard let face = duplicate.addedFaces.first(where: { $0.postScriptName == style.face.postScriptName }) else { continue }
                replaced.insert(style.face.postScriptName)
                let all = [FaceCopy(style)] + style.copies
                let on = all.filter(\.state.isActive)
                let off = on.filter(canTurnOff)
                if off.count < on.count { leavesOtherCopiesOn = true }
                styles.append(Style(family: duplicate.family, face: face, all: all, off: off))
                candidates.formUnion(all.map(\.face.path).filter { !added.contains($0) })
            }
        }
        let switching = Set(styles.filter { !$0.off.isEmpty }.map(\.face.path))
        let switches = styles.filter { !$0.off.isEmpty || installing && switching.contains($0.face.path) }.map { style in
            CopySwitch(target: LibraryFace(face: style.face, state: .inactive), others: style.off.map { $0.libraryFace(among: style.all) })
        }
        var families: [String] = []
        for style in styles where !style.off.isEmpty && !families.contains(style.family) { families.append(style.family) }
        let replacesInstalledCopy = styles.contains { style in
            style.off.contains { $0.state.source == .fontsFolder || !fontLibrary.isEmpty && $0.face.path.hasPrefix(fontLibrary + "/") }
        }
        // A file under Added Fonts goes only when every face in it is taken over, not a collection with others too.
        var names: [String: Set<String>] = [:]
        for face in library.families.flatMap(\.faces) {
            for copy in [FaceCopy(face)] + face.copies where candidates.contains(copy.face.path) {
                names[copy.face.path, default: []].insert(copy.face.postScriptName)
            }
        }
        let listed = Set(fontFiles)
        let forgotten = candidates.filter { listed.contains($0) && names[$0, default: []].isSubset(of: replaced) }.sorted()
        return DuplicateReplacement(switches: switches, families: families, forgotten: forgotten, leavesOtherCopiesOn: leavesOtherCopiesOn,
                                    replacesInstalledCopy: replacesInstalledCopy)
    }

    /// Copies Cicero turns off for an added one: on from a Fonts folder, where they are, for a while or by another app.
    /// Not macOS's, an app's, Adobe Fonts', nor one an application set has on while its app is open, which the set
    /// would turn on again.
    static func canTurnOff(_ copy: FaceCopy) -> Bool {
        guard copy.app == nil, !ActiveSource.isAdobeFonts(copy.face.path), let source = copy.state.source else { return false }
        return source.canDeactivate && source != .temporary(.whileAppsRun)
    }
}
