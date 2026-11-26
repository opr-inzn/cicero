import CoreText
import Foundation

public enum ProblemKind: String, CaseIterable, Sendable {
    case installedTwice, missing, unreadable, external, duplicates, sharedNames

    public var isMinor: Bool { self == .sharedNames }

    public var groupsFilesByFolder: Bool { self != .sharedNames }

    public var title: String {
        switch self {
        case .installedTwice: "Installed Twice"
        case .sharedNames: "Shared Style Names"
        case .missing: "Missing Files"
        case .unreadable: "Damaged or Unreadable Files"
        case .external: "Unavailable Fonts"
        case .duplicates: "Duplicates"
        }
    }

    public var explanation: String {
        switch self {
        case .installedTwice:
            "The same font is active from more than one file. macOS uses only one of them, so apps may get an older version. Keep one and remove the other copies. Selected files go to the Trash."
        case .sharedNames:
            "Some fonts, often variable ones, give styles a short name like “Bold”. When two active fonts share a name, macOS assigns it to only one, so a document may open in the wrong font. Usually you don’t need to do anything. If a document uses the wrong font, deactivate the one you don’t need or get a newer version."
        case .missing:
            "Cicero remembers these files or families, but they can’t be found. They may have been moved or deleted."
        case .unreadable:
            "Cicero couldn’t read these files. They may be damaged or not valid font files. Select any you want to move to the Trash."
        case .external:
            "These fonts are installed from their own folder on a disk or location that isn’t available now, so they’re inactive. Connect the disk or make the location available again, or forget them if it’s gone for good."
        case .duplicates:
            "The same font file appears more than once in the same location. You can move selected files to the Trash, and Cicero always keeps at least one copy of each font."
        }
    }
}

public struct ProblemFile: Hashable, Sendable {
    public var path: String
    public var version: String?
    public var modified: Date?
    public var detail: String
    public var title: String?
    public var note: String?
    public var preferredFor: [String]
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

public enum ProblemFix: Hashable, Sendable {
    case reveal([String])
    case deactivate([FaceID])
    // Never protected paths, and only spare copies (every face in them, of every family, has a copy in another file), or files nothing can read.
    case trash([String])
    case forgetInPlace(String)
    case forgetInstalledCopy(String)
    case removeFromSet(UUID, family: String)
    case installCopy(String)
    case removeFromAdobeFonts([String])

    public var title: String {
        switch self {
        case .reveal: "Reveal"
        case .deactivate: "Deactivate"
        case .trash(let paths): paths.count == 1 ? "Move to Trash" : "Move Extra Copies to Trash"
        case .forgetInPlace, .forgetInstalledCopy: "Forget"
        case .removeFromSet: "Forget Family"
        case .installCopy: "Install a Copy"
        case .removeFromAdobeFonts: "Manage in Adobe Fonts"
        }
    }

    public var isForget: Bool {
        switch self {
        case .forgetInPlace, .forgetInstalledCopy, .removeFromSet: true
        default: false
        }
    }
}

public struct Problem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ProblemKind
    public var title: String
    public var family: String?
    public var summary: String
    public var files: [ProblemFile]
    public var fixes: [ProblemFix]
    public var fileFixes: [String: [ProblemFix]]
    public var folderFixes: [String: [ProblemFix]]
    public var newestFolder: String?
    public var extraCopies: [String]
    public var copyGroups: [[String]]
    public var trashable: Set<String>
    public var newest: Set<String>
    public var leavesAdobeFonts: Set<String>

    public init(id: String, kind: ProblemKind, title: String, family: String? = nil, summary: String, files: [ProblemFile], fixes: [ProblemFix],
                fileFixes: [String: [ProblemFix]], folderFixes: [String: [ProblemFix]] = [:], newestFolder: String? = nil,
                extraCopies: [String] = [], copyGroups: [[String]] = [], trashable: Set<String> = [], newest: Set<String> = [],
                leavesAdobeFonts: Set<String> = []) {
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
        self.extraCopies = extraCopies
        self.copyGroups = copyGroups
        self.trashable = trashable
        self.newest = newest
        self.leavesAdobeFonts = leavesAdobeFonts
    }

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

public struct ProblemFolder: Hashable, Sendable {
    public var path: String
    public var files: [ProblemFile]
}

public enum ProblemDetector {
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
        var copies: SpareCopies
        private var versions: [String: String?] = [:]

        init(library: Library, data: UserData, locations: Locations, fileForName: @escaping (String) -> String?) {
            self.library = library
            self.data = data
            self.locations = locations
            self.fileForName = fileForName
            folders = data.scannedFolders().map(data.named)
            copies = SpareCopies(library)
            var knownVersions: [String: String?] = [:]
            for family in library.families {
                for face in family.faces {
                    if knownVersions.index(forKey: face.face.path) == nil {
                        knownVersions.updateValue(face.face.version, forKey: face.face.path)
                    }
                    for copy in face.copies where knownVersions.index(forKey: copy.face.path) == nil {
                        knownVersions.updateValue(copy.face.version, forKey: copy.face.path)
                    }
                }
            }
            versions = knownVersions
        }

        mutating func file(_ path: String) -> ProblemFile {
            ProblemFile(path: path, version: version(of: path), modified: Self.modified(path), detail: detail(of: path))
        }

        mutating func version(of path: String) -> String? {
            if let index = versions.index(forKey: path) { return versions.values[index] }
            let version = FontFileReader.faces(atPath: path).first?.version
            versions.updateValue(version, forKey: path)
            return version
        }

        static func modified(_ path: String) -> Date? {
            try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        func detail(of path: String) -> String {
            if library.activePaths.contains(path) {
                switch LibraryScanner.activeSource(of: path, locations: locations, records: data.records) {
                case .macOS: return "Installed with macOS"
                case .allUsers: return "Installed for all users"
                case .app: return "Comes with an app"
                case .adobeFonts: return "Adobe Fonts"
                case .fontsFolder: return "Active"
                case .inPlace:
                    return data.fontLibrary.map { path.hasPrefix($0.path + "/") } == true ? "Active" : "Active from its own folder"
                case .temporary(.untilQuit): return "Active until Cicero quits"
                case .temporary(.whileAppsRun): return "Active while its app is open"
                case .otherApp: return "Activated by another app"
                }
            }
            if ActiveSource.isAdobeFonts(path) { return "Active in Adobe apps" }
            if let app = folders.first(where: { path.hasPrefix($0.path + "/") })?.appName { return "Active in \(FaceState.appDescription(app))" }
            return "Inactive"
        }

        func unreachable(_ path: String) -> String? {
            if let volume = Reachability.disconnectedVolume(of: path) { return "Disk “\(volume)” isn’t connected" }
            guard let folder = folders.first(where: { library.unavailableFolders[$0.id] != nil && path.hasPrefix($0.path + "/") }) else { return nil }
            return library.unavailableFolders[folder.id] == .noAccess
                ? "No access to “\(folder.displayName)”"
                : "“\(folder.displayName)” can’t be found"
        }

        func isInWatchedFolder(_ path: String) -> Bool {
            locations.isInInactiveFolder(path) || folders.contains { path.hasPrefix($0.path + "/") }
        }

        func versionNumber(of path: String) -> [Double] {
            guard let version = versions[path] ?? nil else { return [] }
            return FontVersion.number(version)
        }

        func keeper(of paths: [String]) -> String {
            func rank(_ path: String) -> Int {
                let source = LibraryScanner.activeSource(of: path, locations: locations, records: data.records)
                if source != .adobeFonts, ActivationEngine.isProtected(path) { return 5 }
                switch source {
                // Creative Cloud may take a copy from Adobe Fonts away, so one of the user's own stays too.
                case .adobeFonts: return 0
                case .macOS, .app: return 5
                case .inPlace, .otherApp: return 4
                case .allUsers: return 3
                case .fontsFolder: return 2
                case .temporary: return 1
                }
            }
            return paths.max { a, b in
                let (va, vb) = (versionNumber(of: a), versionNumber(of: b))
                if va != vb { return va.lexicographicallyPrecedes(vb) }
                let (ra, rb) = (rank(a), rank(b))
                if ra != rb { return ra < rb }
                return a > b
            }!
        }

        func newest(of paths: [String]) -> Set<String> {
            let numbers = paths.map(versionNumber)
            guard let top = numbers.max(by: { $0.lexicographicallyPrecedes($1) }), numbers.contains(where: { $0.lexicographicallyPrecedes(top) }) else { return [] }
            return Set(zip(paths, numbers).filter { $0.1 == top }.map(\.0))
        }

        func newestFolder(of paths: [String]) -> String? {
            let ranked = Dictionary(grouping: paths) { ($0 as NSString).deletingLastPathComponent }
                .mapValues { $0.map(versionNumber).max { $0.lexicographicallyPrecedes($1) } ?? [] }
                .sorted { $1.value.lexicographicallyPrecedes($0.value) }
            guard ranked.count > 1, ranked[1].value.lexicographicallyPrecedes(ranked[0].value) else { return nil }
            return ranked[0].key
        }
    }

    // MARK: Installed twice

    private static func installedTwice(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        var styles: [[[String]]] = []
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
            guard !paths.isEmpty, !paths.allSatisfy(ActivationEngine.isProtected) else { continue }
            paths.sort()
            var fileFixes: [String: [ProblemFix]] = [:]
            for path in paths {
                var fixes: [ProblemFix] = [.reveal([path])]
                if let id = deactivatable[path] {
                    fixes.append(.deactivate([id]))
                } else if ActiveSource.isAdobeFonts(path) {
                    // Creative Cloud's copy goes when the font is removed from Adobe Fonts, never by Cicero.
                    fixes.append(.removeFromAdobeFonts([path]))
                } else if !ActivationEngine.isProtected(path), context.copies.areSpare([path]) {
                    // Not when the file also holds styles, or other families, that are nowhere else.
                    fixes.append(.trash([path]))
                }
                fileFixes[path] = fixes
            }
            let files = paths.map { context.file($0) }
            // Turning a folder's files off at once must leave every style active from another copy, and removing them must leave every face in them a copy elsewhere.
            let folderFixes = folderFixes(paths, fileFixes) { folder, trashing in
                copies.allSatisfy { $0.contains { !folder.contains($0) } } && (!trashing || context.copies.areSpare(folder))
            }
            let trashable = paths.filter { !ActivationEngine.isProtected($0) && context.copies.areSpare([$0]) }
            // Only after the trash alert warns that Creative Cloud can take the Adobe Fonts copy left away at any time, losing the font.
            var withAdobeFonts = SpareCopies(context.library, countingAdobeFonts: true)
            let leavesAdobeFonts = paths.filter { path in
                !trashable.contains(path) && !ActivationEngine.isProtected(path) && !ActiveSource.isAdobeFonts(path) && withAdobeFonts.areSpare([path])
            }
            problems.append(Problem(
                id: "installedTwice.\(family.id)", kind: .installedTwice, title: family.name, family: family.id,
                summary: copies.count == 1 ? "Active from \(paths.count) files." : "\(copies.count) styles active from \(paths.count) files.",
                files: files, fixes: [], fileFixes: fileFixes, folderFixes: folderFixes,
                newestFolder: context.newestFolder(of: paths),
                copyGroups: copies.map { $0.sorted() }, trashable: Set(trashable + leavesAdobeFonts), newest: context.newest(of: paths),
                leavesAdobeFonts: Set(leavesAdobeFonts)
            ))
            styles.append(copies)
        }
        // The copy each style keeps, of every family: a collection one family keeps can be another's extra copy.
        let kept = Set(styles.joined().map { context.keeper(of: $0) })
        var removed = Set<String>()
        var removedIDs = Set<SpareCopies.FileID>()
        for index in problems.indices {
            for path in problems[index].files.map(\.path) where !kept.contains(path) && !ActivationEngine.isProtected(path) {
                guard context.copies.takeIfSpare(path, removed: &removed, removedIDs: &removedIDs) else { continue }
                problems[index].extraCopies.append(path)
            }
        }
        return problems
    }

    // MARK: Shared names

    private static func sharedNames(_ context: inout Context) -> [Problem] {
        struct Face {
            var path: String
            var copies: [String]
            var family: String
            var style: String
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
                    // From the style name: a variable font's named styles share one OS/2 weight.
                    rank: (face.face.isItalic ? 10_000 : 0) + (StyleName(face.face.styleName).weight ?? face.face.weight),
                    id: face.canDeactivate ? face.id : nil
                ))
            }
        }
        clashes = clashes.filter { _, faces in
            Set(faces.map(\.family)).count >= 2 && !faces.allSatisfy { ActivationEngine.isProtected($0.path) }
        }

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
                if let path = context.fileForName(name), let face = faces.first(where: { $0.path == path || $0.copies.contains(path) }) {
                    files[face.path]?.won.append(name)
                    if !files[face.path]!.wonStyles.contains(where: { $0.name == face.style }) { files[face.path]?.wonStyles.append((face.style, face.rank)) }
                }
            }
            func ordered(_ styles: [(name: String, rank: Int)]) -> String {
                abridged(styles.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name < $1.name }.map(\.name)).listed()
            }
            let problemFiles = files.map { path, file in
                let isPartly = !file.won.isEmpty && file.won.count < file.names.count
                return ProblemFile(path: path, version: nil, modified: nil, detail: context.detail(of: path),
                                   title: sorted(file.families).listed(), note: ordered(file.styles), preferredFor: file.won,
                                   preferredStyles: isPartly ? ordered(file.wonStyles) : nil)
            }.sorted { a, b in
                let order = a.title!.localizedStandardCompare(b.title!)
                return order == .orderedSame ? a.path < b.path : order == .orderedAscending
            }

            let families = sorted(Array(component))
            var summary = names.count == 1
                ? "These fonts share the PostScript name “\(names[0])”."
                : "These fonts share these PostScript names: \(abridged(names).listed())."
            let winners = problemFiles.filter { !$0.preferredFor.isEmpty }
            if winners.map(\.preferredFor.count).reduce(0, +) == names.count {
                summary += " macOS assigns \(names.count == 1 ? "it" : "them") to \(winners.map { $0.title! }.listed())."
            }
            return Problem(
                id: "sharedNames.\(families.joined(separator: "|"))", kind: .sharedNames,
                title: (families.count > 4 ? Array(families.prefix(3)) + ["\(families.count - 3) more"] : families).listed(),
                summary: summary, files: problemFiles, fixes: [],
                fileFixes: Dictionary(uniqueKeysWithValues: problemFiles.map { file in
                    (file.path, [ProblemFix.reveal([file.path])] + (files[file.path]!.id.map { [.deactivate([$0])] } ?? []))
                })
            )
        }
    }

    private static func abridged(_ items: [String]) -> [String] {
        items.count > 7 ? Array(items.prefix(6)) + ["\(items.count - 6) more"] : items
    }

    private static func sorted(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func folderFixes(_ paths: [String], _ fileFixes: [String: [ProblemFix]],
                                    canCombine: (_ files: Set<String>, _ trashing: Bool) -> Bool) -> [String: [ProblemFix]] {
        var result: [String: [ProblemFix]] = [:]
        for (folder, files) in Dictionary(grouping: paths, by: { ($0 as NSString).deletingLastPathComponent }) where files.count > 1 {
            var fixes: [ProblemFix] = [.reveal(files)]
            var trash: [String] = []
            var deactivate: [FaceID] = []
            var adobeFonts: [String] = []
            for fix in files.flatMap({ fileFixes[$0] ?? [] }) {
                switch fix {
                case .trash(let paths): trash += paths
                case .deactivate(let ids): deactivate += ids
                case .removeFromAdobeFonts(let paths): adobeFonts += paths
                default: break
                }
            }
            if adobeFonts.count == files.count {
                fixes.append(.removeFromAdobeFonts(adobeFonts))
            } else if trash.count == files.count {
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


    // MARK: Duplicates

    private static func duplicates(_ context: inout Context) -> [Problem] {
        var problems: [Problem] = []
        let records = context.data.records
        let origins = Set(records.installedCopies.values)
        let fontLibrary = context.data.fontLibrary.map { $0.path + "/" }
        for family in context.library.families {
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
            var groups: [[String]] = []
            var keep = Set<String>()
            var styles = 0
            for face in family.faces {
                // Never the Font Library's files: the library keeps its fonts while they're off, copies of fonts in the user's folders among them.
                let inactive = ([face.face.path] + face.otherCopies).filter { path in
                    !context.library.activePaths.contains(path) && context.isInWatchedFolder(path) && !(fontLibrary.map(path.hasPrefix) ?? false)
                }
                // Copies in different places, like each client's folder, are for Use Copy From to choose between, not spares.
                let spares = Dictionary(grouping: inactive) { place[$0] ?? ($0 as NSString).deletingLastPathComponent }.values
                    .flatMap(identicalGroups).filter { $0.count >= 2 }
                guard !spares.isEmpty else { continue }
                styles += 1
                for copies in spares {
                    for path in copies where !paths.contains(path) { paths.append(path) }
                    if !groups.contains(copies) { groups.append(copies) }
                    for path in copies { _ = context.version(of: path) }
                    let kept = copies.first { origins.contains($0) } ?? copies.max { a, b in
                        let (va, vb) = (context.versionNumber(of: a), context.versionNumber(of: b))
                        if va != vb { return va.lexicographicallyPrecedes(vb) }
                        let (ca, cb) = (looksLikeACopy(a), looksLikeACopy(b))
                        if ca != cb { return ca }
                        return (Context.modified(a) ?? .distantPast) < (Context.modified(b) ?? .distantPast)
                    }!
                    keep.insert(kept)
                }
            }
            guard !paths.isEmpty else { continue }
            paths.sort()
            // A file goes only when every face in it keeps a copy without it and the extras before it: a collection can also hold styles, or other families, that have no duplicate.
            var extras: [String] = []
            var removed = Set<String>()
            var removedIDs = Set<SpareCopies.FileID>()
            for path in paths where !keep.contains(path) && !ActivationEngine.isProtected(path) {
                if context.copies.takeIfSpare(path, removed: &removed, removedIDs: &removedIDs) { extras.append(path) }
            }
            let trashable = paths.filter { path in
                var removed = Set<String>(), removedIDs = Set<SpareCopies.FileID>()
                return !ActivationEngine.isProtected(path) && context.copies.takeIfSpare(path, removed: &removed, removedIDs: &removedIDs)
            }
            problems.append(Problem(
                id: "duplicate.\(family.id)", kind: .duplicates, title: family.name, family: family.id,
                summary: styles == 1 ? "Inactive, in \(paths.count) files." : "\(styles) inactive styles in \(paths.count) files.",
                files: paths.map { context.file($0) },
                fixes: extras.isEmpty ? [] : [.trash(extras)],
                fileFixes: Dictionary(uniqueKeysWithValues: paths.map { ($0, [ProblemFix.reveal([$0])]) }),
                folderFixes: folderFixes(paths, [:]) { _, _ in false },
                extraCopies: extras,
                copyGroups: groups.map { $0.sorted() },
                trashable: Set(trashable)
            ))
        }
        return problems
    }

    private static func looksLikeACopy(_ path: String) -> Bool {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.range(of: #"([ _]\d+|[ _-]copy( \d+)?| \(\d+\))$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func identicalGroups(_ paths: [String]) -> [[String]] {
        var groups: [[String]] = []
        for path in paths {
            if let index = groups.firstIndex(where: { ActivationEngine.isIdenticalCopy($0[0], of: path) }) {
                groups[index].append(path)
            } else {
                groups.append([path])
            }
        }
        return groups
    }

    // MARK: Missing

    private static func missing(_ context: inout Context) -> [Problem] {
        let fm = FileManager.default
        var problems: [Problem] = []
        for path in context.data.records.inPlace.sorted() where !fm.fileExists(atPath: path) && context.unreachable(path) == nil {
            problems.append(Problem(
                id: "missing.inplace.\(path)", kind: .missing, title: (path as NSString).lastPathComponent,
                summary: "Installed from its own folder, now missing.",
                files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Installed from its own folder, now missing")],
                fixes: [.forgetInPlace(path)], fileFixes: [:]
            ))
        }
        for path in context.data.records.installedCopies.keys.sorted() where !fm.fileExists(atPath: path) {
            let inLibrary = context.data.fontLibrary.map { path.hasPrefix($0.path + "/") } ?? false
            let place = inLibrary ? "Cicero’s Library" : (context.locations.userFonts.path as NSString).abbreviatingWithTildeInPath
            problems.append(Problem(
                id: "missing.copy.\(path)", kind: .missing, title: (path as NSString).lastPathComponent,
                summary: "Copy missing from \(place).",
                files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Copy missing from \(place)")],
                fixes: [.forgetInstalledCopy(path)], fileFixes: [:]
            ))
        }
        for set in context.data.sets {
            for family in set.memberFamilies where context.library.family(family) == nil && !context.library.offlineFamilies.contains(family) {
                problems.append(Problem(
                    id: "missing.set.\(set.id.uuidString).\(family)", kind: .missing, title: family,
                    summary: "Listed in “\(set.name)”, but its fonts are missing.",
                    files: [], fixes: [.removeFromSet(set.id, family: family)], fileFixes: [:]
                ))
            }
        }
        return problems
    }

    // MARK: Unreadable

    private static func unreadable(_ context: inout Context) -> [Problem] {
        context.library.unreadableFiles.map { path in
            var fixes: [ProblemFix] = [.reveal([path])]
            if !ActivationEngine.isProtected(path) { fixes.append(.trash([path])) }
            return Problem(
                id: "unreadable.\(path)", kind: .unreadable, title: (path as NSString).lastPathComponent,
                summary: context.detail(of: path) + ".",
                files: [ProblemFile(path: path, version: nil, modified: Context.modified(path), detail: context.detail(of: path))],
                fixes: fixes, fileFixes: [:],
                trashable: ActivationEngine.isProtected(path) ? [] : [path]
            )
        }
    }

    // MARK: External

    private static func external(_ context: inout Context) -> [Problem] {
        let fontLibrary = context.data.fontLibrary.map { $0.path + "/" }
        return context.data.records.inPlace.sorted().compactMap { path in
            guard !(fontLibrary.map(path.hasPrefix) ?? false), !FileManager.default.fileExists(atPath: path), let place = context.unreachable(path) else { return nil }
            return Problem(
                id: "external.\(path)", kind: .external, title: (path as NSString).lastPathComponent,
                summary: "\(place).",
                files: [ProblemFile(path: path, version: nil, modified: nil, detail: "Currently unavailable")],
                fixes: [.forgetInPlace(path)], fileFixes: [:]
            )
        }
    }
}

struct SpareCopies: Sendable {
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

    struct FileID: Hashable {
        var device: Int32
        var inode: UInt64
    }

    private var faces: [String: Set<FaceKey>] = [:]
    private var files: [FaceKey: [String]] = [:]
    private let unreadable: Set<String>
    private var faceCounts: [String: Int] = [:]
    private var fileIDs: [String: FileID?] = [:]

    init(_ library: Library, countingAdobeFonts: Bool = false) {
        unreadable = Set(library.unreadableFiles)
        for family in library.families {
            for face in family.faces {
                let key = FaceKey(face.face)
                // A copy from Adobe Fonts is Creative Cloud's to take away whenever it likes, and one only Adobe apps load no other app has: it leaves no file of the user's spare.
                let paths = ([face.face.path] + face.otherCopies).filter { countingAdobeFonts || !ActiveSource.isAdobeFonts($0) }
                files[key] = paths
                for path in paths { faces[path, default: []].insert(key) }
            }
        }
    }

    mutating func areSpare(_ paths: Set<String>) -> Bool {
        var removed = Set<FileID>()
        for path in paths {
            if let id = fileID(of: path) { removed.insert(id) }
        }
        for path in paths {
            guard let known = faces[path], !known.isEmpty else {
                // A file nothing could read, and still can't, holds nothing to lose. One the library knows nothing else about holds something unknown.
                if unreadable.contains(path) && faceCount(of: path) == 0 { continue }
                return false
            }
            // More faces in the file than the library lists: one of them may be nowhere else.
            guard faceCount(of: path) <= known.count else { return false }
            for key in known where !hasCopy(of: key, outside: paths, removed: removed) { return false }
        }
        return true
    }

    mutating func takeIfSpare(_ path: String, removed: inout Set<String>, removedIDs: inout Set<FileID>) -> Bool {
        guard !removed.contains(path) else { return false }
        let known = faces[path]
        if let known, !known.isEmpty {
            guard faceCount(of: path) <= known.count else { return false }
        } else {
            guard unreadable.contains(path) && faceCount(of: path) == 0 else { return false }
            removed.insert(path)
            if let id = fileID(of: path) { removedIDs.insert(id) }
            return true
        }
        let id = fileID(of: path)
        var nextRemoved = removed
        nextRemoved.insert(path)
        var nextIDs = removedIDs
        let isNewID = id.map { nextIDs.insert($0).inserted } ?? false
        for key in known! where !hasCopy(of: key, outside: nextRemoved, removed: nextIDs) { return false }
        if isNewID, let id {
            for other in removed {
                guard let otherKeys = faces[other] else { continue }
                for key in otherKeys where (files[key] ?? []).contains(where: { fileID(of: $0) == id }) {
                    guard hasCopy(of: key, outside: nextRemoved, removed: nextIDs) else { return false }
                }
            }
        }
        removed = nextRemoved
        removedIDs = nextIDs
        return true
    }

    private mutating func hasCopy(of key: FaceKey, outside paths: Set<String>, removed: Set<FileID>) -> Bool {
        for other in files[key] ?? [] where !paths.contains(other) {
            // The other copy must still be there, and be another file rather than the same one by another path.
            if let id = fileID(of: other), !removed.contains(id) { return true }
        }
        return false
    }

    private mutating func faceCount(of path: String) -> Int {
        if let count = faceCounts[path] { return count }
        let count = Set(FontFileReader.faces(atPath: path).map(FaceKey.init)).count
        faceCounts[path] = count
        return count
    }

    private mutating func fileID(of path: String) -> FileID? {
        if let index = fileIDs.index(forKey: path) { return fileIDs.values[index] }
        var info = stat()
        let id = stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG ? FileID(device: info.st_dev, inode: info.st_ino) : nil
        fileIDs.updateValue(id, forKey: path)
        return id
    }
}
