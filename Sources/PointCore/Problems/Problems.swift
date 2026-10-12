import Foundation

public enum ProblemKind: String, CaseIterable, Sendable {
    case installedTwice, missing, unreadable, external, duplicates, sharedNames

    /// Worth knowing, rarely worth acting on: not counted in the sidebar badge and shown collapsed.
    public var isMinor: Bool { self == .sharedNames }

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
            "Each of these fonts has its own main PostScript name, but some of its named styles use a bare name like “Bold” that another font uses too. A document that refers to one of those styles by name may open with the other font. Usually there’s nothing to do; if it happens, turn one of the fonts off or get updated versions."
        case .missing:
            "Point remembers these files, but they’re gone. Fonts used where they were stop working when their files move or their disk is unplugged."
        case .unreadable:
            "Point couldn’t read these files. They may be damaged, or not font files at all."
        case .external:
            "These fonts are used from a disk that can be unplugged. They turn off when it’s gone."
        case .duplicates:
            "The same font is in your folders more than once."
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

    public init(path: String, version: String?, modified: Date?, detail: String) {
        self.path = path
        self.version = version
        self.modified = modified
        self.detail = detail
    }
}

/// Something the user can do about a problem. The app carries these out.
public enum ProblemFix: Hashable, Sendable {
    case reveal(String)
    /// Deactivate this active copy (installed copies go to the Trash or the Deactivated folder).
    case deactivate(FaceID)
    /// Move these files to the Trash (never protected paths, never the only copy).
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
        case .trash(let paths): paths.count == 1 ? "Move to Trash…" : "Move Extra Copies to Trash…"
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
    /// e.g. "Active from 2 files."
    public var summary: String
    public var files: [ProblemFile]
    /// Fixes for the problem as a whole.
    public var fixes: [ProblemFix]
    /// Fixes for single files, by path.
    public var fileFixes: [String: [ProblemFix]]

    public init(id: String, kind: ProblemKind, title: String, summary: String, files: [ProblemFile], fixes: [ProblemFix], fileFixes: [String: [ProblemFix]]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.files = files
        self.fixes = fixes
        self.fileFixes = fileFixes
    }
}

public enum ProblemDetector {
    /// Finds problems in the library. Reads font versions from disk for the files involved, so call it off the main thread.
    public static func detect(in library: Library, data: UserData, locations: Locations) -> [Problem] {
        var context = Context(library: library, data: data, locations: locations)
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

    private struct Context {
        let library: Library
        let data: UserData
        let locations: Locations
        private var versions: [String: String?] = [:]

        init(library: Library, data: UserData, locations: Locations) {
            self.library = library
            self.data = data
            self.locations = locations
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
                case .temporary(.untilQuit): return "Active until Point quits"
                case .temporary(.untilLogout): return "Active until you log out"
                case .otherApp: return "Activated by another app"
                }
            }
            if path.hasPrefix(locations.deactivated.path + "/") { return "In Point’s Deactivated folder" }
            if let folder = data.folders.first(where: { path.hasPrefix($0.path + "/") }) {
                return folder.appName.map { "Active in \(FaceState.appDescription($0))" } ?? "In \(folder.displayName)"
            }
            return "Not activated"
        }

        func isInWatchedFolder(_ path: String) -> Bool {
            path.hasPrefix(locations.deactivated.path + "/") || data.folders.contains { path.hasPrefix($0.path + "/") }
        }

        /// "Version 2.001" → 2.001, for picking the newest copy.
        func versionNumber(of path: String) -> Double {
            guard let version = versions[path] ?? nil else { return 0 }
            let digits = version.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
            return Double(digits.trimmingCharacters(in: CharacterSet(charactersIn: "."))) ?? 0
        }
    }

    // MARK: Installed twice

    /// The same font active from more than one file, grouped by family.
    private static func installedTwice(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        for family in context.library.families {
            var paths: [String] = []
            var styles = 0
            var deactivatable: [String: FaceID] = [:]
            for face in family.faces {
                let active = ([face.face.path] + face.otherCopies).filter { context.library.activePaths.contains($0) }
                guard active.count >= 2 else { continue }
                styles += 1
                for path in active where !paths.contains(path) { paths.append(path) }
                if face.canDeactivate, deactivatable[face.face.path] == nil { deactivatable[face.face.path] = face.id }
            }
            // Copies that all come with macOS are macOS's business: there's nothing to do about them.
            guard !paths.isEmpty, !paths.allSatisfy(ActivationEngine.isProtected) else { continue }
            paths.sort()
            var fileFixes: [String: [ProblemFix]] = [:]
            for path in paths {
                var fixes: [ProblemFix] = [.reveal(path)]
                if let id = deactivatable[path] {
                    fixes.append(.deactivate(id))
                } else if !ActivationEngine.isProtected(path) {
                    fixes.append(.trash([path]))
                }
                fileFixes[path] = fixes
            }
            problems.append(Problem(
                id: "installedTwice.\(family.id)", kind: .installedTwice, title: family.name,
                summary: styles == 1 ? "Active from \(paths.count) files." : "\(styles) styles active from \(paths.count) files.",
                files: paths.map { context.file($0) }, fixes: [], fileFixes: fileFixes
            ))
        }
        return problems
    }

    // MARK: Shared names

    /// Different families whose active faces use the same PostScript names (typically bare names like
    /// "Bold" given to variable fonts' named instances), grouped by the families involved.
    private static func sharedNames(_ context: inout Context) -> [Problem] {
        struct Clash {
            var weight = Int.max
            var files: [String: FaceID?] = [:]
            var families: [String] = []
        }
        var clashes: [String: Clash] = [:]
        for family in context.library.families {
            for face in family.faces where face.state.isActive {
                var clash = clashes[face.face.postScriptName] ?? Clash()
                clash.weight = min(clash.weight, face.face.weight)
                clash.files[face.face.path] = face.canDeactivate ? Self.first(face.id, clash.files[face.face.path] ?? nil) : clash.files[face.face.path] ?? nil
                if !clash.families.contains(family.id) { clash.families.append(family.id) }
                clashes[face.face.postScriptName] = clash
            }
        }
        var groups: [[String]: (names: [(String, Int)], files: [String: FaceID?])] = [:]
        for (name, clash) in clashes where clash.families.count >= 2 && !clash.files.keys.allSatisfy(ActivationEngine.isProtected) {
            var group = groups[clash.families] ?? ([], [:])
            group.names.append((name, clash.weight))
            group.files.merge(clash.files) { known, new in Self.first(known, new) }
            groups[clash.families] = group
        }
        return groups.map { families, group in
            let names = group.names.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.0)
            let shown = names.count > 7 ? Array(names.prefix(6)) + ["\(names.count - 6) more"] : names
            let paths = group.files.keys.sorted()
            let summary = names.count == 1
                ? "Named style \(names[0]) uses the same PostScript name in \(families.count == 2 ? "both" : "all of them")."
                : "Named styles \(joined(shown)) use the same PostScript names in \(families.count == 2 ? "both" : "all of them")."
            return Problem(
                id: "sharedNames.\(families.joined(separator: "|"))", kind: .sharedNames,
                title: joined(families), summary: summary,
                files: paths.map { context.file($0) }, fixes: [],
                fileFixes: Dictionary(uniqueKeysWithValues: paths.map { path in
                    (path, [ProblemFix.reveal(path)] + ((group.files[path] ?? nil).map { [.deactivate($0)] } ?? []))
                })
            )
        }
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

    /// The same font more than once among the inactive files in the user's folders.
    private static func duplicates(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        let origins = Set(context.data.records.installedCopies.values)
        for family in context.library.families {
            var paths: [String] = []
            var keep = Set<String>()
            var styles = 0
            for face in family.faces {
                let copies = ([face.face.path] + face.otherCopies).filter { !context.library.activePaths.contains($0) && context.isInWatchedFolder($0) }
                guard copies.count >= 2 else { continue }
                styles += 1
                for path in copies where !paths.contains(path) { paths.append(path) }
                for path in copies { _ = context.version(of: path) }
                let kept = copies.first { origins.contains($0) } ?? copies.max { a, b in
                    let (va, vb) = (context.versionNumber(of: a), context.versionNumber(of: b))
                    if va != vb { return va < vb }
                    return (Context.modified(a) ?? .distantPast) < (Context.modified(b) ?? .distantPast)
                }!
                keep.insert(kept)
            }
            guard !paths.isEmpty else { continue }
            paths.sort()
            let extras = paths.filter { !keep.contains($0) && !ActivationEngine.isProtected($0) }
            problems.append(Problem(
                id: "duplicate.\(family.id)", kind: .duplicates, title: family.name,
                summary: styles == 1 ? "In \(paths.count) files." : "\(styles) styles in \(paths.count) files.",
                files: paths.map { context.file($0) },
                fixes: extras.isEmpty ? [] : [.trash(extras)],
                fileFixes: Dictionary(uniqueKeysWithValues: paths.map { ($0, [ProblemFix.reveal($0)]) })
            ))
        }
        return problems
    }

    // MARK: Missing

    private static func missing(_ context: inout Context) -> [Problem] {
        let fm = FileManager.default
        var problems: [Problem] = []
        for path in context.data.records.inPlace.sorted() where !fm.fileExists(atPath: path) {
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
        for set in context.data.sets {
            for family in set.families where context.library.family(family) == nil {
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
            var fixes: [ProblemFix] = [.reveal(path)]
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

    /// Fonts used in place from disks that can go away.
    private static func external(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        for path in context.data.records.inPlace.sorted() {
            guard let volume = externalVolumeName(of: path) else { continue }
            let family = context.library.families.first { $0.faces.contains { $0.face.path == path } }
            problems.append(Problem(
                id: "external.\(path)", kind: .external, title: family?.name ?? (path as NSString).lastPathComponent,
                summary: "Used where it is, on “\(volume)”.",
                files: [context.file(path)], fixes: [.installCopy(path), .reveal(path)], fileFixes: [:]
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
