import CoreText
import Foundation
import Synchronization

extension ActivationEngine {
    static let offBatchSize = 20

    static let keptOff = Mutex<Set<String>>([])

    static func stopKeepingOff(_ paths: some Sequence<String>) {
        keptOff.withLock { $0.subtract(paths) }
    }

    var turningOffList: URL { locations.support.appendingPathComponent("turning-off.json", isDirectory: false) }

    // One for each call: an import, a Replace and a Put Back can move files in at the same time.
    private func newTurningOffList() -> URL {
        locations.support.appendingPathComponent("turning-off-\(UUID().uuidString).json", isDirectory: false)
    }

    var turningOffLists: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: locations.support.path)) ?? []
        return names.filter { $0 == "turning-off.json" || $0.hasPrefix("turning-off-") && $0.hasSuffix(".json") }
            .map { locations.support.appendingPathComponent($0, isDirectory: false) }
    }

    public func moveIntoFontsFolderOff(_ moves: [String: String], exactly: Bool = false, staysOn: Set<String> = [])
        async -> (placed: [String: String], failed: [String]) {
        let fm = FileManager.default
        var placed: [String: String] = [:]
        var failed: [String] = []
        let all = moves.sorted { $0.key < $1.key }
        let list = newTurningOffList()
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
                    let goingOff = moved.filter { !staysOn.contains($0.from) }.map(\.to)
                    // Written down before the file moves in, so a stop halfway leaves none of them on.
                    try noteTurningOff(goingOff + (staysOn.contains(from) ? [] : [destination.path]), in: list)
                    try Self.moveItem(Self.url(from), to: destination)
                    moved.append((from, destination.path))
                } catch {
                    failed.append(from)
                }
            }
            guard !moved.isEmpty else {
                try? fm.removeItem(at: list)
                continue
            }
            let paths = moved.map(\.to)
            let on = Set(moved.filter { staysOn.contains($0.from) }.map(\.to))
            // Turned off only once macOS shows it on: before that, turning it off wouldn't stick.
            let untaken = await registerAndConfirm(paths, scope: .persistent)
            let stillOn = await registrar.setEnabled(paths.filter { !untaken.contains($0) && !on.contains($0) }.map(Self.url), false)
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
            try? fm.removeItem(at: list)
        }
        return (placed, failed)
    }

    public struct CopyPlan: Sendable {
        public var toCopy: [(path: String, folder: URL)] = []
        public var inAlready: [String: String] = [:]
        public var sameAs: [String: String] = [:]
    }

    public func copyPlan(_ files: [String]) -> CopyPlan {
        var plan = CopyPlan()
        var seen = Set<String>()
        var named: [String: [String]] = [:]
        for path in files where seen.insert(path).inserted {
            if Task.isCancelled { break }
            let folder = installFolder(for: path, family: nil)
            if let there = installedAlready(path, into: folder) {
                plan.inAlready[path] = there
                continue
            }
            let key = folder.path + "/" + Self.nameKey((path as NSString).lastPathComponent)
            if let original = named[key]?.first(where: { Self.isIdenticalCopy(path, of: $0) }) {
                plan.sameAs[path] = original
                continue
            }
            named[key, default: []].append(path)
            plan.toCopy.append((path, folder))
        }
        return plan
    }

    @concurrent
    public func installOff(_ files: [String], on: Set<String> = [], keepOnWhenCancelled: Bool = false,
                           progress: @escaping @Sendable (Int, Int) -> Void) async
        -> (placed: [String: String], new: [String], failed: [String]) {
        // Without it, macOS slows an app it can't see (App Nap) and lets the Mac sleep, and every wait for fontd here takes far longer.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                             reason: "Copying fonts in")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let fm = FileManager.default
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        let plan = copyPlan(files)
        let total = plan.toCopy.count
        var placed = plan.inAlready
        var new: [String] = []
        let onSources = on.union(plan.sameAs.filter { on.contains($0.key) }.map(\.value))
        var stagedOn = Set<String>()
        var onSoFar: [String] = []
        var intoFontsFolderSoFar: [String] = []
        var lookedAt = TurnOffAgain()
        var lastLook = ContinuousClock.now
        var again: [String: (destination: String, source: String)] = [:]
        for start in stride(from: 0, to: total, by: Self.offBatchSize) {
            if Task.isCancelled { break }
            if ContinuousClock.now - lastLook > Self.lookAgainEvery {
                await turnOffAgain(intoFontsFolderSoFar, state: &lookedAt)
                lastLook = .now
            }
            progress(start, total)
            var intoFontsFolder: [String: String] = [:]
            var sources: [String: String] = [:]
            for (path, folder) in plan.toCopy[start..<min(start + Self.offBatchSize, total)] {
                let name = (path as NSString).lastPathComponent
                let same = folder.appendingPathComponent(name, isDirectory: false)
                if let there = installedAlready(path, into: folder) {
                    placed[path] = there
                    continue
                }
                // Copied into Cicero's staging folder first and moved in from there, so a Fonts folder never has half a file.
                let staged = staging.appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: false)
                do {
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    try fm.copyItem(at: Self.url(path), to: staged)
                    // Without the original's quarantine tag: with it, fontworker opens the quarantine database for each file it reads (and fails), so slowly that fontd reads the Fonts folder again and again.
                    removexattr(staged.path, "com.apple.quarantine", 0)
                } catch {
                    continue
                }
                if folder == locations.userFonts {
                    intoFontsFolder[staged.path] = same.path
                    sources[staged.path] = path
                    if onSources.contains(path) { stagedOn.insert(staged.path) }
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
            let moved = await moveIntoFontsFolderOff(intoFontsFolder, staysOn: stagedOn)
            for (staged, destination) in moved.placed {
                guard let source = sources[staged] else { continue }
                placed[source] = destination
                new.append(destination)
                if stagedOn.contains(staged) {
                    onSoFar.append(destination)
                } else {
                    intoFontsFolderSoFar.append(destination)
                    Self.keptOff.withLock { _ = $0.insert(destination) }
                }
            }
            for staged in moved.failed {
                if let source = sources[staged], let destination = intoFontsFolder[staged] { again[staged] = (destination, source) }
            }
        }
        if !again.isEmpty, !Task.isCancelled {
            var patient = self
            patient.confirmationWait = max(confirmationWait, Self.retryWait)
            let moved = await patient.moveIntoFontsFolderOff(again.mapValues(\.destination), staysOn: stagedOn)
            for (staged, destination) in moved.placed {
                guard let source = again[staged]?.source else { continue }
                placed[source] = destination
                new.append(destination)
                if stagedOn.contains(staged) {
                    onSoFar.append(destination)
                } else {
                    intoFontsFolderSoFar.append(destination)
                    Self.keptOff.withLock { _ = $0.insert(destination) }
                }
            }
        }
        for staged in again.keys { try? fm.removeItem(atPath: staged) }
        // In a task of its own, also once cancelled, as the copies stay: in a cancelled task the waits would be cut short.
        let cancelled = Task.isCancelled
        let turningOff = cancelled && !keepOnWhenCancelled ? onSoFar : []
        if !intoFontsFolderSoFar.isEmpty || !turningOff.isEmpty {
            let engine = self, paths = intoFontsFolderSoFar + turningOff, earlier = lookedAt
            Self.keptOff.withLock { $0.formUnion(turningOff) }
            await Task {
                var lookedAt = earlier
                if !turningOff.isEmpty { _ = await engine.registrar.setEnabled(turningOff.map(Self.url), false) }
                await engine.turnOffAtLast(paths, state: &lookedAt)
            }.value
        }
        for (path, original) in plan.sameAs { if let copy = placed[original] { placed[path] = copy } }
        if total > 0 { progress(total, total) }
        var seen = Set<String>()
        let failed = Task.isCancelled ? [] : files.filter { placed[$0] == nil && seen.insert($0).inserted }
        return (placed, new, failed)
    }

    static let retryWait: Duration = .seconds(10)

    static let lookAgainEvery: Duration = .seconds(10)
    static let lookingAtMost = 500
    static let registeringAgainAtMost = 3
    static let lastLookAtMost: Duration = .seconds(120)
    static let watchAfterwards: Duration = .seconds(180)

    struct TurnOffAgain: Sendable {
        var settled = Set<String>()
        var tries: [String: Int] = [:]
    }

    func turnOffAtLast(_ paths: [String], state: inout TurnOffAgain) async {
        let deadline = ContinuousClock.now + Self.lastLookAtMost
        while await turnOffAgain(paths, state: &state, atMost: .max) > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(3))
        }
        let engine = self, settled = state
        // A busy fontd can take a copy in after it was turned off and forget that it's off, also after a last look that found nothing.
        Task.detached(priority: .utility) {
            var state = settled
            let end = ContinuousClock.now + Self.watchAfterwards
            while ContinuousClock.now < end {
                try? await Task.sleep(for: .seconds(10))
                await engine.turnOffAgain(paths, state: &state, atMost: .max)
            }
            Self.stopKeepingOff(paths)
        }
    }

    @discardableResult
    func turnOffAgain(_ paths: [String], state: inout TurnOffAgain, atMost: Int = Self.lookingAtMost) async -> Int {
        let kept = Self.keptOff.withLock { $0 }
        let paths = paths.filter(kept.contains)
        guard !paths.isEmpty else { return 0 }
        let off = registrar.offFontPaths()
        // An empty list means it couldn't be read: the files turned off are on it.
        guard !off.isEmpty else { return 0 }
        let settled = state.settled
        let unlisted = Array(paths.lazy.filter { !off.contains($0) && !settled.contains($0) && FileManager.default.fileExists(atPath: $0) }
            .prefix(atMost))
        guard !unlisted.isEmpty else { return 0 }
        let on = unlisted.filter { registrar.isActive(Self.url($0)) }
        let unregistered = unlisted.filter { !on.contains($0) && state.tries[$0, default: 0] < Self.registeringAgainAtMost }
        for path in unregistered { state.tries[path, default: 0] += 1 }
        // Turning off a file macOS doesn't have doesn't stick, so it's registered first.
        let taken = unregistered.isEmpty ? [] : await Set(unregistered).subtracting(registerAndConfirm(unregistered, scope: .persistent))
        let keptNow = Self.keptOff.withLock { $0 }
        let turningOff = (on + unregistered.filter(taken.contains)).filter(keptNow.contains)
        guard !turningOff.isEmpty else { return unregistered.count }
        let stillOn = await registrar.setEnabled(turningOff.map(Self.url), false)
        state.settled.formUnion(unregistered.filter { taken.contains($0) && !stillOn.contains($0) })
        return on.count + unregistered.count
    }

    public func installedAlready(_ path: String, into folder: URL? = nil) -> String? {
        let folder = folder ?? installFolder(for: path, family: nil)
        let name = (path as NSString).lastPathComponent
        let installed = folder == locations.userFonts ? [folder] : [folder, locations.userFonts]
        let looked = installed + locations.inactiveFolders + appFontFolders
        return looked.lazy.compactMap { Self.identicalFile(to: path, named: name, in: $0) }.first
    }

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

    private func noteTurningOff(_ paths: [String], in list: URL) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(paths).write(to: list, options: .atomic)
    }

    public func finishTurningOff() async {
        let fm = FileManager.default
        let lists = turningOffLists
        let paths = lists.flatMap { list in
            (try? Data(contentsOf: list)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        }
        let on = paths.filter { isInsideFontsFolder($0) && fm.fileExists(atPath: $0) && registrar.isActive(Self.url($0)) }
        if !on.isEmpty { _ = await registrar.setEnabled(on.map(Self.url), false) }
        for list in lists { try? fm.removeItem(at: list) }
    }

    public func trashStagingLeftovers() {
        finishReplacing()
        let fm = FileManager.default
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        // To the Trash, not deleted: an import's originals may be gone since.
        for name in (try? fm.contentsOfDirectory(atPath: staging.path)) ?? [] where name != ".DS_Store" {
            try? fm.trashItem(at: staging.appendingPathComponent(name, isDirectory: false), resultingItemURL: nil)
        }
    }

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
                if didTrash(Self.url(path)) { placed[path] = same }
                continue
            }
            if destination == locations.userFonts {
                intoFontsFolder[path] = destination.appendingPathComponent((path as NSString).lastPathComponent, isDirectory: false).path
                continue
            }
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
            if let moved = placed[original] { records.installedCopies[copy] = moved == copy ? nil : moved }
        }
        return (records, placed.count)
    }

    var inactiveFolderMovesList: URL { locations.support.appendingPathComponent("moving-inactive.json", isDirectory: false) }

    public var hasFormerInactiveFolders: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: inactiveFolderMovesList.path) || locations.formerInactiveFolders.contains { fm.fileExists(atPath: $0.path) }
    }

    @concurrent
    public func moveFormerInactiveFolders(_ records: ActivationRecords) async -> (records: ActivationRecords, moves: [String: String]) {
        let fm = FileManager.default
        let folder = locations.inactiveFolder
        var moves: [String: String] = [:]
        if let data = try? Data(contentsOf: inactiveFolderMovesList), let listed = try? JSONDecoder().decode([String: String].self, from: data) {
            for (from, to) in listed where Self.exists(to) {
                if Self.exists(from), !(Self.isIdenticalCopy(to, of: from) && (try? fm.removeItem(atPath: from)) != nil) { continue }
                moves[from] = to
            }
        }
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
            if staying.isEmpty, !Self.exists(folder.path) || Self.removeIfEmpty(folder.path),
               (try? fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil {
                let planned = Dictionary(uniqueKeysWithValues: names.map { (former.appendingPathComponent($0).path, folder.appendingPathComponent($0).path) })
                if (try? noteInactiveFolderMoves(moves.merging(planned) { first, _ in first })) != nil,
                   Self.renameExclusively(former.path, to: folder.path) {
                    moves.merge(planned) { first, _ in first }
                    continue
                }
            }
            guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { continue }
            var taken = Set(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).map(Self.nameKey))
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
            for item in items {
                Self.removeEmptyFolders(item.from.path)
                Self.removeEmptyFolders(item.to.path)
            }
            _ = Self.removeIfEmpty(former.path)
        }
        return (Self.records(records, following: moves), moves)
    }

    public func forgetInactiveFolderMoves() {
        try? FileManager.default.removeItem(at: inactiveFolderMovesList)
    }

    private func noteInactiveFolderMoves(_ moves: [String: String]) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(moves).write(to: inactiveFolderMovesList, options: .atomic)
        // On the disk itself before anything moves, so a power cut can't leave the moves without it.
        guard UserDataStore.syncToDisk(inactiveFolderMovesList) else { throw POSIXError(.EIO) }
    }

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

    public static func paths(_ paths: [String], following moves: [String: String]) -> [String] {
        guard !moves.isEmpty else { return paths }
        return paths.map(movedPath(following: moves))
    }

    private static func movedPath(following moves: [String: String]) -> (String) -> String {
        { path in
            var item = path, rest = ""
            while item.count > 1 {
                // A name in another Unicode form finds its move too, as Swift's strings compare equal across forms, like the disk.
                if let to = moves[item] { return to + rest }
                rest = "/" + (item as NSString).lastPathComponent + rest
                item = (item as NSString).deletingLastPathComponent
            }
            return path
        }
    }

    // Letter case ignored, as on the Mac's own disk; Swift's strings already count every Unicode form of a name as one.
    private static func nameKey(_ name: String) -> String { name.lowercased() }

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

    static let movingPrefix = ".cicero-moving-"

    // Some disks (exFAT, FAT, some file servers) can't rename exclusively: there, a plain rename, once nothing is at the destination.
    static func renameExclusively(_ from: String, to: String) -> Bool {
        if renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 { return true }
        let error = errno
        guard error == ENOTSUP || error == EINVAL else { return false }
        guard !exists(to) else {
            errno = EEXIST
            return false
        }
        return rename(from, to) == 0
    }

    static func moveItem(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        // macOS sets a file's Date Added anew when it moves into another folder.
        let added = dateAdded(of: from)
        if !renameExclusively(from.path, to: to.path) {
            let error = errno
            // Never a folder onto another disk: deleting one could stop partway, and taking the copy back out would then lose the files only it has.
            guard error == EXDEV, !isFolder(from.path) else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
            // Under a hidden name until it's whole, so a copy that stops halfway is never taken for a font.
            let copy = to.deletingLastPathComponent().appendingPathComponent(movingPrefix + UUID().uuidString)
            do {
                try fm.copyItem(at: from, to: copy)
                // copyItem gives the copy its original's flags, and a Locked copy could be neither named nor taken back out.
                unlock(copy)
                guard renameExclusively(copy.path, to: to.path) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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

    static func unlock(_ url: URL) {
        let locked = UInt32(UF_IMMUTABLE | UF_APPEND)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_flags & locked != 0 else { return }
        lchflags(url.path, info.st_flags & ~locked)
    }

    static func fileMoves(_ from: URL, to: URL) -> [(from: URL, to: URL)] {
        guard isFolder(from.path) else { return [(from, to)] }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: from.path)) ?? []).filter { $0 != ".DS_Store" }.sorted()
        return names.flatMap { fileMoves(from.appendingPathComponent($0), to: to.appendingPathComponent($0)) }
    }

    static func isFolder(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    static func disk(of path: String) -> dev_t? {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_dev : nil
    }

    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
