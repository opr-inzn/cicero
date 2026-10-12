import CoreText
import Foundation

/// Kinds of trouble Point can spot in a library, in the order the Problems view lists them.
enum ProblemKind: String, CaseIterable, Sendable {
    case conflict, missing, unreadable, external, duplicate

    var title: String {
        switch self {
        case .conflict: "Conflicts"
        case .missing: "Missing Files"
        case .unreadable: "Damaged or Unreadable Files"
        case .external: "Fonts on External Disks"
        case .duplicate: "Duplicates"
        }
    }

    var icon: String {
        switch self {
        case .conflict: "exclamationmark.2"
        case .missing: "questionmark.folder"
        case .unreadable: "doc.badge.ellipsis"
        case .external: "externaldrive.badge.exclamationmark"
        case .duplicate: "doc.on.doc"
        }
    }

    var explanation: String {
        switch self {
        case .conflict:
            "Fonts with the same PostScript name are active from more than one file. macOS uses only one of them, so apps may get an old version or a different font. Keep one and turn off the rest."
        case .missing:
            "Point remembers these fonts, but their files are gone. The drive may be unplugged, or the files were moved or deleted."
        case .unreadable:
            "Point couldn't read these files. They may be damaged, or not font files at all."
        case .external:
            "These fonts are used where they are, from a disk that can be unplugged. They turn off when it is. Installing a copy keeps them working."
        case .duplicate:
            "The same font is stored more than once in your folders. Only one copy is needed."
        }
    }
}

/// One file involved in a problem.
struct ProblemFile: Hashable, Sendable, Identifiable {
    var path: String
    var version: String?
    var modified: Date?
    /// Where the file is active from; nil when it isn't active.
    var activeKind: ActiveKind?
    var note: String
    var exists = true

    var id: String { path }
    var isUserControllable: Bool { activeKind?.isUserControllable ?? false }
    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

struct FontProblem: Identifiable, Hashable, Sendable {
    enum Detail: Hashable, Sendable {
        /// Active from several files; `template` is a face with the same name, used to build a face for any of the files.
        case conflict(template: FontFace)
        /// Stored several times while inactive; every file but `keep` is an extra copy.
        case duplicate(keep: String)
        case missingRegistered(path: String)
        case missingInstalledCopy(path: String, origin: String)
        case missingSetMember(setID: UUID, familyName: String)
        case unreadable(path: String)
        case external(face: LibraryFace)
    }

    var id: String
    var kind: ProblemKind
    var title: String
    var summary: String
    var files: [ProblemFile]
    var detail: Detail
}

/// Works out the problems for a snapshot of the library; runs off the main thread.
enum ProblemFinder {
    struct Input: Sendable {
        var families: [FontFamily]
        var activeKinds: [String: ActiveKind]
        var unreadableFiles: [String]
        var data: UserLibraryData
        /// Watched folders plus Point's Deactivated folder: the places duplicates may be trashed from.
        var libraryFolders: [String]
        var deactivatedFolder: String
    }

    /// Places Point must never move files out of.
    static func isProtected(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/Library/") || path.hasPrefix("/usr/") || path.hasPrefix("/private/")
            || path.contains(".app/") || path.contains("/Adobe/")
    }

    static func isInLibraryFolder(_ path: String, folders: [String]) -> Bool {
        !isProtected(path) && folders.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    static func find(_ input: Input) -> [FontProblem] {
        var problems: [FontProblem] = []
        problems += copyProblems(input)
        problems += missingProblems(input)
        problems += unreadableProblems(input)
        problems += externalProblems(input)
        return problems.sorted {
            ($0.kind.rawValue, $0.title) < ($1.kind.rawValue, $1.title)
        }
    }

    // MARK: Conflicts and duplicates

    private struct Copies {
        var template: FontFace
        var families: Set<String> = []
        var paths: [String] = []
    }

    private static func copyProblems(_ input: Input) -> [FontProblem] {
        // The same PostScript name can appear in several families when a font was renamed between versions.
        var byName: [String: Copies] = [:]
        for family in input.families {
            for face in family.faces {
                var copies = byName[face.face.postScriptName] ?? Copies(template: face.face)
                copies.families.insert(family.name)
                for path in [face.face.path] + face.otherPaths where !copies.paths.contains(path) {
                    copies.paths.append(path)
                }
                byName[face.face.postScriptName] = copies
            }
        }

        struct Group {
            var template: FontFace
            var families: Set<String> = []
            var names: [String] = []
        }
        var conflicts: [[String]: Group] = [:]
        var duplicates: [[String]: Group] = [:]
        for (name, copies) in byName {
            let active = copies.paths.filter { input.activeKinds[$0] != nil }.sorted()
            if active.count >= 2 {
                var group = conflicts[active] ?? Group(template: copies.template)
                group.families.formUnion(copies.families)
                group.names.append(name)
                conflicts[active] = group
            }
            let spare = copies.paths.filter { input.activeKinds[$0] == nil && isInLibraryFolder($0, folders: input.libraryFolders) }.sorted()
            if spare.count >= 2 {
                var group = duplicates[spare] ?? Group(template: copies.template)
                group.families.formUnion(copies.families)
                group.names.append(name)
                duplicates[spare] = group
            }
        }

        var result: [FontProblem] = []
        for (paths, group) in conflicts {
            let files = paths.map { file(at: $0, template: group.template, input: input) }
            result.append(FontProblem(
                id: "conflict:" + paths.joined(separator: "|"),
                kind: .conflict,
                title: title(families: group.families, styleCount: group.names.count),
                summary: "Active from \(paths.count) files.",
                files: files,
                detail: .conflict(template: group.template)
            ))
        }
        let origins = Set(input.data.installedCopies.values)
        for (paths, group) in duplicates {
            let files = paths.map { file(at: $0, template: group.template, input: input) }
            let keep = files.first { origins.contains($0.path) } ?? files.max { ($0.version ?? "", $0.modified ?? .distantPast) < ($1.version ?? "", $1.modified ?? .distantPast) } ?? files[0]
            result.append(FontProblem(
                id: "duplicate:" + paths.joined(separator: "|"),
                kind: .duplicate,
                title: title(families: group.families, styleCount: group.names.count),
                summary: "\(paths.count) copies; \(paths.count - 1 == 1 ? "1 is" : "\(paths.count - 1) are") extra.",
                files: files,
                detail: .duplicate(keep: keep.path)
            ))
        }
        return result
    }

    private static func title(families: Set<String>, styleCount: Int) -> String {
        let names = families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", ")
        return styleCount == 1 ? names : "\(names) · \(styleCount) styles"
    }

    private static func file(at path: String, template: FontFace, input: Input) -> ProblemFile {
        var face = template
        face.path = path
        face.index = 0
        let font = FontCache.shared.font(face, size: 12)
        var version = (CTFontCopyName(font, kCTFontVersionNameKey) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if version.lowercased().hasPrefix("version ") { version.removeFirst("version ".count) }
        let modified = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let kind = input.activeKinds[path]
        return ProblemFile(path: path, version: version.isEmpty ? nil : version, modified: modified, activeKind: kind, note: note(for: kind, path: path, input: input))
    }

    private static func note(for kind: ActiveKind?, path: String, input: Input) -> String {
        switch kind {
        case .system: "Installed with macOS"
        case .allUsers: "Installed for all users"
        case .application: "Inside an app"
        case .adobeCloud: "Adobe Fonts"
        case .user: "In your Fonts folder"
        case .registered: "Used where it is"
        case .temporary(let scope): scope.statusLabel
        case .other: "Activated by another app"
        case nil: path.hasPrefix(input.deactivatedFolder + "/") ? "In Point's Deactivated folder" : "Not active"
        }
    }

    // MARK: Missing files

    private static func missingProblems(_ input: Input) -> [FontProblem] {
        let fm = FileManager.default
        var result: [FontProblem] = []
        for path in input.data.registeredPaths.sorted() where !fm.fileExists(atPath: path) {
            result.append(FontProblem(
                id: "missing-registered:\(path)", kind: .missing,
                title: URL(fileURLWithPath: path).lastPathComponent,
                summary: "Was used where it is, but the file is gone.",
                files: [ProblemFile(path: path, note: "Missing", exists: false)],
                detail: .missingRegistered(path: path)
            ))
        }
        for (path, origin) in input.data.installedCopies.sorted(by: { $0.key < $1.key }) where !fm.fileExists(atPath: path) {
            result.append(FontProblem(
                id: "missing-copy:\(path)", kind: .missing,
                title: URL(fileURLWithPath: path).lastPathComponent,
                summary: "Point installed this copy, but it has been removed from your Fonts folder.",
                files: [
                    ProblemFile(path: path, note: "Missing", exists: false),
                    ProblemFile(path: origin, note: fm.fileExists(atPath: origin) ? "Original" : "Original, also missing", exists: fm.fileExists(atPath: origin)),
                ],
                detail: .missingInstalledCopy(path: path, origin: origin)
            ))
        }
        let known = Set(input.families.map(\.name))
        for set in input.data.sets {
            for name in set.familyNames where !known.contains(name) {
                result.append(FontProblem(
                    id: "missing-member:\(set.id):\(name)", kind: .missing,
                    title: name,
                    summary: "Listed in the set “\(set.name)”, but no longer in your library.",
                    files: [],
                    detail: .missingSetMember(setID: set.id, familyName: name)
                ))
            }
        }
        return result
    }

    // MARK: Unreadable files

    private static func unreadableProblems(_ input: Input) -> [FontProblem] {
        input.unreadableFiles.sorted().map { path in
            let modified = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return FontProblem(
                id: "unreadable:\(path)", kind: .unreadable,
                title: URL(fileURLWithPath: path).lastPathComponent,
                summary: "macOS can't read this file as a font.",
                files: [ProblemFile(path: path, modified: modified, note: "Unreadable")],
                detail: .unreadable(path: path)
            )
        }
    }

    // MARK: External volumes

    private static func externalProblems(_ input: Input) -> [FontProblem] {
        var volumes: [String: (external: Bool, name: String)] = [:]
        func volume(of path: String) -> (external: Bool, name: String)? {
            let parts = path.split(separator: "/", maxSplits: 3)
            guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
            let root = "/Volumes/\(parts[1])"
            if let cached = volumes[root] { return cached }
            let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey, .volumeNameKey]
            let values = try? URL(fileURLWithPath: root).resourceValues(forKeys: keys)
            let external = values?.volumeIsInternal == false || values?.volumeIsRemovable == true
                || values?.volumeIsEjectable == true || values?.volumeIsLocal == false
            let info = (external, values?.volumeName ?? String(parts[1]))
            volumes[root] = info
            return info
        }

        var result: [FontProblem] = []
        var seen = Set<String>()
        for family in input.families {
            for face in family.faces {
                guard let kind = face.status.activeKind, kind == .registered || kind == .other || kind.isTemporary,
                      seen.insert(face.face.path).inserted,
                      let volume = volume(of: face.face.path), volume.external else { continue }
                let styles = family.faces.filter { $0.face.path == face.face.path }
                result.append(FontProblem(
                    id: "external:\(face.face.path)", kind: .external,
                    title: styles.count == 1 ? "\(family.name) \(face.face.styleName)" : "\(family.name) · \(styles.count) styles",
                    summary: "Active from the disk “\(volume.name)”.",
                    files: [ProblemFile(path: face.face.path, activeKind: kind, note: note(for: kind, path: face.face.path, input: input))],
                    detail: .external(face: face)
                ))
            }
        }
        return result
    }
}

// MARK: - Store

extension LibraryStore {
    @MainActor private static var problemsTask: Task<Void, Never>?

    /// Recomputes `problems` from the current scan and user data, off the main thread.
    func refreshProblems() {
        guard hasScanned || !families.isEmpty else { return }
        let userFonts = NSHomeDirectory() + "/Library/Fonts/"
        let input = ProblemFinder.Input(
            families: families,
            activeKinds: Dictionary(uniqueKeysWithValues: activePaths.map { ($0, activeKind(of: $0, userFonts: userFonts)) }),
            unreadableFiles: unreadableFiles.filter { !["woff", "woff2"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) },
            data: data,
            libraryFolders: data.watchedFolders.map(\.path) + [Persistence.deactivatedDirectory.path],
            deactivatedFolder: Persistence.deactivatedDirectory.path
        )
        Self.problemsTask?.cancel()
        Self.problemsTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { ProblemFinder.find(input) }.value
            guard !Task.isCancelled else { return }
            self?.problems = found
        }
    }

    var problemsLabel: String {
        problems.count == 1 ? "1 problem" : "\(problems.count) problems"
    }

    /// Whether Point may move this file to the Trash: it has to be in one of the user's own folders.
    func mayTrash(_ path: String) -> Bool {
        guard !ProblemFinder.isProtected(path) else { return false }
        let folders = data.watchedFolders.map(\.path) + [Persistence.deactivatedDirectory.path, NSHomeDirectory() + "/Library/Fonts"]
        return ProblemFinder.isInLibraryFolder(path, folders: folders)
    }

    /// Moves files to the Trash, never deleting them, and never the copy to keep.
    func trashFiles(_ paths: [String], keeping keep: String? = nil) {
        let fm = FileManager.default
        if let keep, !fm.fileExists(atPath: keep) {
            showToast("The copy to keep is missing, so nothing was moved.")
            return
        }
        var moved = 0, failed = 0
        for path in paths where path != keep && mayTrash(path) {
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                data.installedCopies.removeValue(forKey: path)
                data.registeredPaths.remove(path)
                moved += 1
            } catch {
                NSLog("Point: trash \(path) failed: \(error)")
                failed += 1
            }
        }
        if failed > 0 {
            showToast("Couldn't move \(failed == 1 ? "1 file" : "\(failed) files") to the Trash.")
        } else {
            showToast(moved == 1 ? "Moved to the Trash." : "Moved \(moved) files to the Trash.")
        }
        save()
        scheduleRescan(after: 0.3)
    }

    /// A face standing for one particular file of a font that's active from several.
    func conflictFace(at path: String, template: FontFace, others: [String]) -> LibraryFace {
        var face = template
        face.path = path
        face.index = 0
        let kind = activeKind(of: path, userFonts: NSHomeDirectory() + "/Library/Fonts/")
        return LibraryFace(face: face, status: .active(kind), otherPaths: others.filter { $0 != path })
    }

    func forgetRegistration(_ path: String) {
        data.registeredPaths.remove(path)
        save()
        refreshProblems()
        Task { _ = await CoreTextRegistration.unregister([URL(fileURLWithPath: path)], scope: .persistent) }
    }

    func forgetInstalledCopy(_ path: String) {
        data.installedCopies.removeValue(forKey: path)
        save()
        refreshProblems()
    }

    func removeMember(_ familyName: String, fromSet id: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == id }) else { return }
        data.sets[index].familyNames.removeAll { $0 == familyName }
        save()
        refreshProblems()
    }

    /// Replaces a font used from an external disk with a copy in ~/Library/Fonts.
    func installCopyInstead(of face: LibraryFace) async {
        await activate([face], method: .copy)
        await deactivate([face])
    }
}
