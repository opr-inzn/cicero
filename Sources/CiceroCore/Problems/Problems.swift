import CoreText
import Foundation

public enum ProblemKind: String, CaseIterable, Sendable {
    case installedTwice, missing, unreadable, external, duplicates, sharedNames

    /// Worth knowing, rarely worth acting on: not counted in the sidebar badge and shown collapsed.
    public var isMinor: Bool { self == .sharedNames }

    /// Whether the files are copies of one font, shown by folder. Shared names lists different fonts, one file each.
    public var groupsFilesByFolder: Bool { self != .sharedNames }

    public var title: String {
        switch self {
        case .installedTwice: "Installed Twice"
        case .sharedNames: "Shared Style Names"
        case .missing: "Missing Files"
        case .unreadable: "Damaged or Unreadable Files"
        case .external: "Fonts on External Disks"
        case .duplicates: "Duplicates"
        }
    }

    /// One or two plain sentences shown above the group.
    public var explanation: String {
        switch self {
        case .installedTwice:
            "The same font is active from more than one file. macOS uses only one of them, so apps may get an older version. Keep one and remove the other copies."
        case .sharedNames:
            "Each of these fonts has its own main PostScript name (name ID 6), but variable fonts also give each named style a PostScript name of its own, and some use just “Bold” or “Light”. When two fonts use the same one, macOS gives it to only one of them, and a document set in the other may open in the wrong font. Usually there’s nothing to do; if it happens, turn off the font you don’t need or get an updated version."
        case .missing:
            "Cicero remembers these files, but they’re gone. Fonts used where they were stop working when their files move or their disk is unplugged."
        case .unreadable:
            "Cicero couldn’t read these files. They may be damaged, or not font files at all."
        case .external:
            "These fonts are used from a disk that can be unplugged, or a server. They turn off while it’s gone."
        case .duplicates:
            "The same font is in one of your folders more than once. Copies in different folders, like each client’s, aren’t listed: choose between them with Use Copy From."
        }
    }
}

/// One file involved in a problem.
public struct ProblemFile: Hashable, Sendable {
    public var path: String
    public var version: String?
    public var modified: Date?
    /// Where it is or how it's active, e.g. "In your Fonts folder", "Used where it is".
    public var detail: String
    /// Shown instead of the file name, e.g. the font's family.
    public var title: String?
    /// What about the file matters here, e.g. the styles involved.
    public var note: String?
    /// The PostScript names macOS gives this file when an app asks for them, of the names the problem is about.
    public var preferredFor: [String]
    /// The styles behind `preferredFor` when macOS gives this file only some of its names and the rest to other files,
    /// e.g. "Light Oblique and Bold Oblique".
    public var preferredStyles: String?

    public init(path: String, version: String?, modified: Date?, detail: String, title: String? = nil, note: String? = nil,
                preferredFor: [String] = [], preferredStyles: String? = nil) {
        self.path = path
        self.version = version
        self.modified = modified
        self.detail = detail
        self.title = title
        self.note = note
        self.preferredFor = preferredFor
        self.preferredStyles = preferredStyles
    }
}

/// Something the user can do about a problem. The app carries these out.
public enum ProblemFix: Hashable, Sendable {
    case reveal([String])
    /// Deactivate these active copies (installed copies go to the Trash or the Deactivated folder).
    case deactivate([FaceID])
    /// Move these files to the Trash: never protected paths, and only spare copies (every face in them,
    /// of every family, has a copy in another file), or files nothing can read.
    case trash([String])
    /// Forget a missing in-place registration and unregister it.
    case forgetInPlace(String)
    /// Forget a missing installed copy.
    case forgetInstalledCopy(String)
    case removeFromSet(UUID, family: String)
    /// Copy a font used from an external disk into ~/Library/Fonts and stop using it in place.
    case installCopy(String)

    public var title: String {
        switch self {
        case .reveal: "Reveal"
        case .deactivate: "Deactivate"
        case .trash(let paths): paths.count == 1 ? "Move to Trash" : "Move Extra Copies to Trash"
        case .forgetInPlace, .forgetInstalledCopy: "Forget"
        case .removeFromSet: "Remove from Set"
        case .installCopy: "Install a Copy Instead"
        }
    }
}

public struct Problem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ProblemKind
    /// e.g. the family names involved.
    public var title: String
    /// The family the problem is about, when it's about one: removing its files names the other families in them.
    public var family: String?
    /// e.g. "Active from 2 files."
    public var summary: String
    public var files: [ProblemFile]
    /// Fixes for the problem as a whole.
    public var fixes: [ProblemFix]
    /// Fixes for single files, by path.
    public var fileFixes: [String: [ProblemFix]]
    /// Fixes for all the files in a folder that holds more than one of them, by the folder's path.
    public var folderFixes: [String: [ProblemFix]]
    /// The folder with the newest version, when every other folder's files are older: usually the copy to keep.
    public var newestFolder: String?

    public init(id: String, kind: ProblemKind, title: String, family: String? = nil, summary: String, files: [ProblemFile], fixes: [ProblemFix],
                fileFixes: [String: [ProblemFix]], folderFixes: [String: [ProblemFix]] = [:], newestFolder: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.family = family
        self.summary = summary
        self.files = files
        self.fixes = fixes
        self.fileFixes = fileFixes
        self.folderFixes = folderFixes
        self.newestFolder = newestFolder
    }

    /// The files by the folder they're in, in order.
    public var folders: [ProblemFolder] {
        var folders: [ProblemFolder] = []
        for file in files {
            let path = (file.path as NSString).deletingLastPathComponent
            if let index = folders.firstIndex(where: { $0.path == path }) {
                folders[index].files.append(file)
            } else {
                folders.append(ProblemFolder(path: path, files: [file]))
            }
        }
        return folders
    }
}

/// The files of a problem that are in one folder.
public struct ProblemFolder: Hashable, Sendable {
    public var path: String
    public var files: [ProblemFile]
}

public enum ProblemDetector {
    /// Finds problems in the library. Reads font versions from disk for the files involved, so call it off the main thread.
    /// `fileForName` is the file macOS uses for a PostScript name, if any.
    public static func detect(in library: Library, data: UserData, locations: Locations,
                              fileForName: @escaping (String) -> String? = activeFile(named:)) -> [Problem] {
        var context = Context(library: library, data: data, locations: locations, fileForName: fileForName)
        var problems = installedTwice(&context) + sharedNames(&context) + duplicates(&context) + missing(&context) + unreadable(&context) + external(&context)
        let order = Dictionary(uniqueKeysWithValues: ProblemKind.allCases.enumerated().map { ($1, $0) })
        problems.sort { a, b in
            if a.kind != b.kind { return order[a.kind]! < order[b.kind]! }
            switch a.title.localizedStandardCompare(b.title) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.id < b.id
            }
        }
        return problems
    }

    /// The file macOS uses when an app asks for a font by PostScript name, or nil when no active font has the name.
    public static func activeFile(named postScriptName: String) -> String? {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        guard CTFontCopyPostScriptName(font) as String == postScriptName else { return nil }
        return (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path
    }

    private struct Context {
        let library: Library
        let data: UserData
        let locations: Locations
        let folders: [WatchedFolder]
        let fileForName: (String) -> String?
        /// Which files can go without taking a face's last copy with them.
        var copies: SpareCopies
        private var versions: [String: String?] = [:]

        init(library: Library, data: UserData, locations: Locations, fileForName: @escaping (String) -> String?) {
            self.library = library
            self.data = data
            self.locations = locations
            self.fileForName = fileForName
            folders = data.scannedFolders()
            copies = SpareCopies(library)
        }

        mutating func file(_ path: String) -> ProblemFile {
            ProblemFile(path: path, version: version(of: path), modified: Self.modified(path), detail: detail(of: path))
        }

        mutating func version(of path: String) -> String? {
            if let known = versions[path] { return known }
            let version = FontFileReader.faces(atPath: path).first?.version
            versions[path] = version
            return version
        }

        static func modified(_ path: String) -> Date? {
            try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        func detail(of path: String) -> String {
            if library.activePaths.contains(path) {
                switch LibraryScanner.activeSource(of: path, locations: locations, records: data.records) {
                case .macOS: return "Comes with macOS"
                case .allUsers: return "Installed for all users"
                case .app: return "Comes with an app"
                case .adobeFonts: return "Adobe Fonts"
                case .fontsFolder: return "In your Fonts folder"
                case .inPlace: return "Used where it is"
                case .temporary(.untilQuit): return "Active until Cicero quits"
                case .temporary(.whileAppsRun): return "Active while its app is open"
                case .otherApp: return "Activated by another app"
                }
            }
            if path.hasPrefix(locations.deactivated.path + "/") { return "In Cicero’s Deactivated folder" }
            if let folder = folders.first(where: { path.hasPrefix($0.path + "/") }) {
                return folder.appName.map { "Active in \(FaceState.appDescription($0))" } ?? "In \(folder.displayName)"
            }
            return "Not activated"
        }

        /// Where a missing file may only be out of reach for now: "on “Server”, which isn’t connected" for a disk
        /// under /Volumes that isn't there, or the like for a watched folder Cicero can't read. nil when it's just gone.
        func unreachable(_ path: String) -> String? {
            if let volume = Reachability.disconnectedVolume(of: path) { return "on “\(volume)”, which isn’t connected" }
            guard let folder = folders.first(where: { library.unavailableFolders[$0.id] != nil && path.hasPrefix($0.path + "/") }) else { return nil }
            return library.unavailableFolders[folder.id] == .noAccess
                ? "in “\(folder.displayName)”, which Cicero isn’t allowed to read"
                : "in “\(folder.displayName)”, which can’t be found"
        }

        func isInWatchedFolder(_ path: String) -> Bool {
            path.hasPrefix(locations.deactivated.path + "/") || folders.contains { path.hasPrefix($0.path + "/") }
        }

        /// "Version 2.001" → [2.001], "Version 5.01.2" → [5.01, 2], for picking the newest copy: compare with
        /// `lexicographicallyPrecedes`. Empty when there's no version.
        func versionNumber(of path: String) -> [Double] {
            guard let version = versions[path] ?? nil else { return [] }
            return FontVersion.number(version)
        }

        /// The folder whose files include the newest version, when every other folder's are all older.
        func newestFolder(of paths: [String]) -> String? {
            let ranked = Dictionary(grouping: paths) { ($0 as NSString).deletingLastPathComponent }
                .mapValues { $0.map(versionNumber).max { $0.lexicographicallyPrecedes($1) } ?? [] }
                .sorted { $1.value.lexicographicallyPrecedes($0.value) }
            guard ranked.count > 1, ranked[1].value.lexicographicallyPrecedes(ranked[0].value) else { return nil }
            return ranked[0].key
        }
    }

    // MARK: Installed twice

    /// The same font active from more than one file, grouped by family.
    private static func installedTwice(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        for family in context.library.families {
            var paths: [String] = []
            var copies: [[String]] = []
            var deactivatable: [String: FaceID] = [:]
            for face in family.faces {
                let active = ([face.face.path] + face.otherCopies).filter { context.library.activePaths.contains($0) }
                guard active.count >= 2 else { continue }
                copies.append(active)
                for path in active where !paths.contains(path) { paths.append(path) }
                if face.canDeactivate, deactivatable[face.face.path] == nil { deactivatable[face.face.path] = face.id }
            }
            // Copies that all come with macOS are macOS's business: there's nothing to do about them.
            guard !paths.isEmpty, !paths.allSatisfy(ActivationEngine.isProtected) else { continue }
            paths.sort()
            var fileFixes: [String: [ProblemFix]] = [:]
            for path in paths {
                var fixes: [ProblemFix] = [.reveal([path])]
                if let id = deactivatable[path] {
                    fixes.append(.deactivate([id]))
                } else if !ActivationEngine.isProtected(path), context.copies.areSpare([path]) {
                    // Not when the file also holds styles, or other families, that are nowhere else.
                    fixes.append(.trash([path]))
                }
                fileFixes[path] = fixes
            }
            let files = paths.map { context.file($0) }
            // Turning a folder's files off at once must leave every style active from another copy, and
            // removing them every face in them a copy elsewhere.
            let folderFixes = folderFixes(paths, fileFixes) { folder, trashing in
                copies.allSatisfy { $0.contains { !folder.contains($0) } } && (!trashing || context.copies.areSpare(folder))
            }
            problems.append(Problem(
                id: "installedTwice.\(family.id)", kind: .installedTwice, title: family.name, family: family.id,
                summary: copies.count == 1 ? "Active from \(paths.count) files." : "\(copies.count) styles active from \(paths.count) files.",
                files: files, fixes: [], fileFixes: fileFixes, folderFixes: folderFixes,
                newestFolder: context.newestFolder(of: paths)
            ))
        }
        return problems
    }

    // MARK: Shared names

    /// Different families whose active faces use the same PostScript names (typically bare names like "Bold" that
    /// variable fonts give their named instances). Families linked by any shared name are one problem: which of them
    /// to keep on is one decision.
    private static func sharedNames(_ context: inout Context) -> [Problem] {
        struct Face {
            var path: String
            var copies: [String]
            var family: String
            var style: String
            /// Upright before italic, then by weight (from the style name: a variable font's named styles share one OS/2
            /// weight): the order styles are listed in.
            var rank: Int
            var id: FaceID?
        }
        struct File {
            var families: [String] = []
            var styles: [(name: String, rank: Int)] = []
            var names: Set<String> = []
            var won: [String] = []
            var wonStyles: [(name: String, rank: Int)] = []
            var id: FaceID?
        }
        var clashes: [String: [Face]] = [:]
        for family in context.library.families {
            for face in family.faces where face.state.isActive {
                clashes[face.face.postScriptName, default: []].append(Face(
                    path: face.face.path, copies: face.otherCopies, family: family.id, style: face.face.styleName,
                    rank: (face.face.isItalic ? 10_000 : 0) + (StyleName(face.face.styleName).weight ?? face.face.weight),
                    id: face.canDeactivate ? face.id : nil
                ))
            }
        }
        clashes = clashes.filter { _, faces in
            Set(faces.map(\.family)).count >= 2 && !faces.allSatisfy { ActivationEngine.isProtected($0.path) }
        }

        // Families that share a name, and the families those share a name with, and so on.
        var components: [Set<String>] = []
        for faces in clashes.values {
            var linked = Set(faces.map(\.family))
            components.removeAll { component in
                guard !component.isDisjoint(with: linked) else { return false }
                linked.formUnion(component)
                return true
            }
            components.append(linked)
        }

        return components.map { component in
            let names = clashes.keys.filter { component.contains(clashes[$0]![0].family) }
                .map { (name: $0, rank: clashes[$0]!.map(\.rank).min()!) }
                .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name < $1.name }
                .map(\.name)
            var files: [String: File] = [:]
            for name in names {
                let faces = clashes[name]!
                for face in faces {
                    var file = files[face.path] ?? File()
                    if !file.families.contains(face.family) { file.families.append(face.family) }
                    if !file.styles.contains(where: { $0.name == face.style }) { file.styles.append((face.style, face.rank)) }
                    file.names.insert(name)
                    file.id = Self.first(file.id, face.id)
                    files[face.path] = file
                }
                // An app asking for the name gets this file (or another active copy of the same face).
                if let path = context.fileForName(name), let face = faces.first(where: { $0.path == path || $0.copies.contains(path) }) {
                    files[face.path]?.won.append(name)
                    if !files[face.path]!.wonStyles.contains(where: { $0.name == face.style }) { files[face.path]?.wonStyles.append((face.style, face.rank)) }
                }
            }
            func ordered(_ styles: [(name: String, rank: Int)]) -> String {
                joined(abridged(styles.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name < $1.name }.map(\.name)))
            }
            let problemFiles = files.map { path, file in
                // Getting only some of its names, a file says which: "Preferred" alone would read as all of them.
                let isPartly = !file.won.isEmpty && file.won.count < file.names.count
                return ProblemFile(path: path, version: nil, modified: nil, detail: context.detail(of: path),
                                   title: joined(sorted(file.families)), note: ordered(file.styles), preferredFor: file.won,
                                   preferredStyles: isPartly ? ordered(file.wonStyles) : nil)
            }.sorted { a, b in
                let order = a.title!.localizedStandardCompare(b.title!)
                return order == .orderedSame ? a.path < b.path : order == .orderedAscending
            }

            let families = sorted(Array(component))
            var summary = names.count == 1
                ? "One style in each has the same PostScript name, \(names[0])."
                : "Some of their styles have the same PostScript names: \(joined(abridged(names)))."
            let winners = problemFiles.filter { !$0.preferredFor.isEmpty }
            if winners.map(\.preferredFor.count).reduce(0, +) == names.count {
                summary += " macOS gives \(names.count == 1 ? "that name" : "those names") to \(joined(winners.map { $0.title! }))."
            }
            return Problem(
                id: "sharedNames.\(families.joined(separator: "|"))", kind: .sharedNames,
                title: joined(families.count > 4 ? Array(families.prefix(3)) + ["\(families.count - 3) more"] : families),
                summary: summary, files: problemFiles, fixes: [],
                fileFixes: Dictionary(uniqueKeysWithValues: problemFiles.map { file in
                    (file.path, [ProblemFix.reveal([file.path])] + (files[file.path]!.id.map { [.deactivate([$0])] } ?? []))
                })
            )
        }
    }

    /// The first six of more than seven items, then "N more".
    private static func abridged(_ items: [String]) -> [String] {
        items.count > 7 ? Array(items.prefix(6)) + ["\(items.count - 6) more"] : items
    }

    /// In Finder's order.
    private static func sorted(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Reveal for each folder holding more than one of the paths, and the files' own Move to Trash or Deactivate
    /// for all of them at once when every file has it and `canCombine` allows it for the folder's files (and
    /// whether that's trashing them).
    private static func folderFixes(_ paths: [String], _ fileFixes: [String: [ProblemFix]],
                                    canCombine: (_ files: Set<String>, _ trashing: Bool) -> Bool) -> [String: [ProblemFix]] {
        var result: [String: [ProblemFix]] = [:]
        for (folder, files) in Dictionary(grouping: paths, by: { ($0 as NSString).deletingLastPathComponent }) where files.count > 1 {
            var fixes: [ProblemFix] = [.reveal(files)]
            var trash: [String] = []
            var deactivate: [FaceID] = []
            for fix in files.flatMap({ fileFixes[$0] ?? [] }) {
                switch fix {
                case .trash(let paths): trash += paths
                case .deactivate(let ids): deactivate += ids
                default: break
                }
            }
            if trash.count == files.count {
                if canCombine(Set(files), true) { fixes.append(.trash(trash)) }
            } else if deactivate.count == files.count {
                if canCombine(Set(files), false) { fixes.append(.deactivate(deactivate)) }
            }
            result[folder] = fixes
        }
        return result
    }

    private static func first(_ a: FaceID?, _ b: FaceID?) -> FaceID? {
        guard let a, let b else { return a ?? b }
        return min(a, b)
    }

    /// "A and B", "A, B and C".
    private static func joined(_ items: [String]) -> String {
        guard items.count > 1 else { return items.joined() }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    // MARK: Duplicates

    /// The same font more than once among the inactive files in one place in the user's folders. Copies in
    /// different places, like each client's folder, are for Use Copy From to choose between (see
    /// `CopyChooser.places`), not spares.
    private static func duplicates(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        let records = context.data.records
        let origins = Set(records.installedCopies.values)
        for family in context.library.families {
            // The family's copies Use Copy From would list, each in its place.
            var copies: [(style: FaceID, folder: String)] = []
            var copyPaths: [(style: FaceID, path: String)] = []
            for face in family.faces {
                for path in [face.face.path] + face.otherCopies where !ActivationEngine.isProtected(path) {
                    let origin = records.installedCopies[path]
                    let isActive = context.library.activePaths.contains(path)
                    guard origin != nil || (isActive ? records.inPlace.contains(path) || records.temporary[path] != nil : context.isInWatchedFolder(path))
                    else { continue }
                    copies.append((face.id, ((origin ?? path) as NSString).deletingLastPathComponent))
                    copyPaths.append((face.id, path))
                }
            }
            let placed = CopyChooser.places(of: copies, folders: context.data.folders, locations: context.locations)
            var place: [String: String] = [:]
            for (copy, spot) in zip(copyPaths, placed) { place[copy.path] = spot.key }

            var paths: [String] = []
            var keep = Set<String>()
            var styles = 0
            for face in family.faces {
                let inactive = ([face.face.path] + face.otherCopies).filter { !context.library.activePaths.contains($0) && context.isInWatchedFolder($0) }
                let spares = Dictionary(grouping: inactive) { place[$0] ?? ($0 as NSString).deletingLastPathComponent }.values.filter { $0.count >= 2 }
                guard !spares.isEmpty else { continue }
                styles += 1
                for copies in spares {
                    for path in copies where !paths.contains(path) { paths.append(path) }
                    for path in copies { _ = context.version(of: path) }
                    let kept = copies.first { origins.contains($0) } ?? copies.max { a, b in
                        let (va, vb) = (context.versionNumber(of: a), context.versionNumber(of: b))
                        if va != vb { return va.lexicographicallyPrecedes(vb) }
                        return (Context.modified(a) ?? .distantPast) < (Context.modified(b) ?? .distantPast)
                    }!
                    keep.insert(kept)
                }
            }
            guard !paths.isEmpty else { continue }
            paths.sort()
            // A file goes only when every face in it keeps a copy without it and the extras before it: a
            // collection can also hold styles, or other families, that have no duplicate.
            var extras: [String] = []
            for path in paths where !keep.contains(path) && !ActivationEngine.isProtected(path) {
                if context.copies.areSpare(Set(extras + [path])) { extras.append(path) }
            }
            problems.append(Problem(
                id: "duplicate.\(family.id)", kind: .duplicates, title: family.name, family: family.id,
                summary: styles == 1 ? "In \(paths.count) files." : "\(styles) styles in \(paths.count) files.",
                files: paths.map { context.file($0) },
                fixes: extras.isEmpty ? [] : [.trash(extras)],
                fileFixes: Dictionary(uniqueKeysWithValues: paths.map { ($0, [ProblemFix.reveal([$0])]) }),
                folderFixes: folderFixes(paths, [:]) { _, _ in false }
            ))
        }
        return problems
    }

    // MARK: Missing

    private static func missing(_ context: inout Context) -> [Problem] {
        let fm = FileManager.default
        var problems: [Problem] = []
        // A file on a disk that isn't connected is under Fonts on External Disks instead.
        for path in context.data.records.inPlace.sorted() where !fm.fileExists(atPath: path) && context.unreachable(path) == nil {
            problems.append(Problem(
                id: "missing.inplace.\(path)", kind: .missing, title: (path as NSString).lastPathComponent,
                summary: "Used where it was.",
                files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Used where it was")],
                fixes: [.forgetInPlace(path)], fileFixes: [:]
            ))
        }
        for (path, origin) in context.data.records.installedCopies.sorted(by: { $0.key < $1.key }) where !fm.fileExists(atPath: path) {
            problems.append(Problem(
                id: "missing.copy.\(path)", kind: .missing, title: (path as NSString).lastPathComponent,
                summary: "Installed from “\((origin as NSString).lastPathComponent)”.",
                files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Was in your Fonts folder")],
                fixes: [.forgetInstalledCopy(path)], fileFixes: [:]
            ))
        }
        // A family out of reach for now, on a disk that isn't connected, say, comes back with it.
        for set in context.data.sets {
            for family in set.families where context.library.family(family) == nil && !context.library.offlineFamilies.contains(family) {
                problems.append(Problem(
                    id: "missing.set.\(set.id.uuidString).\(family)", kind: .missing, title: family,
                    summary: "In the set “\(set.name)”, but not in the library.",
                    files: [], fixes: [.removeFromSet(set.id, family: family)], fileFixes: [:]
                ))
            }
        }
        return problems
    }

    // MARK: Unreadable

    private static func unreadable(_ context: inout Context) -> [Problem] {
        context.library.unreadableFiles.filter { !["woff", "woff2"].contains(($0 as NSString).pathExtension.lowercased()) }.map { path in
            var fixes: [ProblemFix] = [.reveal([path])]
            if !ActivationEngine.isProtected(path) { fixes.append(.trash([path])) }
            return Problem(
                id: "unreadable.\(path)", kind: .unreadable, title: (path as NSString).lastPathComponent,
                summary: context.detail(of: path) + ".",
                files: [ProblemFile(path: path, version: nil, modified: Context.modified(path), detail: context.detail(of: path))],
                fixes: fixes, fileFixes: [:]
            )
        }
    }

    // MARK: External

    /// Fonts used in place from disks that can go away, and from ones that are gone for now.
    private static func external(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        for path in context.data.records.inPlace.sorted() {
            if !FileManager.default.fileExists(atPath: path), let place = context.unreachable(path) {
                problems.append(Problem(
                    id: "external.\(path)", kind: .external, title: (path as NSString).lastPathComponent,
                    summary: "Used where it is, \(place).",
                    files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Out of reach for now")],
                    // For a disk that's gone for good.
                    fixes: [.forgetInPlace(path)], fileFixes: [:]
                ))
                continue
            }
            guard let volume = externalVolumeName(of: path) else { continue }
            let family = context.library.families.first { $0.faces.contains { $0.face.path == path } }
            problems.append(Problem(
                id: "external.\(path)", kind: .external, title: family?.name ?? (path as NSString).lastPathComponent,
                summary: "Used where it is, on “\(volume)”.",
                files: [context.file(path)], fixes: [.installCopy(path), .reveal([path])], fileFixes: [:]
            ))
        }
        return problems
    }

    /// The volume's name when it's removable, external or on the network; nil for the Mac's own disk (or a missing file).
    private static func externalVolumeName(of path: String) -> String? {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeLocalizedNameKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { return nil }
        let external = values.volumeIsRemovable == true || values.volumeIsEjectable == true || values.volumeIsInternal == false || values.volumeIsLocal == false
        return external ? values.volumeLocalizedName ?? "an external disk" : nil
    }
}

/// Tells whether font files are spare copies: whether every face in them, of every family, has a copy in
/// another file that stays. Problems offers to remove a file only then. Which faces a file holds comes from
/// the library; the file itself is read too, for faces the library leaves out (hidden families), and the
/// other copies must still be there, and be other files rather than the same one by another path.
public struct SpareCopies: Sendable {
    private struct FaceKey: Hashable {
        var family: String
        var postScriptName: String
        var isItalic: Bool

        init(_ face: FontFace) {
            family = face.familyName
            postScriptName = face.postScriptName
            isItalic = face.isItalic
        }
    }

    private struct FileID: Hashable {
        var device: Int32
        var inode: UInt64
    }

    /// The faces the library knows in each file, and every file each face is in.
    private var faces: [String: Set<FaceKey>] = [:]
    private var files: [FaceKey: [String]] = [:]
    private let unreadable: Set<String>
    /// Read from disk once per file.
    private var faceCounts: [String: Int] = [:]
    private var fileIDs: [String: FileID?] = [:]

    public init(_ library: Library) {
        unreadable = Set(library.unreadableFiles)
        for family in library.families {
            for face in family.faces {
                let key = FaceKey(face.face)
                let paths = [face.face.path] + face.otherCopies
                files[key] = paths
                for path in paths { faces[path, default: []].insert(key) }
            }
        }
    }

    /// Whether all of `paths` can go without taking the last copy of any face with them. A file nothing could
    /// read, and still can't, holds nothing to lose; a file the library knows nothing else about holds
    /// something unknown, so it can't go.
    public mutating func areSpare(_ paths: Set<String>) -> Bool {
        var removed = Set<FileID>()
        for path in paths {
            if let id = fileID(of: path) { removed.insert(id) }
        }
        for path in paths {
            guard let known = faces[path], !known.isEmpty else {
                if unreadable.contains(path) && faceCount(of: path) == 0 { continue }
                return false
            }
            // More faces in the file than the library lists: one of them may be nowhere else.
            guard faceCount(of: path) <= known.count else { return false }
            for key in known where !hasCopy(of: key, outside: paths, removed: removed) { return false }
        }
        return true
    }

    private mutating func hasCopy(of key: FaceKey, outside paths: Set<String>, removed: Set<FileID>) -> Bool {
        for other in files[key] ?? [] where !paths.contains(other) {
            if let id = fileID(of: other), !removed.contains(id) { return true }
        }
        return false
    }

    /// Distinct faces in the file, hidden families' included.
    private mutating func faceCount(of path: String) -> Int {
        if let count = faceCounts[path] { return count }
        let count = Set(FontFileReader.faces(atPath: path).map(FaceKey.init)).count
        faceCounts[path] = count
        return count
    }

    /// The file a path leads to, through symbolic links; nil when there's none.
    private mutating func fileID(of path: String) -> FileID? {
        if let known = fileIDs[path] { return known }
        var info = stat()
        let id = stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG ? FileID(device: info.st_dev, inode: info.st_ino) : nil
        fileIDs[path] = id
        return id
    }
}
