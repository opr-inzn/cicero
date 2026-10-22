import CoreText
import Foundation
import Security

/// Registers and unregisters font files with the system. The CoreText implementation is used by the
/// app; tests use a fake so they never change the Mac's fonts.
public protocol FontRegistrar: Sendable {
    /// Returns the paths that failed.
    func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    /// Returns the paths that failed.
    func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    /// Synchronous unregistering, for when the app is about to quit.
    func unregisterNow(_ urls: [URL], scope: CTFontManagerScope)
    /// Every font file the system has active.
    func activeFontURLs() -> [URL]
    /// Whether the system has the file active, in any scope. Also true for files `activeFontURLs` leaves
    /// out because their fonts have hidden names (starting with a dot).
    func isActive(_ url: URL) -> Bool
}

public struct CoreTextRegistrar: FontRegistrar {
    public init() {}

    /// Returns once fontd has registered the files and told every app, so they're usable the moment this
    /// returns. Files turned off in macOS stay off when registered again, so those are turned back on.
    public func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let result = await Self.perform(urls, ignoring: .alreadyRegistered, undone: { !Self.isActive($0) }) { handler in
            CTFontManagerRegisterFontURLs(urls as CFArray, scope, true, handler)
        }
        if result.timedOut, !result.failed.isEmpty {
            // fontd may still turn on the files it hadn't by then; taken back, they stay off, as the caller is told.
            // Without waiting, as fontd may not be answering.
            let late = urls.filter { result.failed.contains($0.path(percentEncoded: false)) }
            DispatchQueue.global(qos: .utility).async {
                CTFontManagerUnregisterFontURLs(late as CFArray, scope) { _, _ in true }
            }
        }
        let ignored = Self.given(result.ignored, among: urls)
        let disabled = urls.filter { ignored.contains($0.path(percentEncoded: false)) && !isActive($0) }
        if !disabled.isEmpty {
            let descriptors = disabled.flatMap { CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor] ?? [] }
            CTFontManagerEnableFontDescriptors(descriptors as CFArray, true)
        }
        return Self.given(result.failed, among: urls)
    }

    public func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let failed = await Self.perform(urls, ignoring: .notRegistered, undone: { Self.isActive($0) }) { handler in
            CTFontManagerUnregisterFontURLs(urls as CFArray, scope, handler)
        }.failed
        return Self.given(failed, among: urls)
    }

    public func unregisterNow(_ urls: [URL], scope: CTFontManagerScope) {
        guard !urls.isEmpty else { return }
        let finished = DispatchSemaphore(value: 0)
        CTFontManagerUnregisterFontURLs(urls as CFArray, scope) { _, done in
            if done { finished.signal() }
            return true
        }
        _ = finished.wait(timeout: .now() + 3)
    }

    public func activeFontURLs() -> [URL] {
        CTFontManagerCopyAvailableFontURLs() as? [URL] ?? []
    }

    /// CoreText knows a file registered through a symlink (a folder linked into the home folder, say) by its path with
    /// the symlink resolved only, so that's asked about too.
    public func isActive(_ url: URL) -> Bool {
        Self.isActive(url)
    }

    private static func isActive(_ url: URL) -> Bool {
        if CTFontManagerGetScopeForURL(url as CFURL) != .none { return true }
        return LibraryScanner.linkedPaths(url.path(percentEncoded: false)).contains { path in
            CTFontManagerGetScopeForURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL) != .none
        }
    }

    /// The files CoreText's errors name, by their paths as given: it names a file by its path with every symlink resolved.
    private static func given(_ named: Set<String>, among urls: [URL]) -> Set<String> {
        guard !named.isEmpty else { return named }
        return Set(urls.map { $0.path(percentEncoded: false) }.filter { path in
            named.contains(path) || !LibraryScanner.linkedPaths(path).isDisjoint(with: named)
        })
    }

    /// Runs a CoreText registration call and waits for its last callback. fontd can hang, and an
    /// operation that never finishes would hold up every one after it, so after a while (fontd takes a few
    /// milliseconds a file) the files that are still `undone` count as failed.
    private static func perform(
        _ urls: [URL], ignoring ignored: CTFontManagerError, undone: @escaping @Sendable (URL) -> Bool,
        _ start: (@escaping (CFArray, Bool) -> Bool) -> Void
    ) async -> FailureCollector.Result {
        await withCheckedContinuation { continuation in
            let collector = FailureCollector(ignoring: ignored, continuation: continuation)
            start { errors, done in
                collector.add(errors as! [CFError])
                if done { collector.finish() }
                return true
            }
            let timeout = 15 + 0.05 * Double(urls.count)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard collector.isWaiting else { return }
                // Asking about each file takes fontd too, which may not answer either: then, a while later, every
                // file counts as failed.
                let all = Set(urls.map { $0.path(percentEncoded: false) })
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { collector.finish(failing: all, timedOut: true) }
                collector.finish(failing: Set(urls.filter(undone).map { $0.path(percentEncoded: false) }), timedOut: true)
            }
        }
    }

    /// Gathers the files named by CoreText's errors (the handler can run more than once) and resumes
    /// the caller once, when CoreText is done or the wait times out.
    private final class FailureCollector: @unchecked Sendable {
        typealias Result = (failed: Set<String>, ignored: Set<String>, timedOut: Bool)

        private let lock = NSLock()
        private let ignoredCode: CTFontManagerError
        private var continuation: CheckedContinuation<Result, Never>?
        private var failed = Set<String>()
        private var ignored = Set<String>()

        init(ignoring: CTFontManagerError, continuation: CheckedContinuation<Result, Never>) {
            ignoredCode = ignoring
            self.continuation = continuation
        }

        /// Whether the caller hasn't been resumed yet.
        var isWaiting: Bool {
            lock.withLock { continuation != nil }
        }

        func add(_ errors: [CFError]) {
            lock.withLock {
                for error in errors {
                    let info = CFErrorCopyUserInfo(error) as? [String: Any]
                    let paths = (info?[kCTFontManagerErrorFontURLsKey as String] as? [URL] ?? []).map { $0.path(percentEncoded: false) }
                    if CFErrorGetCode(error) == ignoredCode.rawValue {
                        ignored.formUnion(paths)
                    } else {
                        failed.formUnion(paths)
                    }
                }
            }
        }

        func finish(failing extra: Set<String> = [], timedOut: Bool = false) {
            let resume = lock.withLock { () -> (CheckedContinuation<Result, Never>, Result)? in
                guard let continuation else { return nil }
                self.continuation = nil
                return (continuation, (failed.union(extra), ignored, timedOut))
            }
            guard let (continuation, result) = resume else { return }
            continuation.resume(returning: result)
        }
    }
}

/// What an activation, deactivation or trash did.
public struct ActivationResult: Sendable {
    /// Records after the operation; the caller stores them.
    public var records: ActivationRecords
    public var succeeded: Int
    /// Paths that couldn't be handled.
    public var failed: [String]
    /// A short toast, without a full stop at the end, e.g. "Activated" or "Couldn’t activate 2 of 5 files"
    public var message: String

    public init(records: ActivationRecords, succeeded: Int, failed: [String], message: String) {
        self.records = records
        self.succeeded = succeeded
        self.failed = failed
        self.message = message
    }
}

/// Files to move to the Trash, worked out before asking for confirmation.
public struct TrashPlan: Sendable, Identifiable {
    public let id = UUID()
    /// e.g. "“Inter”" or "3 families".
    public var title: String
    public var paths: [String]
    /// Families that are not part of the request but have styles in those files (collections).
    public var otherFamilies: [String]
    /// Files that were left out because Cicero never touches them (macOS, apps, Adobe Fonts…).
    public var protectedCount: Int
    /// Families removed entirely, to drop from sets, tags and foundry overrides.
    public var removedFamilies: [String]
    /// The paths are every copy of some fonts, wherever they are; false for files picked one by one.
    public var includesCopies: Bool
    /// For files Problems offers to remove: this library's fonts must each keep a copy in another file
    /// (the `otherFamilies` too), checked again right before trashing, since a copy may have gone since.
    public var spareCopiesOf: Library?

    public init(title: String, paths: [String], otherFamilies: [String], protectedCount: Int, removedFamilies: [String],
                includesCopies: Bool = true, spareCopiesOf: Library? = nil) {
        self.title = title
        self.paths = paths
        self.otherFamilies = otherFamilies
        self.protectedCount = protectedCount
        self.removedFamilies = removedFamilies
        self.includesCopies = includesCopies
        self.spareCopiesOf = spareCopiesOf
    }
}

/// Turns fonts on and off. Never deletes a user's only copy: a copy Cicero installed goes to the Trash
/// only when the file it was copied from is still there with the same contents, in the library; every
/// other file in ~/Library/Fonts moves to Cicero's Deactivated folder.
public struct ActivationEngine: Sendable {
    let locations: Locations
    let registrar: any FontRegistrar
    /// Moves a file to the Trash. Tests replace it so they don't fill the user's Trash.
    public var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    /// Moves files `trash` wasn't allowed to move, after macOS asks for an administrator's password, and returns
    /// the paths that went. Tests replace it so no password is asked for.
    public var trashAsAdministrator: @Sendable ([URL]) async -> Set<String> = { await AdministratorTrash.move($0) }
    /// Cicero's Font Library (see `UserData.fontLibraryPath`). Fonts in it are always used where they are, and turning
    /// one off leaves it there.
    public var fontLibrary: URL?
    /// Fonts Cicero installs go into `fontLibrary`, a folder for each family, and are registered there, rather than copied
    /// into ~/Library/Fonts.
    public var installsIntoFontLibrary = false

    public init(locations: Locations, registrar: any FontRegistrar = CoreTextRegistrar()) {
        self.locations = locations
        self.registrar = registrar
    }

    /// Copies into ~/Library/Fonts, or into the family's folder in the Font Library (see `installsIntoFontLibrary`), or
    /// registers in place (`method` is `.copy`, `.move` or `.inPlace`). With `.move`, files in `movable` (ones the user
    /// added one at a time) are moved there instead (see `removeOriginals`), and the rest copied. Files from Cicero's
    /// Deactivated folder, which only keeps fonts while they're off, are always moved, whatever `method` is. Faces from
    /// app-only folders and from the Font Library are always registered in place, the former after going back into
    /// the folder if Cicero moved them out; faces in a Fonts folder that macOS has off are turned on there.
    /// Temporarily active faces are made permanent.
    ///
    /// Copies are registered too: left alone, they reach apps only when macOS notices the file, seconds
    /// later. A file counts as activated once macOS reports it active, so it's usable in every app as
    /// soon as this returns.
    @concurrent
    public func activate(_ faces: [LibraryFace], method: InstallMethod, records: ActivationRecords, movable: Set<String> = []) async -> ActivationResult {
        let signpost = Signposts.activation.beginInterval("Activate", "\(faces.count) faces")
        defer { Signposts.activation.endInterval("Activate", signpost) }
        var records = records
        var failed: [String] = []
        // Files to copy, and the family each is copied for (see `placeCopy`).
        var toCopy: [(path: String, family: String)] = []
        // Files to register where they are; `record` for those Cicero must remember to unregister.
        var toRegister: [(path: String, record: Bool)] = []
        let targets = Self.uniqueByPath(faces).filter(\.canActivate)
        // A session registration of the same file would shadow the permanent one.
        let temporary = targets.map(\.face.path).filter { records.temporary[$0] != nil }
        if !temporary.isEmpty {
            let stuck = await registrar.unregister(temporary.map(Self.url), scope: .session)
            for path in temporary where !stuck.contains(path) { records.temporary[path] = nil }
        }
        for face in targets {
            let path = face.face.path
            if records.appFolderOrigins[path] != nil {
                do {
                    toRegister.append((try moveBackToAppFolder(path, records: &records), true))
                } catch {
                    failed.append(path)
                }
            } else if isInsideFontsFolder(path) {
                toRegister.append((path, false))
            } else if face.app != nil || method == .inPlace && !isInDeactivatedFolder(path) || isInFontLibrary(path) {
                toRegister.append((path, true))
            } else {
                toCopy.append((path, face.face.familyName))
            }
        }
        var copies: [PlacedCopy] = []
        Signposts.activation.withIntervalSignpost("Copy", "\(toCopy.count) files") {
            for (path, family) in toCopy {
                do {
                    copies.append(try placeCopy(of: path, family: family))
                } catch {
                    failed.append(path)
                }
            }
        }
        let stuck = await registerAndConfirm(toRegister.map(\.path) + copies.map(\.destination), scope: .persistent)
        var succeeded = 0
        for (path, record) in toRegister {
            if stuck.contains(path) {
                failed.append(path)
            } else {
                if record { records.inPlace.insert(path) }
                succeeded += 1
            }
        }
        let installed = keep(copies, stuck: stuck, records: &records, failed: &failed)
        succeeded += installed.count
        let done = Set(targets.map(\.face.path)).subtracting(failed)
        let message = Self.message("Activated", "activate", succeeded: succeeded, failed: failed.count,
                                   done: Self.names(of: faces, in: done), undone: Self.names(of: faces, in: Set(failed)))
        let removed = removeOriginals(of: installed.filter { copy in
            method == .move && movable.contains(copy.source)
                || isInDeactivatedFolder(copy.source)
                    && !records.installedCopies.contains { $0.key != copy.destination && $0.value == copy.source }
        })
        // Back in ~/Library/Fonts, a file from the Deactivated folder is the user's own again, no copy of anything.
        for copy in removed where isInDeactivatedFolder(copy.source) && !isInFontLibrary(copy.destination) {
            records.installedCopies[copy.destination] = nil
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Copies font files into ~/Library/Fonts and turns them on, as opening files the library doesn't have does when
    /// fonts are activated by copying. The originals stay where they are, out of the library, so deactivating a copy
    /// moves it to the Deactivated folder rather than to the Trash (see `moveOutOfFontsFolder`). `moving`, as when
    /// fonts are activated by moving, they go (see `removeOriginals`).
    @concurrent
    public func install(_ paths: [String], moving: Bool = false, records: ActivationRecords) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var copies: [PlacedCopy] = []
        for path in Set(paths).sorted() {
            do {
                copies.append(try placeCopy(of: path, family: nil))
            } catch {
                failed.append(path)
            }
        }
        let stuck = await registerAndConfirm(copies.map(\.destination), scope: .persistent)
        let installed = keep(copies, stuck: stuck, records: &records, failed: &failed)
        if moving { removeOriginals(of: installed) }
        // Read from the copies: moving, the originals are gone.
        let message = Self.message("Installed", "install", succeeded: installed.count, failed: failed.count,
                                   done: FontNames.describe(FontNames.fonts(inFiles: installed.map(\.destination))),
                                   undone: FontNames.describe(FontNames.fonts(inFiles: failed)))
        return ActivationResult(records: records, succeeded: installed.count, failed: failed, message: message)
    }

    /// Remembers what each copy macOS turned on was copied from, and takes out the ones it didn't: a copy macOS
    /// won't use only clutters the Fonts folder. Returns the ones it kept.
    private func keep(_ copies: [PlacedCopy], stuck: Set<String>, records: inout ActivationRecords, failed: inout [String]) -> [PlacedCopy] {
        var kept: [PlacedCopy] = []
        for copy in copies {
            if stuck.contains(copy.destination) {
                failed.append(copy.source)
                if copy.isNew {
                    try? FileManager.default.removeItem(atPath: copy.destination)
                    removeEmptyFolders(around: copy.destination)
                }
            } else {
                records.installedCopies[copy.destination] = copy.source
                if isInFontLibrary(copy.destination) { records.inPlace.insert(copy.destination) }
                kept.append(copy)
            }
        }
        return kept
    }

    /// Finishes moving files whose copies are on: deletes each original whose copy has the same contents. The folders
    /// they were in stay, whatever is left in them. An original that can't go, on a disk that's read only say, stays, as
    /// a copy's would. Returns the copies whose originals went.
    @discardableResult
    private func removeOriginals(of copies: [PlacedCopy]) -> [PlacedCopy] {
        copies.filter { copy in
            !Self.isProtected(copy.source) && Self.isIdenticalCopy(copy.destination, of: copy.source)
                && (try? FileManager.default.removeItem(atPath: copy.source)) != nil
        }
    }

    /// Registers for the session until Cicero quits. Faces already on for an application set stay on
    /// until then too.
    @concurrent
    public func activateTemporarily(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var succeeded = 0
        var done = Set<String>()
        var toRegister: [String] = []
        let session = Self.currentSession()
        // Never one of Creative Cloud's: one only Adobe apps load would be on in every app.
        for face in Self.uniqueByPath(faces) where !face.isAdobeFonts {
            let path = face.face.path
            if records.temporary[path] != nil {
                records.temporary[path] = TemporaryRecord(scope: .untilQuit, session: session)
                done.insert(path)
                succeeded += 1
            } else if !face.state.isActive {
                toRegister.append(path)
            }
        }
        let stuck = await registerAndConfirm(toRegister, scope: .session)
        for path in toRegister {
            if stuck.contains(path) {
                failed.append(path)
            } else {
                records.temporary[path] = TemporaryRecord(scope: .untilQuit, session: session)
                done.insert(path)
                succeeded += 1
            }
        }
        let message: String
        if failed.isEmpty, let name = Self.names(of: faces, in: done) {
            message = "\(name) activated until Cicero quits"
        } else if failed.isEmpty {
            message = succeeded <= 1 ? "Activated until Cicero quits" : "Activated \(succeeded) files until Cicero quits"
        } else {
            message = Self.message("Activated", "activate", succeeded: succeeded, failed: failed.count,
                                   undone: Self.names(of: faces, in: Set(failed)))
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Moves styles to other copies of them (see `CopyChooser.plan`): the old copies go off first, so the
    /// new ones don't land beside them as "Name 2.otf", then the new ones go on. A style whose new copy
    /// doesn't go on gets its old copies back rather than none; any that can't come back are among `failed`.
    /// With `.move`, new copies in `movable` are moved into the Fonts folder (see `activate`).
    @concurrent
    public func switchCopies(_ switches: [CopySwitch], method: InstallMethod, records: ActivationRecords, movable: Set<String> = []) async -> ActivationResult {
        let origins = records.installedCopies
        var moved: [String: String] = [:]
        let off = await deactivate(switches.flatMap(\.others), records: records, moved: &moved)
        let on = await activate(switches.compactMap(\.target), method: method, records: off.records, movable: movable)
        var result = ActivationResult(records: on.records, succeeded: on.succeeded, failed: off.failed + on.failed, message: "Switched")
        let stuck = Set(on.failed)
        let restoring = switches.filter { $0.target.map { stuck.contains($0.face.path) } ?? false }
            .flatMap(\.others).filter { !off.failed.contains($0.face.path) }
        if !restoring.isEmpty {
            let restored = await restore(restoring, origins: origins, moved: moved, records: result.records)
            result.records = restored.records
            result.failed += restored.failed
        }
        if !result.failed.isEmpty {
            result.message = Self.message("Switched", "switch", succeeded: result.succeeded, failed: Set(result.failed).count)
        }
        return result
    }

    /// Turns copies back on as they were: in place, until Cicero quits, or back into ~/Library/Fonts from the
    /// Deactivated folder, or (when it went to the Trash, being the same as its original) installed again from
    /// its original.
    private func restore(_ faces: [LibraryFace], origins: [String: String], moved: [String: String], records: ActivationRecords) async -> ActivationResult {
        var inPlace: [LibraryFace] = [], temporary: [LibraryFace] = [], copies: [LibraryFace] = []
        var failed: [String] = []
        for face in faces {
            let path = face.face.path
            switch face.state.source {
            case .inPlace: inPlace.append(LibraryFace(face: face.face, state: .inactive))
            case .temporary: temporary.append(LibraryFace(face: face.face, state: .inactive))
            case .fontsFolder:
                if let source = moved[path] ?? origins[path], FileManager.default.fileExists(atPath: source) {
                    copies.append(LibraryFace(face: face.face.at(source), state: .inactive))
                } else {
                    failed.append(path)
                }
            default: failed.append(path)
            }
        }
        var records = records
        for (faces, method) in [(inPlace, InstallMethod.inPlace), (copies, .copy)] where !faces.isEmpty {
            let result = await activate(faces, method: method, records: records)
            records = result.records
            failed += result.failed
        }
        if !temporary.isEmpty {
            let result = await activateTemporarily(temporary, records: records)
            records = result.records
            failed += result.failed
        }
        return ActivationResult(records: records, succeeded: 0, failed: failed, message: "")
    }

    /// Faces an app loads from its own folder also leave that folder for Cicero's Deactivated folder,
    /// so they're off in the app too. Files in ~/Library/Fonts are unregistered before they move, so
    /// apps drop them at once rather than when macOS notices they're gone, seconds later.
    @concurrent
    public func deactivate(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var moved: [String: String] = [:]
        return await deactivate(faces, records: records, moved: &moved)
    }

    /// `moved` gets where files that left the Fonts folder for the Deactivated folder went.
    private func deactivate(_ faces: [LibraryFace], records: ActivationRecords, moved: inout [String: String]) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var locked: [String] = []
        var succeeded = 0
        var installed: [LibraryFace] = []
        var persistent: [String] = []
        var session: [String] = []
        var leaving: [String] = []
        // The library's other files with the same fonts as each file, among which an installed copy's original must be.
        var listed: [String: Set<String>] = [:]
        for face in faces { listed[face.face.path, default: []].formUnion(face.otherCopies) }
        for face in Self.uniqueByPath(faces) {
            let path = face.face.path
            // Creative Cloud's files never move, also those only Adobe apps load.
            if face.isAdobeFonts {
                locked.append(path)
                continue
            }
            if face.app != nil, records.appFolderOrigins[path] == nil {
                leaving.append(path)
                switch face.state.source {
                case .inPlace, .otherApp: persistent.append(path)
                case .temporary: session.append(path)
                default: break
                }
                continue
            }
            switch face.state.source {
            case nil:
                continue
            case .fontsFolder:
                installed.append(face)
            case .inPlace, .otherApp:
                persistent.append(path)
            case .temporary:
                session.append(path)
            case .macOS, .allUsers, .app, .adobeFonts:
                locked.append(path)
            }
        }
        if !installed.isEmpty {
            _ = await registrar.unregister(installed.map { Self.url($0.face.path) }, scope: .persistent)
            var kept: [String] = []
            for face in installed {
                do {
                    moved[face.face.path] = try moveOutOfFontsFolder(face.face.path, listed: listed[face.face.path] ?? [], records: records)
                    records.installedCopies[face.face.path] = nil
                    removeEmptyFolders(around: face.face.path)
                    succeeded += 1
                } catch {
                    failed.append(face.face.path)
                    kept.append(face.face.path)
                }
            }
            // Still in the Fonts folder, so back on, as macOS would soon make it anyway.
            if !kept.isEmpty { _ = await registrar.register(kept.map(Self.url), scope: .persistent) }
        }
        if !persistent.isEmpty {
            var stuck = await registrar.unregister(persistent.map(Self.url), scope: .persistent)
            if !stuck.isEmpty {
                stuck = await registrar.unregister(stuck.sorted().map(Self.url), scope: .session)
            }
            for path in persistent {
                if stuck.contains(path) {
                    failed.append(path)
                } else {
                    records.inPlace.remove(path)
                    if !leaving.contains(path) { succeeded += 1 }
                }
            }
        }
        if !session.isEmpty {
            let stuck = await registrar.unregister(session.map(Self.url), scope: .session)
            for path in session {
                if stuck.contains(path) {
                    failed.append(path)
                } else {
                    records.temporary[path] = nil
                    if !leaving.contains(path) { succeeded += 1 }
                }
            }
        }
        for path in leaving where !failed.contains(path) {
            do {
                try moveOutOfAppFolder(path, records: &records)
                succeeded += 1
            } catch {
                failed.append(path)
            }
        }
        let done = Set(installed.map(\.face.path) + persistent + session + leaving).subtracting(failed)
        let message = failed.isEmpty && succeeded == 0 && !locked.isEmpty
            ? "These fonts are managed by macOS or another app"
            : Self.message("Deactivated", "deactivate", succeeded: succeeded, failed: failed.count + locked.count,
                           done: Self.names(of: faces, in: done), undone: Self.names(of: faces, in: Set(failed + locked)))
        return ActivationResult(records: records, succeeded: succeeded, failed: failed + locked, message: message)
    }

    /// Faces an app loads from its own folder go back to being on in that app only: files Cicero moved
    /// out of the folder go back, files it registered there are unregistered.
    @concurrent
    public func useInAppOnly(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var persistent: [String] = []
        var session: [String] = []
        var returning: [String] = []
        for face in Self.uniqueByPath(faces) where face.app != nil {
            let path = face.face.path
            if records.appFolderOrigins[path] != nil { returning.append(path) }
            switch face.state.source {
            case .inPlace, .otherApp: persistent.append(path)
            case .temporary: session.append(path)
            default: break
            }
        }
        if !persistent.isEmpty {
            var stuck = await registrar.unregister(persistent.map(Self.url), scope: .persistent)
            if !stuck.isEmpty {
                stuck = await registrar.unregister(stuck.sorted().map(Self.url), scope: .session)
            }
            for path in persistent where !stuck.contains(path) { records.inPlace.remove(path) }
            failed += persistent.filter(stuck.contains)
        }
        if !session.isEmpty {
            let stuck = await registrar.unregister(session.map(Self.url), scope: .session)
            for path in session where !stuck.contains(path) { records.temporary[path] = nil }
            failed += session.filter(stuck.contains)
        }
        for path in returning where !failed.contains(path) {
            do {
                _ = try moveBackToAppFolder(path, records: &records)
            } catch {
                failed.append(path)
            }
        }
        let succeeded = Set(persistent + session + returning).subtracting(failed).count
        let app = faces.lazy.compactMap(\.app).first.map(FaceState.appDescription) ?? "the app"
        let message = failed.isEmpty
            ? "On in \(app) only"
            : Self.message("Done", "move", succeeded: succeeded, failed: failed.count)
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// nil when every file is protected (the app then says so).
    public func trashPlan(for faces: [LibraryFace], removing families: [String], in library: Library, title: String) -> TrashPlan? {
        var paths: [String] = []
        var protectedCount = 0
        for path in faces.flatMap({ [$0.face.path] + $0.otherCopies }) where !paths.contains(path) {
            if Self.isProtected(path) {
                protectedCount += 1
            } else {
                paths.append(path)
            }
        }
        guard !paths.isEmpty else { return nil }
        let set = Set(paths)
        let removing = Set(families)
        let otherFamilies = library.families
            .filter { !removing.contains($0.id) && $0.faces.contains { set.contains($0.face.path) } }
            .map(\.id)
        let removed = families.filter { name in
            library.family(name).map { $0.faces.allSatisfy { set.contains($0.face.path) } } ?? false
        }
        return TrashPlan(title: title, paths: paths, otherFamilies: otherFamilies, protectedCount: protectedCount, removedFamilies: removed)
    }

    /// For a fix in Problems: files that are spare copies (or that nothing can read), picked one by one.
    /// Names the families besides `families` (the problems') with faces in them, which keep their other copies;
    /// `moveToTrash` checks the files are still spare right before it trashes them. nil when every file is protected.
    public func spareCopiesTrashPlan(_ paths: [String], families: Set<String>, in library: Library) -> TrashPlan? {
        let allowed = paths.filter { !Self.isProtected($0) }
        guard !allowed.isEmpty else { return nil }
        let set = Set(allowed)
        let otherFamilies = library.families
            .filter { !families.contains($0.id) && $0.faces.contains { set.contains($0.face.path) || $0.otherCopies.contains(where: set.contains) } }
            .map(\.id)
        return TrashPlan(
            title: allowed.count == 1 ? "“\((allowed[0] as NSString).lastPathComponent)”" : "\(allowed.count) files",
            paths: allowed, otherFamilies: otherFamilies, protectedCount: paths.count - allowed.count, removedFamilies: [],
            includesCopies: false, spareCopiesOf: library
        )
    }

    /// Files in use are unregistered first, so apps drop them at once.
    @concurrent
    public func moveToTrash(_ plan: TrashPlan, records: ActivationRecords) async -> ActivationResult {
        var records = records
        if let library = plan.spareCopiesOf {
            var copies = SpareCopies(library)
            guard copies.areSpare(Set(plan.paths)) else {
                let message = plan.paths.count == 1 ? "Kept the file: it holds the only copy of a font" : "Kept the files: some hold the only copy of a font"
                return ActivationResult(records: records, succeeded: 0, failed: plan.paths, message: message)
            }
        }
        var failed: [String] = []
        var succeeded = 0
        let persistent = plan.paths.filter { records.inPlace.contains($0) || isInsideUserFonts($0) }
        if !persistent.isEmpty {
            _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent)
        }
        let session = plan.paths.filter { records.temporary[$0] != nil }
        if !session.isEmpty {
            _ = await registrar.unregister(session.map(Self.url), scope: .session)
        }
        func trashed(_ path: String) {
            records.installedCopies[path] = nil
            records.inPlace.remove(path)
            records.temporary[path] = nil
            records.appFolderOrigins[path] = nil
            removeEmptyFolders(around: path)
            succeeded += 1
        }
        var forbidden: [String] = []
        for path in plan.paths {
            do {
                try trash(Self.url(path))
                trashed(path)
            } catch CocoaError.fileWriteNoPermission where !Self.isLocked(path) {
                forbidden.append(path)
            } catch {
                failed.append(path)
            }
        }
        // Files in a folder the user may not change, like the Fonts folder next to InDesign, go once macOS has
        // asked for an administrator's password, as in the Finder.
        if !forbidden.isEmpty {
            let moved = await trashAsAdministrator(forbidden.map(Self.url))
            for path in forbidden {
                if moved.contains(path) { trashed(path) } else { failed.append(path) }
            }
        }
        // Files that stayed where they were stay in use.
        let kept = persistent.filter(failed.contains)
        if !kept.isEmpty { _ = await registrar.register(kept.map(Self.url), scope: .persistent) }
        let message: String
        if failed.isEmpty {
            message = succeeded <= 1 ? "Moved to the Trash" : "Moved \(succeeded) files to the Trash"
        } else if succeeded == 0 {
            message = failed.count == 1 ? "Couldn’t move the file to the Trash" : "Couldn’t move \(failed.count) files to the Trash"
        } else {
            message = "Couldn’t move \(failed.count) of \(succeeded + failed.count) files to the Trash"
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Stops using a file registered in place (e.g. one whose file is gone) and forgets it.
    @concurrent
    public func forgetInPlace(_ path: String, records: ActivationRecords) async -> ActivationRecords {
        var records = records
        _ = await registrar.unregister([Self.url(path)], scope: .persistent)
        records.inPlace.remove(path)
        return records
    }

    /// Copies a font used in place into ~/Library/Fonts (or the Font Library), then stops using the original in place.
    /// One in the Font Library is installed already.
    @concurrent
    public func installCopy(of face: LibraryFace, records: ActivationRecords) async -> ActivationResult {
        var records = records
        let path = face.face.path
        let name = FontNames.describe([face])
        guard !isInFontLibrary(path) else { return ActivationResult(records: records, succeeded: 0, failed: [], message: "\(name ?? "The font") is in your Font Library") }
        let place = installsIntoFontLibrary && fontLibrary != nil ? "your Font Library" : "your Fonts folder"
        let failure = ActivationResult(records: records, succeeded: 0, failed: [path], message: "Couldn’t copy \(name ?? "the font") into \(place)")
        guard let copy = try? placeCopy(of: path, family: face.face.familyName) else { return failure }
        guard await registerAndConfirm([copy.destination], scope: .persistent).isEmpty else {
            if copy.isNew {
                try? FileManager.default.removeItem(atPath: copy.destination)
                removeEmptyFolders(around: copy.destination)
            }
            return failure
        }
        records.installedCopies[copy.destination] = path
        if isInFontLibrary(copy.destination) { records.inPlace.insert(copy.destination) }
        if records.inPlace.contains(path) {
            _ = await registrar.unregister([Self.url(path)], scope: .persistent)
            records.inPlace.remove(path)
        }
        return ActivationResult(records: records, succeeded: 1, failed: [], message: name.map { "\($0) installed" } ?? "Installed a copy")
    }

    /// At launch: unregisters "until Cicero quits" activations left behind by a crash, and forgets
    /// application sets' ones from an earlier login session, which ended with it.
    @concurrent
    public func reconcileTemporary(_ records: ActivationRecords) async -> ActivationRecords {
        var records = records
        let session = Self.currentSession()
        var leftovers: [String] = []
        for (path, record) in records.temporary {
            switch record.scope {
            case .untilQuit: leftovers.append(path)
            case .whileAppsRun: if record.session != session { records.temporary[path] = nil }
            }
        }
        if !leftovers.isEmpty {
            _ = await registrar.unregister(leftovers.map(Self.url), scope: .session)
            for path in leftovers { records.temporary[path] = nil }
        }
        return records
    }

    /// At launch: turning a font on used to leave its file in the Deactivated folder, as the original of the copy that
    /// went into ~/Library/Fonts or the Font Library. The copy is the font now, so the file goes, once the copy has the
    /// same contents and it's the original of no other copy, as `activate` does it now; in ~/Library/Fonts, the copy
    /// is the user's own again. Returns how many files went.
    @concurrent
    public func tidyDeactivatedFolder(_ records: ActivationRecords) async -> (records: ActivationRecords, removed: Int) {
        var records = records
        var removed = 0
        let copiesOf = Dictionary(grouping: records.installedCopies.values, by: { $0 }).mapValues(\.count)
        for (copy, original) in records.installedCopies where isInDeactivatedFolder(original) && copiesOf[original] == 1 {
            guard isInsideUserFonts(copy) || isInFontLibrary(copy), Self.isIdenticalCopy(copy, of: original),
                  (try? FileManager.default.removeItem(atPath: original)) != nil
            else { continue }
            if !isInFontLibrary(copy) { records.installedCopies[copy] = nil }
            removed += 1
        }
        return (records, removed)
    }

    /// At quit: unregisters "until Cicero quits" activations synchronously.
    public func endUntilQuit(_ records: ActivationRecords) -> ActivationRecords {
        var records = records
        let paths = records.temporary.filter { $0.value.scope == .untilQuit }.map(\.key)
        guard !paths.isEmpty else { return records }
        registrar.unregisterNow(paths.map(Self.url), scope: .session)
        for path in paths { records.temporary[path] = nil }
        return records
    }

    /// Identifies the current login session (audit session ID plus boot time). Application sets'
    /// registrations outlive Cicero but not a logout, so their records only count within one.
    public static func currentSession() -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var name = [CTL_KERN, KERN_BOOTTIME]
        _ = sysctl(&name, 2, &boot, &size, nil, 0)
        var sessionID: SecuritySessionId = 0
        var attributes: SessionAttributeBits = []
        _ = SessionGetInfo(callerSecuritySession, &sessionID, &attributes)
        return "\(boot.tv_sec)-\(sessionID)"
    }

    /// Paths Cicero never moves, trashes or modifies.
    public static func isProtected(_ path: String) -> Bool {
        ["/System/", "/Library/Application Support/Apple/", "/usr/", "/private/"].contains(where: path.hasPrefix)
            || path.contains(".app/") || ActiveSource.isAdobeFonts(path)
    }

    // MARK: Files

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: false)
    }

    /// Locked in the Finder's Get Info: not even an administrator can move it then.
    private static func isLocked(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.immutable] as? Bool) == true
    }

    private static func uniqueByPath(_ faces: [LibraryFace]) -> [LibraryFace] {
        var seen = Set<String>()
        return faces.filter { seen.insert($0.face.path).inserted }
    }

    private func isInsideUserFonts(_ path: String) -> Bool {
        path.hasPrefix(locations.userFonts.path + "/")
    }

    /// ~/Library/Fonts or /Library/Fonts, where a file is active unless it's turned off in macOS.
    private func isInsideFontsFolder(_ path: String) -> Bool {
        isInsideUserFonts(path) || path.hasPrefix(locations.allUsersFonts.path + "/")
    }

    /// Registers files and returns the ones that aren't active afterwards: those CoreText rejects and
    /// any it accepts but doesn't turn on.
    func registerAndConfirm(_ paths: [String], scope: CTFontManagerScope) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let signpost = Signposts.activation.beginInterval("Register", "\(paths.count) files")
        var stuck = await registrar.register(paths.map(Self.url), scope: scope)
        Signposts.activation.endInterval("Register", signpost)
        Signposts.activation.withIntervalSignpost("Confirm") {
            for path in paths where !stuck.contains(path) && !registrar.isActive(Self.url(path)) {
                stuck.insert(path)
            }
        }
        return stuck
    }

    private struct PlacedCopy {
        var destination: String
        var source: String
        /// False when an identical file was there already.
        var isNew: Bool
    }

    /// Puts a copy of a file into ~/Library/Fonts, or into the folder of `family` in the Font Library (see `installFolder`). It's
    /// copied into Cicero's staging folder first (a clone, on the same disk) and then moved in, so macOS never sees a
    /// half-written file. A file of the same name with the same contents is already installed; another file of that
    /// name gets "Name 2.otf".
    private func placeCopy(of path: String, family: String?) throws -> PlacedCopy {
        let fm = FileManager.default
        let source = Self.url(path)
        let folder = installFolder(for: path, family: family)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let first = folder.appendingPathComponent(name, isDirectory: false)
        if fm.fileExists(atPath: first.path), Self.size(of: first) == Self.size(of: source), fm.contentsEqual(atPath: first.path, andPath: path) {
            return PlacedCopy(destination: first.path, source: path, isNew: false)
        }
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: false)
        let destination = Self.uniqueURL(for: name, in: folder)
        do {
            try fm.copyItem(at: source, to: staged)
            try fm.moveItem(at: staged, to: destination)
        } catch {
            try? fm.removeItem(at: staged)
            removeEmptyFolders(around: destination.path)
            throw error
        }
        // A font back from the Deactivated folder, which it only left the Fonts folder for, arrives no more than then.
        if isInDeactivatedFolder(path), let added = Self.dateAdded(of: source) { Self.setDateAdded(added, of: destination) }
        return PlacedCopy(destination: destination.path, source: path, isNew: true)
    }

    /// Moves a file out of an app's folder into Cicero's Deactivated folder, so the app stops loading it,
    /// and remembers where it was.
    private func moveOutOfAppFolder(_ path: String, records: inout ActivationRecords) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: locations.deactivated, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: locations.deactivated)
        try Self.move(Self.url(path), to: destination)
        records.appFolderOrigins[destination.path] = path
    }

    /// Puts a file back where it was in an app's folder (beside a newer file of the same name, if there
    /// is one) and returns its path there. Fails when the folder is gone.
    private func moveBackToAppFolder(_ path: String, records: inout ActivationRecords) throws -> String {
        guard let origin = records.appFolderOrigins[path] else { return path }
        let original = Self.url(origin)
        let destination = FileManager.default.fileExists(atPath: origin)
            ? Self.uniqueURL(for: original.lastPathComponent, in: original.deletingLastPathComponent())
            : original
        try Self.move(Self.url(path), to: destination)
        records.appFolderOrigins[path] = nil
        return destination.path
    }

    /// Trashes a copy Cicero installed when the file it was copied from is still there, unchanged, and in the
    /// library (among `listed`, the library's other files with the same fonts). Any other file, the user's own or
    /// a copy whose origin is gone, changed or not in the library (like a font installed by opening it), keeps its
    /// place in the library in Cicero's Deactivated folder: another file with the same font names (macOS's, Adobe
    /// Fonts', another version) is no copy of it. The whole file decides, so a collection or variable font goes to
    /// the Trash only when every face in it is in the origin.
    /// Returns where the file went when it went to the Deactivated folder, nil when it went to the Trash.
    @discardableResult
    private func moveOutOfFontsFolder(_ path: String, listed: Set<String>, records: ActivationRecords) throws -> String? {
        let url = Self.url(path)
        if let origin = records.installedCopies[path], listed.contains(origin), Self.isIdenticalCopy(path, of: origin) {
            try trash(url)
            return nil
        }
        let fm = FileManager.default
        try fm.createDirectory(at: locations.deactivated, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: url.lastPathComponent, in: locations.deactivated)
        try Self.move(url, to: destination)
        return destination.path
    }

    /// Whether two paths are separate files with the same bytes, so one can go without losing any face in
    /// it. The same file reached twice (a symbolic link, a hard link) is no copy. A file iCloud has taken off
    /// the Mac is never read, which would download it, so it doesn't count either.
    public static func isIdenticalCopy(_ path: String, of original: String) -> Bool {
        var copy = stat(), source = stat()
        guard stat(path, &copy) == 0, stat(original, &source) == 0,
              copy.st_mode & S_IFMT == S_IFREG, source.st_mode & S_IFMT == S_IFREG,
              copy.st_dev != source.st_dev || copy.st_ino != source.st_ino,
              copy.st_size == source.st_size,
              (copy.st_flags | source.st_flags) & UInt32(SF_DATALESS) == 0
        else { return false }
        return FileManager.default.contentsEqual(atPath: path, andPath: original)
    }

    /// Moves a file and gives it back its Date Added, which macOS sets anew for a file moved into another folder: a font
    /// Cicero turns off or on, or puts into the Font Library, arrives no more than it did before (see `Family.lastAdded`).
    static func move(_ source: URL, to destination: URL) throws {
        let added = dateAdded(of: source)
        try FileManager.default.moveItem(at: source, to: destination)
        if let added { setDateAdded(added, of: destination) }
    }

    /// Finder's Date Added, where the disk keeps one.
    static func dateAdded(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    /// Sets Finder's Date Added, where the disk keeps one; elsewhere the file keeps the date it has.
    static func setDateAdded(_ date: Date, of url: URL) {
        var list = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: attrgroup_t(ATTR_CMN_ADDEDTIME),
                            volattr: 0, dirattr: 0, fileattr: 0, forkattr: 0)
        let seconds = date.timeIntervalSince1970.rounded(.down)
        var time = timespec(tv_sec: Int(seconds), tv_nsec: Int((date.timeIntervalSince1970 - seconds) * 1_000_000_000))
        _ = setattrlist(url.path, &list, &time, MemoryLayout<timespec>.size, 0)
    }

    /// "Name.otf", then "Name 2.otf", "Name 3.otf"…
    static func uniqueURL(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name, isDirectory: false)
        var number = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)", isDirectory: false)
            number += 1
        }
        return candidate
    }

    private static func size(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// "Inter Bold activated", "Inter activated", "Inter and Roboto activated" or "12 families activated", naming the
    /// fonts `done` (see `FontNames`), else "Activated 3 files"; or what couldn't be done, by name (`undone`) when
    /// nothing could.
    static func message(_ past: String, _ verb: String, succeeded: Int, failed: Int,
                                done: @autoclosure () -> String? = nil, undone: @autoclosure () -> String? = nil) -> String {
        if failed == 0 {
            if let done = done() { return "\(done) \(past.lowercased())" }
            return succeeded <= 1 ? past : "\(past) \(succeeded) files"
        }
        if succeeded == 0 {
            if let undone = undone() { return "Couldn’t \(verb) \(undone)" }
            return failed == 1 ? "Couldn’t \(verb) the font" : "Couldn’t \(verb) \(failed) files"
        }
        return "Couldn’t \(verb) \(failed) of \(succeeded + failed) files"
    }

    /// The fonts among `faces` whose files are among `paths`, named for a toast (see `FontNames`).
    private static func names(of faces: [LibraryFace], in paths: Set<String>) -> String? {
        FontNames.describe(faces.filter { paths.contains($0.face.path) })
    }
}
