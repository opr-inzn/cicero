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
                    try Self.moveItem(Self.url(from), to: destination)
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
                try? Self.moveItem(Self.url(to), to: Self.url(from))
                failed.append(from)
            }
            try? fm.removeItem(at: turningOffList)
        }
        return (placed, failed)
    }

    /// What `installOff` does with each of some files, worked out before it copies any, so a sheet can say how many it
    /// copies and the progress counts only those.
    public struct CopyPlan: Sendable {
        /// The files to copy, in the order given, each with the folder it goes into.
        public var toCopy: [(path: String, folder: URL)] = []
        /// Each file whose copy is in already (see `installedAlready`) → that copy.
        public var inAlready: [String: String] = [:]
        /// Each file the same as one before it in `toCopy`: of the same name and contents, going into the same folder, so
        /// one copy stands for both, as with "Font.otf" in two of another app's folders. File → that one.
        public var sameAs: [String: String] = [:]
    }

    /// Works out what `installOff` does with `files`: takes those in already, copies one of each set of the same file,
    /// copies the rest. Reads only files whose name is taken where they go (and, for Cicero's Library, each file's
    /// family), so it's quick unless they're in already.
    public func copyPlan(_ files: [String]) -> CopyPlan {
        var plan = CopyPlan()
        var seen = Set<String>()
        // Where a file of each name goes (folder/name) → the files to copy there under it.
        var named: [String: [String]] = [:]
        for path in files where seen.insert(path).inserted {
            if Task.isCancelled { break }
            let folder = installFolder(for: path, family: nil)
            if let there = installedAlready(path, into: folder) {
                plan.inAlready[path] = there
                continue
            }
            let key = folder.appendingPathComponent((path as NSString).lastPathComponent, isDirectory: false).path
            if let original = named[key]?.first(where: { Self.isIdenticalCopy(path, of: $0) }) {
                plan.sameAs[path] = original
                continue
            }
            named[key, default: []].append(path)
            plan.toCopy.append((path, folder))
        }
        return plan
    }

    /// Copies font files in where installing puts them, off, as an import brings in another app's fonts: into
    /// ~/Library/Fonts (see `moveIntoFontsFolderOff`), or their family's folder in Cicero's Library, where a font is on
    /// only while Cicero has it registered. A file with the same contents there already, under its name or a numbered one
    /// ("Name 2.otf", as one of two files of the same name went in), or elsewhere Cicero has it (see `installedAlready`),
    /// is taken as it is, on or off: importing again copies nothing twice. Of files with the same name and contents,
    /// one is copied and stands for the others (see `copyPlan`). Nothing is remembered as a copy of anything: the files are
    /// the user's own from now on. Those macOS didn't show off in time, as it can while it's busy, are tried once more at
    /// the end, with longer to wait (`retryWait`). Progress counts the files to copy. Returns where each file is now,
    /// which of those are new, and the files that didn't go in; cancelling stops between batches.
    @concurrent
    public func installOff(_ files: [String], progress: @escaping @Sendable (Int, Int) -> Void) async
        -> (placed: [String: String], new: [String], failed: [String]) {
        let fm = FileManager.default
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        let plan = copyPlan(files)
        let total = plan.toCopy.count
        var placed = plan.inAlready
        var new: [String] = []
        // The copies moved into ~/Library/Fonts, off, and when they were last looked at (see `turnOffAgain`).
        var intoFontsFolderSoFar: [String] = []
        var registeredAgain = Set<String>()
        var lastLook = ContinuousClock.now
        // Staged copies macOS didn't take in time → where they go in ~/Library/Fonts, and the file each is a copy of.
        var again: [String: (destination: String, source: String)] = [:]
        for start in stride(from: 0, to: total, by: Self.offBatchSize) {
            if Task.isCancelled { break }
            if ContinuousClock.now - lastLook > Self.lookAgainEvery {
                await turnOffAgain(intoFontsFolderSoFar, registeredAgain: &registeredAgain)
                lastLook = .now
            }
            progress(start, total)
            // Each staged copy → where it goes in ~/Library/Fonts, and the file it's a copy of.
            var intoFontsFolder: [String: String] = [:]
            var sources: [String: String] = [:]
            for (path, folder) in plan.toCopy[start..<min(start + Self.offBatchSize, total)] {
                let name = (path as NSString).lastPathComponent
                let same = folder.appendingPathComponent(name, isDirectory: false)
                // One that went in since the plan was made.
                if let there = installedAlready(path, into: folder) {
                    placed[path] = there
                    continue
                }
                // Copied into Cicero's staging folder first and moved in from there, so a Fonts folder never has half a file.
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
                intoFontsFolderSoFar.append(destination)
            }
            for staged in moved.failed {
                if let source = sources[staged], let destination = intoFontsFolder[staged] { again[staged] = (destination, source) }
            }
        }
        if !again.isEmpty, !Task.isCancelled {
            var patient = self
            patient.confirmationWait = max(confirmationWait, Self.retryWait)
            let moved = await patient.moveIntoFontsFolderOff(again.mapValues(\.destination))
            for (staged, destination) in moved.placed {
                guard let source = again[staged]?.source else { continue }
                placed[source] = destination
                new.append(destination)
                intoFontsFolderSoFar.append(destination)
            }
        }
        for staged in again.keys { try? fm.removeItem(atPath: staged) }
        // Not once cancelled: the copies go again.
        if !intoFontsFolderSoFar.isEmpty, !Task.isCancelled {
            await turnOffAgain(intoFontsFolderSoFar, registeredAgain: &registeredAgain)
            // And once more for the last ones, which macOS may not have noticed yet.
            try? await Task.sleep(for: .seconds(3))
            await turnOffAgain(intoFontsFolderSoFar, registeredAgain: &registeredAgain)
        }
        // The same files as those copied take their copies.
        for (path, original) in plan.sameAs { if let copy = placed[original] { placed[path] = copy } }
        if total > 0 { progress(total, total) }
        var seen = Set<String>()
        let failed = Task.isCancelled ? [] : files.filter { placed[$0] == nil && seen.insert($0).inserted }
        return (placed, new, failed)
    }

    /// How long macOS gets to show the files `installOff` tries once more on: a busy Mac took over the 2 seconds the
    /// first time gives (`confirmationWait`).
    static let retryWait: Duration = .seconds(10)

    /// How often `installOff` looks for copies macOS turned on again, and how many it looks at, at most.
    static let lookAgainEvery: Duration = .seconds(10)
    static let lookingAtMost = 500

    /// Turns off again the files among `paths`, in ~/Library/Fonts, that macOS's list of fonts it has off doesn't name any
    /// more. While it's busy, macOS can notice files that arrived there after `moveIntoFontsFolderOff` turned them off
    /// (in a macOS 15 VM, one or two batches of 20 in the first minute of an import of 31,209 fonts): it then forgets that
    /// they're off, and has them on, or not at all until it looks at the folder again, which turns them on. One it has on is
    /// turned off; one it doesn't have is registered first, as turning off a file macOS doesn't have doesn't stick, but
    /// only once (`registeredAgain`), so a file the list names by another path isn't turned on and off at every look.
    /// Looking costs one read of the list, and a question for each file it doesn't name: no more than
    /// `lookingAtMost` at a time, so a list that names the files by other paths can't have every file asked about. An
    /// empty list says nothing: the files turned off are on it, unless it can't be read.
    func turnOffAgain(_ paths: [String], registeredAgain: inout Set<String>) async {
        guard !paths.isEmpty else { return }
        let off = registrar.offFontPaths()
        guard !off.isEmpty else { return }
        let unlisted = Array(paths.lazy.filter { !off.contains($0) && FileManager.default.fileExists(atPath: $0) }.prefix(Self.lookingAtMost))
        guard !unlisted.isEmpty else { return }
        let on = unlisted.filter { registrar.isActive(Self.url($0)) }
        let unregistered = unlisted.filter { !on.contains($0) && !registeredAgain.contains($0) }
        registeredAgain.formUnion(unregistered)
        let taken = unregistered.isEmpty ? [] : await Set(unregistered).subtracting(registerAndConfirm(unregistered, scope: .persistent))
        let turningOff = on + unregistered.filter(taken.contains)
        guard !turningOff.isEmpty else { return }
        _ = await registrar.setEnabled(turningOff.map(Self.url), false)
    }

    /// The file `installOff` takes as it is for `path`: one with the same contents where it would copy it (`folder`, else
    /// where installing puts it), in ~/Library/Fonts while Cicero's Library is used, in an app's own folder
    /// (`appFontFolders`), or in the Inactive folder, where one waits that was turned off in an app's folder: a copy
    /// would have the font twice, on beside the one Proofing lists. Nil when it would copy it.
    public func installedAlready(_ path: String, into folder: URL? = nil) -> String? {
        let folder = folder ?? installFolder(for: path, family: nil)
        let name = (path as NSString).lastPathComponent
        let installed = folder == locations.userFonts ? [folder] : [folder, locations.userFonts]
        let looked = installed + locations.inactiveFolders + appFontFolders
        return looked.lazy.compactMap { Self.identicalFile(to: path, named: name, in: $0) }.first
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

    /// At launch: fonts earlier versions turned off by moving them out of ~/Library/Fonts into the Inactive folder (or
    /// a former one, while something in it waits to move) go where turning them on would put them, and stay off: into
    /// their family's folder in Cicero's Library when fonts are installed there, else back into ~/Library/Fonts (see
    /// `moveIntoFontsFolderOff`). Not one from an app's own folder, which goes back there when it's turned on, nor one
    /// that's on for now, nor one CoreText can't read (it would go in and come out again at every launch). One with the
    /// same name and contents as a file already where it goes goes to the Trash. Records naming a moved file as the
    /// original of a copy follow it. Returns how many files moved or went.
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
            if Self.isIdenticalCopy(same, of: path) {
                // To the Trash, as the user may have put it there; one the Trash won't take stays, rather than going in twice.
                if (try? trash(Self.url(path))) != nil { placed[path] = same }
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
                try Self.moveItem(Self.url(path), to: target)
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

    /// Where `moveFormerInactiveFolders` writes down what it's about to move, each item's path → where it goes, until the
    /// records that follow the moves are saved (see `forgetInactiveFolderMoves`).
    var inactiveFolderMovesList: URL { locations.support.appendingPathComponent("moving-inactive.json", isDirectory: false) }

    /// Whether a former Inactive folder is there, or moves are written down that the records may not have followed yet:
    /// `moveFormerInactiveFolders` has something to do.
    public var hasFormerInactiveFolders: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: inactiveFolderMovesList.path) || locations.formerInactiveFolders.contains { fm.fileExists(atPath: $0.path) }
    }

    /// At launch: up to 0.11.0 the Inactive folder was in Cicero's support folder, where apps that remove an app delete
    /// it, and up to 0.10.10 it was called Deactivated there. What's in a former one moves into `Locations.inactiveFolder`,
    /// ~/Cicero/Inactive: the whole folder, a rename, when that isn't there yet (or is empty), else item by item beside
    /// what's there, under names of its own (see `uniqueName`). The former folder goes once nothing but .DS_Store is left.
    /// Not a file on right now (one on for an app folder's open app, or that macOS has registered; one on until Cicero
    /// quit is off by now): macOS has it from where it is, so it stays, and its folder still counts as an Inactive folder
    /// (`Locations.inactiveFolders`) until a later launch moves it. Nothing moves when ~/Cicero/Inactive can't be made.
    ///
    /// Every move is written down first (`inactiveFolderMovesList`), and the moves of a launch that stopped before its
    /// records were saved are taken up again, those that happened: the records follow them all. Returns the records and
    /// the moves, item → where it went; once the records are saved, `forgetInactiveFolderMoves`.
    @concurrent
    public func moveFormerInactiveFolders(_ records: ActivationRecords) async -> (records: ActivationRecords, moves: [String: String]) {
        let fm = FileManager.default
        let folder = locations.inactiveFolder
        var moves: [String: String] = [:]
        // What a launch that stopped moved, but maybe never saved the records of.
        if let data = try? Data(contentsOf: inactiveFolderMovesList), let listed = try? JSONDecoder().decode([String: String].self, from: data) {
            for (from, to) in listed where Self.exists(to) {
                // One copied onto another disk whose original was still to go: nothing else had that name.
                if Self.exists(from), !(Self.isIdenticalCopy(to, of: from) && (try? fm.removeItem(atPath: from)) != nil) { continue }
                moves[from] = to
            }
        }
        // A copy onto another disk that stopped halfway, under a hidden name nothing reads, in a folder there too.
        let halfCopies = (fm.enumerator(atPath: folder.path)?.allObjects as? [String] ?? [])
            .filter { ($0 as NSString).lastPathComponent.hasPrefix(Self.movingPrefix) }
        for path in halfCopies {
            Self.unlock(folder.appendingPathComponent(path))
            try? fm.removeItem(at: folder.appendingPathComponent(path))
        }
        for former in locations.formerInactiveFolders where Self.exists(former.path) {
            let names = ((try? fm.contentsOfDirectory(atPath: former.path)) ?? []).filter { $0 != ".DS_Store" }.sorted()
            let staying = Set(names.filter { name in
                let path = former.appendingPathComponent(name).path
                return records.temporary.keys.contains { $0 == path || $0.hasPrefix(path + "/") }
                    || FontFileReader.fontExtensions.contains((name as NSString).pathExtension.lowercased()) && registrar.isActive(Self.url(path))
            })
            let movable = names.filter { !staying.contains($0) }
            if movable.isEmpty {
                if names.isEmpty { _ = Self.removeIfEmpty(former.path) }
                continue
            }
            // The whole folder, where nothing is in the way.
            if staying.isEmpty, !Self.exists(folder.path) || Self.removeIfEmpty(folder.path),
               (try? fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil {
                let planned = Dictionary(uniqueKeysWithValues: names.map { (former.appendingPathComponent($0).path, folder.appendingPathComponent($0).path) })
                if (try? noteInactiveFolderMoves(moves.merging(planned) { first, _ in first })) != nil,
                   renamex_np(former.path, folder.path, UInt32(RENAME_EXCL)) == 0 {
                    moves.merge(planned) { first, _ in first }
                    continue
                }
            }
            guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { continue }
            var taken = Set(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).map(Self.nameKey))
            // Onto another disk a folder goes file by file (see `fileMoves`).
            let otherDisk = Self.disk(of: folder.path) != Self.disk(of: former.path)
            var items: [(from: URL, to: URL)] = []
            for name in movable {
                let unique = Self.uniqueName(for: name, taken: &taken)
                items.append((former.appendingPathComponent(name), folder.appendingPathComponent(unique)))
            }
            let planned = otherDisk ? items.flatMap { Self.fileMoves($0.from, to: $0.to) } : items
            let all = moves.merging(planned.map { ($0.from.path, $0.to.path) }) { first, _ in first }
            guard (try? noteInactiveFolderMoves(all)) != nil else { continue }
            for (from, to) in planned {
                guard (try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
                      (try? Self.moveItem(from, to: to)) != nil
                else { continue }
                moves[from.path] = to.path
            }
            // The folders the files left, and those made for files that couldn't go.
            for item in items {
                Self.removeEmptyFolders(item.from.path)
                Self.removeEmptyFolders(item.to.path)
            }
            _ = Self.removeIfEmpty(former.path)
        }
        return (Self.records(records, following: moves), moves)
    }

    /// Once the records `moveFormerInactiveFolders` returned are saved: what it wrote down goes.
    public func forgetInactiveFolderMoves() {
        try? FileManager.default.removeItem(at: inactiveFolderMovesList)
    }

    private func noteInactiveFolderMoves(_ moves: [String: String]) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(moves).write(to: inactiveFolderMovesList, options: .atomic)
        // On the disk itself before anything moves, so a power cut can't leave the moves without it.
        guard UserDataStore.syncToDisk(inactiveFolderMovesList) else { throw POSIXError(.EIO) }
    }

    /// The records with every path in a moved item (item → where it went) where it is now (see `paths(_:following:)`).
    static func records(_ records: ActivationRecords, following moves: [String: String]) -> ActivationRecords {
        guard !moves.isEmpty else { return records }
        let moved = movedPath(following: moves)
        var records = records
        records.installedCopies = Dictionary(records.installedCopies.map { (moved($0.key), moved($0.value)) }, uniquingKeysWith: { first, _ in first })
        records.inPlace = Set(records.inPlace.map(moved))
        records.appFolderOrigins = Dictionary(records.appFolderOrigins.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        records.temporary = Dictionary(records.temporary.map { (moved($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        return records
    }

    /// Paths where they are after these moves (item → where it went): the item's own, or one in it. The same name in
    /// another Unicode form counts as the same, as the disk has it (Swift's strings compare so).
    public static func paths(_ paths: [String], following moves: [String: String]) -> [String] {
        guard !moves.isEmpty else { return paths }
        return paths.map(movedPath(following: moves))
    }

    private static func movedPath(following moves: [String: String]) -> (String) -> String {
        { path in
            var item = path, rest = ""
            while item.count > 1 {
                if let to = moves[item] { return to + rest }
                rest = "/" + (item as NSString).lastPathComponent + rest
                item = (item as NSString).deletingLastPathComponent
            }
            return path
        }
    }

    /// A name as the disk compares it: letter case ignored, as on the Mac's own disk, and one Unicode form as any.
    private static func nameKey(_ name: String) -> String { name.lowercased() }

    /// "Name.otf", then "Name 2.otf", "Name 3.otf"…, the first not in `taken` (as `nameKey` has them), which it joins.
    static func uniqueName(for name: String, taken: inout Set<String>) -> String {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = name, number = 2
        while taken.contains(nameKey(candidate)) {
            candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            number += 1
        }
        taken.insert(nameKey(candidate))
        return candidate
    }

    /// Hidden names of items being copied onto another disk, until they're whole.
    static let movingPrefix = ".cicero-moving-"

    /// Moves an item where nothing is, keeping its Date Added, which macOS sets anew for a file moved into another folder,
    /// so a font Cicero turns off or on arrives no more than it did before (see `Family.lastAdded`): a rename on the same
    /// disk, never over anything. Onto another disk a file is copied under a hidden name first, so a copy that stops
    /// halfway is never taken for a font, then named, and the original goes; one that can't go, on a read-only disk or
    /// Locked, takes the copy back out, so there's never two. Not a folder, whose deleting could stop partway, after some
    /// of its files went: those would be only in the copy, and taking it back out would lose them. A folder goes onto
    /// another disk file by file (see `fileMoves`).
    static func moveItem(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        let added = dateAdded(of: from)
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) != 0 {
            let error = errno
            guard error == EXDEV, !isFolder(from.path) else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
            let copy = to.deletingLastPathComponent().appendingPathComponent(movingPrefix + UUID().uuidString)
            do {
                try fm.copyItem(at: from, to: copy)
                unlock(copy)
                guard renamex_np(copy.path, to.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } catch {
                try? fm.removeItem(at: copy)
                throw error
            }
            do {
                try fm.removeItem(at: from)
            } catch {
                try? fm.removeItem(at: to)
                throw error
            }
        }
        if let added { setDateAdded(added, of: to) }
    }

    /// Takes Locked off a hidden copy of Cicero's own, which `copyItem` gives its original's flags: locked, it could be
    /// neither named nor taken back out, and stayed behind at every try. Other flags, like Hidden, stay.
    static func unlock(_ url: URL) {
        let locked = UInt32(UF_IMMUTABLE | UF_APPEND)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_flags & locked != 0 else { return }
        lchflags(url.path, info.st_flags & ~locked)
    }

    /// Moving `from` to `to` file by file, as onto another disk: a folder's items each to the same place in `to`, at any
    /// depth, but for .DS_Store; anything else, a symbolic link too, is one move. A folder with no files gives none.
    static func fileMoves(_ from: URL, to: URL) -> [(from: URL, to: URL)] {
        guard isFolder(from.path) else { return [(from, to)] }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: from.path)) ?? []).filter { $0 != ".DS_Store" }.sorted()
        return names.flatMap { fileMoves(from.appendingPathComponent($0), to: to.appendingPathComponent($0)) }
    }

    /// Whether a folder is at the path, itself, not a symbolic link to one.
    static func isFolder(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// The disk a file or folder is on, through symbolic links; nil when it isn't there.
    static func disk(of path: String) -> dev_t? {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_dev : nil
    }

    /// Whether anything is at the path, a symbolic link that leads nowhere too.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
