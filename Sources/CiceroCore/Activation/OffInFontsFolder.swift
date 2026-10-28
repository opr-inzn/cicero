import CoreText
import Foundation

extension ActivationEngine {
    /// How many files `moveIntoFontsFolderOff` registers at once.
    static let offBatchSize = 20

    /// Where `moveIntoFontsFolderOff` writes the files on their way in, until they're off.
    var turningOffList: URL { locations.support.appendingPathComponent("turning-off.json", isDirectory: false) }

    /// Moves files into a Fonts folder, off. macOS turns on whatever arrives in one, a second or so later, so each batch is
    /// registered at once and turned off as soon as macOS shows it on: its fonts are on for a few hundredths of a second
    /// (about 20 ms for 1 file or 20, in a macOS 26 VM), and macOS keeps them off from then on. Turning a file off before
    /// macOS has it doesn't stick. `moves` is each file → where it goes; one whose place is taken goes beside it, as
    /// "Name 2.otf". The files on their way in are written down first (see `finishTurningOff`), so stopping halfway leaves
    /// none on. One macOS won't take or won't turn off goes back where it was. `exactly`, one whose place is taken stays
    /// where it is instead. Returns where each file went, and the files that stayed.
    public func moveIntoFontsFolderOff(_ moves: [String: String], exactly: Bool = false) async -> (placed: [String: String], failed: [String]) {
        let fm = FileManager.default
        var placed: [String: String] = [:]
        var failed: [String] = []
        let all = moves.sorted { $0.key < $1.key }
        for start in stride(from: 0, to: all.count, by: Self.offBatchSize) {
            var moved: [(from: String, to: String)] = []
            for (from, to) in all[start..<min(start + Self.offBatchSize, all.count)] {
                let target = Self.url(to)
                let destination = Self.uniqueURL(for: target.lastPathComponent, in: target.deletingLastPathComponent())
                guard !exactly || destination.path == target.path else {
                    failed.append(from)
                    continue
                }
                do {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try noteTurningOff(moved.map(\.to) + [destination.path])
                    try Self.move(Self.url(from), to: destination)
                    moved.append((from, destination.path))
                } catch {
                    failed.append(from)
                }
            }
            guard !moved.isEmpty else { continue }
            let paths = moved.map(\.to)
            // Turned off only once macOS shows it on: before that, turning it off wouldn't stick.
            let untaken = await registerAndConfirm(paths, scope: .persistent)
            let stillOn = await registrar.setEnabled(paths.filter { !untaken.contains($0) }.map(Self.url), false)
            for (from, to) in moved {
                guard untaken.contains(to) || stillOn.contains(to) else {
                    placed[from] = to
                    continue
                }
                // macOS would turn on one it didn't take as soon as it noticed it, and one that won't go off is on.
                if stillOn.contains(to) { _ = await registrar.unregister([Self.url(to)], scope: .persistent) }
                try? Self.move(Self.url(to), to: Self.url(from))
                failed.append(from)
            }
            try? fm.removeItem(at: turningOffList)
        }
        return (placed, failed)
    }

    /// Copies font files in where installing puts them, off, as an import brings in another app's fonts: into
    /// ~/Library/Fonts (see `moveIntoFontsFolderOff`), or their family's folder in Cicero's Library, where a font is on
    /// only while Cicero has it registered. A file with the same contents there already, under its name or a numbered one
    /// ("Name 2.otf", as one of two files of the same name went in), or in ~/Library/Fonts while Cicero's Library is
    /// used, is taken as it is, on or off: importing again copies nothing twice. Nothing is remembered as a copy of
    /// anything: the files are the user's own from now on. Returns where each
    /// file is now, and which of those are new; cancelling stops between batches.
    @concurrent
    public func installOff(_ files: [String], progress: @escaping @Sendable (Int, Int) -> Void) async -> (placed: [String: String], new: [String]) {
        let fm = FileManager.default
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        var placed: [String: String] = [:]
        var new: [String] = []
        for start in stride(from: 0, to: files.count, by: Self.offBatchSize) {
            if Task.isCancelled { break }
            progress(start, files.count)
            // Each staged copy → where it goes in ~/Library/Fonts, and the file it's a copy of.
            var intoFontsFolder: [String: String] = [:]
            var sources: [String: String] = [:]
            for path in files[start..<min(start + Self.offBatchSize, files.count)] where placed[path] == nil {
                let folder = installFolder(for: path, family: nil)
                let name = (path as NSString).lastPathComponent
                let same = folder.appendingPathComponent(name, isDirectory: false)
                let looked = folder == locations.userFonts ? [folder] : [folder, locations.userFonts]
                if let there = looked.lazy.compactMap({ Self.identicalFile(to: path, named: name, in: $0) }).first {
                    placed[path] = there
                    continue
                }
                // Copied next to where it goes first, so a Fonts folder never has half a file.
                let staged = staging.appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: false)
                do {
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    try fm.copyItem(at: Self.url(path), to: staged)
                } catch {
                    continue
                }
                if folder == locations.userFonts {
                    intoFontsFolder[staged.path] = same.path
                    sources[staged.path] = path
                    continue
                }
                let destination = Self.uniqueURL(for: name, in: folder)
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    try fm.moveItem(at: staged, to: destination)
                    placed[path] = destination.path
                    new.append(destination.path)
                } catch {
                    try? fm.removeItem(at: staged)
                }
            }
            let moved = await moveIntoFontsFolderOff(intoFontsFolder)
            for (staged, destination) in moved.placed {
                guard let source = sources[staged] else { continue }
                placed[source] = destination
                new.append(destination)
            }
            for staged in moved.failed { try? fm.removeItem(atPath: staged) }
        }
        progress(files.count, files.count)
        return (placed, new)
    }

    /// A file in `folder` with the same contents as `path`, under `name` or a numbered name as `uniqueURL` gives them.
    static func identicalFile(to path: String, named name: String, in folder: URL) -> String? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name, isDirectory: false)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if isIdenticalCopy(candidate.path, of: path) { return candidate.path }
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)", isDirectory: false)
            number += 1
        }
        return nil
    }

    private func noteTurningOff(_ paths: [String]) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(paths).write(to: turningOffList, options: .atomic)
    }

    /// At launch: files `moveIntoFontsFolderOff` was moving when Cicero stopped are turned off where they are, those that
    /// went on.
    public func finishTurningOff() async {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: turningOffList) else { return }
        let paths = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        let on = paths.filter { isInsideFontsFolder($0) && fm.fileExists(atPath: $0) && registrar.isActive(Self.url($0)) }
        if !on.isEmpty { _ = await registrar.setEnabled(on.map(Self.url), false) }
        try? fm.removeItem(at: turningOffList)
    }

    /// At launch: fonts earlier versions turned off by moving them out of ~/Library/Fonts into the Inactive folder (or the
    /// former one, while it's waiting to be renamed) go
    /// where turning them on would put them, and stay off: into their family's folder in Cicero's Library when fonts are
    /// installed there, else back into ~/Library/Fonts (see `moveIntoFontsFolderOff`). Not one from an app's own folder,
    /// which goes back there when it's turned on, nor one that's on for now, nor one CoreText can't read (it would go in and
    /// come out again at every launch). One with the same name and contents as a file already where it goes is a spare
    /// and goes, as turning it on did. Records naming a moved file as the original of a copy follow it. Returns how many
    /// files moved or went.
    public func emptyInactiveFolder(_ records: ActivationRecords) async -> (records: ActivationRecords, moved: Int) {
        let fm = FileManager.default
        let all = locations.inactiveFolders.flatMap { folder in
            ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().map { folder.appendingPathComponent($0, isDirectory: false).path }
        }
        let files = all.filter { path in
            var info = stat()
            return !(path as NSString).lastPathComponent.hasPrefix(".")
                && FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
                && lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
                && records.appFolderOrigins[path] == nil && records.temporary[path] == nil
                && !registrar.isActive(Self.url(path)) && !FontFileReader.faces(atPath: path).isEmpty
        }
        guard !files.isEmpty else { return (records, 0) }
        var placed: [String: String] = [:]
        var intoFontsFolder: [String: String] = [:]
        for path in files {
            let destination = installFolder(for: path, family: nil)
            let same = destination.appendingPathComponent((path as NSString).lastPathComponent, isDirectory: false).path
            if Self.isIdenticalCopy(same, of: path), (try? fm.removeItem(atPath: path)) != nil {
                placed[path] = same
                continue
            }
            if destination == locations.userFonts {
                intoFontsFolder[path] = destination.appendingPathComponent((path as NSString).lastPathComponent, isDirectory: false).path
                continue
            }
            // Fonts in Cicero's Library are on only while it has them registered: one put there is off.
            let target = Self.uniqueURL(for: (path as NSString).lastPathComponent, in: destination)
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                try Self.move(Self.url(path), to: target)
                placed[path] = target.path
            } catch {
                continue
            }
        }
        placed.merge(await moveIntoFontsFolderOff(intoFontsFolder).placed) { first, _ in first }
        var records = records
        for (copy, original) in records.installedCopies {
            // A copy whose original was a spare of it is the user's own again.
            if let moved = placed[original] { records.installedCopies[copy] = moved == copy ? nil : moved }
        }
        return (records, placed.count)
    }

    /// At launch: the Inactive folder was called Deactivated up to 0.10.10. The former folder is renamed or, when the
    /// Inactive folder has anything in it already, what's in it moves in beside that, under names of its own; the records
    /// follow. Not while a font in it is on for an app folder's open app (one on until Cicero quit is off by now): macOS
    /// has it from where it is, so the folder waits for a later launch, and meanwhile counts as the Inactive folder too
    /// (`Locations.inactiveFolders`). Returns whether anything moved.
    public func moveFormerInactiveFolder(_ records: ActivationRecords) -> (records: ActivationRecords, moved: Bool) {
        let fm = FileManager.default
        let former = locations.formerInactiveFolder
        let folder = locations.inactiveFolder
        guard fm.fileExists(atPath: former.path) else { return (records, false) }
        let prefix = former.path + "/"
        guard !records.temporary.keys.contains(where: { $0.hasPrefix(prefix) }) else { return (records, false) }
        var moves: [String: String] = [:]
        var renamed = false
        if !fm.fileExists(atPath: folder.path) || Self.removeIfEmpty(folder.path) {
            guard (try? fm.moveItem(at: former, to: folder)) != nil else { return (records, false) }
            renamed = true
        } else {
            for name in ((try? fm.contentsOfDirectory(atPath: former.path)) ?? []).sorted() where name != ".DS_Store" {
                let destination = Self.uniqueURL(for: name, in: folder)
                if (try? Self.move(former.appendingPathComponent(name), to: destination)) != nil {
                    moves[former.appendingPathComponent(name).path] = destination.path
                }
            }
            _ = Self.removeIfEmpty(former.path)
        }
        func moved(_ path: String) -> String {
            if renamed, path.hasPrefix(prefix) { return folder.path + "/" + path.dropFirst(prefix.count) }
            return moves[path] ?? path
        }
        var records = records
        records.installedCopies = Dictionary(records.installedCopies.map { (moved($0.key), moved($0.value)) }, uniquingKeysWith: { first, _ in first })
        records.inPlace = Set(records.inPlace.map(moved))
        records.appFolderOrigins = Dictionary(records.appFolderOrigins.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        return (records, renamed || !moves.isEmpty)
    }
}
