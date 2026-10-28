import CoreText
import Foundation
import os
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
    /// Turns files in a Fonts folder on or off where they are, as Font Book does: macOS keeps a list of the fonts it has
    /// off, so they stay off until turned on again, or until their file moves or changes. Turning one off also ends a
    /// session registration of it, and leaves it on the list. Returns the paths that aren't on or off as asked afterwards.
    func setEnabled(_ urls: [URL], _ enabled: Bool) async -> Set<String>
    /// Synchronous turning off, for when the app is about to quit.
    func disableNow(_ urls: [URL])
    /// Waits, up to `timeout`, until macOS's list of fonts it has off no longer names these paths, as it stops doing a
    /// moment after a file there has gone, looking `every` so often. Returns the paths it still names.
    func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String>
    /// Every font file the system has active.
    func activeFontURLs() -> [URL]
    /// Whether the system has the file active, in any scope. Also true for files `activeFontURLs` leaves
    /// out because their fonts have hidden names (starting with a dot).
    func isActive(_ url: URL) -> Bool
}

public struct CoreTextRegistrar: FontRegistrar {
    public init() {}

    /// Returns once fontd has registered the files and told every app, so they're usable the moment this
    /// returns. Files turned off in macOS stay off when registered again, so those are turned back on, and so is a
    /// new file registered for good that's off: one put where a file turned off was a moment ago is, until fontd
    /// notices the old one went.
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
        let failed = Self.given(result.failed, among: urls)
        let disabled = urls.filter { url in
            let path = url.path(percentEncoded: false)
            return !failed.contains(path) && (ignored.contains(path) || scope == .persistent) && !isActive(url)
        }
        if !disabled.isEmpty { Self.setEnabledNow(disabled, true) }
        return failed
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

    public func setEnabled(_ urls: [URL], _ enabled: Bool) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        // It returns once fontd has done it, in a few milliseconds a file, unless fontd isn't answering: then the files
        // that aren't as asked by the time it's waited long enough count as failed.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable () -> Void = {
                guard resumed.withLock({ let first = !$0; $0 = true; return first }) else { return }
                continuation.resume()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                Self.setEnabledNow(urls, enabled)
                resume()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15 + 0.05 * Double(urls.count), execute: resume)
        }
        var pending = urls.filter { Self.isActive($0) != enabled }
        let deadline = ContinuousClock.now + .seconds(1)
        while !pending.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            pending = pending.filter { Self.isActive($0) != enabled }
        }
        return Set(pending.map { $0.path(percentEncoded: false) })
    }

    public func disableNow(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            Self.setEnabledNow(urls, false)
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 3)
    }

    /// Every font in the files (all faces of a collection, all named instances of a variable font) and no other: each by
    /// its file and PostScript name. The descriptors CoreText makes from a file would turn off every file with fonts of
    /// those names in the Fonts folders too, another copy of the font the user has on (tested in a macOS 26 VM). A file
    /// reached through a symlink goes by its real path too, the one fontd has it by.
    private static func setEnabledNow(_ urls: [URL], _ enabled: Bool) {
        let descriptors = urls.flatMap { url in
            let paths = [url.path(percentEncoded: false)] + LibraryScanner.linkedPaths(url.path(percentEncoded: false)).sorted()
            return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []).flatMap { font -> [CTFontDescriptor] in
                guard let name = CTFontDescriptorCopyAttribute(font, kCTFontNameAttribute) as? String else { return [] }
                return paths.map { path in
                    CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: URL(fileURLWithPath: path), kCTFontNameAttribute: name] as CFDictionary)
                }
            }
        }
        guard !descriptors.isEmpty else { return }
        CTFontManagerEnableFontDescriptors(descriptors as CFArray, enabled)
    }

    public func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String> {
        var left = Set(paths)
        let deadline = ContinuousClock.now + timeout
        while true {
            // Asked about the files, fontd runs, and it lets go of gone files only while it does (seen after a restart).
            for path in left { _ = CTFontManagerGetScopeForURL(URL(fileURLWithPath: path) as CFURL) }
            left.formIntersection(Self.offListPaths())
            if left.isEmpty || ContinuousClock.now >= deadline { return left }
            try? await Task.sleep(for: every)
        }
    }

    /// The files macOS's list of fonts it has off names. It keeps the list in the user's com.apple.FontRegistry.user
    /// preferences, `DisabledFonts`: "file:///…/Name.otf#postscript-name=Name-Regular" for each font (Font Book's too).
    static func offListPaths() -> Set<String> {
        let domain = "com.apple.FontRegistry.user" as CFString
        CFPreferencesAppSynchronize(domain)
        let entries = CFPreferencesCopyAppValue("DisabledFonts" as CFString, domain) as? [String] ?? []
        return Set(entries.compactMap { entry in
            URL(string: entry.components(separatedBy: "#postscript-name=")[0])?.path(percentEncoded: false)
        })
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
    /// For `install`: where each file's copy is, by the file. For `replace`: where added files went that didn't take the
    /// old file's path, by that path.
    public var placed: [String: String] = [:]
    /// For `replace`: added files that went in as "Name 2.otf" only because macOS hadn't let go of the old file yet → the
    /// path they're meant for (see `renameBack`).
    public var renameLater: [String: String] = [:]

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

/// Turns fonts on and off. Files in ~/Library/Fonts stay where they are: they're turned off there, as Font Book does
/// it. Never deletes a user's only copy: a copy Cicero installed goes to the Trash only when another copy takes its
/// place (see `switchCopies`) and the file it was copied from is still there with the same contents, in the library.
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
    /// How long a file macOS took without an error may take to show as on (see `registerAndConfirm`). Tests that have
    /// files stay off on purpose make it shorter.
    public var confirmationWait: Duration = .seconds(2)
    /// How long Replace waits for macOS to let go of an off file before the new one takes its path (see `replaceOff`).
    /// Idle, macOS lets go within a second; busy with fonts that just arrived, it took up to 8.4 s (macOS 26 VM).
    public var forgetWait: Duration = .seconds(10)
    /// How long after that a file that went in as "Name 2" waits for its name (see `renameBack`).
    public var renameBackWait: Duration = .seconds(120)

    public init(locations: Locations, registrar: any FontRegistrar = CoreTextRegistrar()) {
        self.locations = locations
        self.registrar = registrar
    }

    /// Copies into ~/Library/Fonts, or into the family's folder in the Font Library (see `installsIntoFontLibrary`), or
    /// registers in place (`method` is `.copy`, `.move` or `.inPlace`). The app turns fonts on with `.inPlace` only: turning
    /// a font on never copies it, and copying is for installing (`install`). With `.move`, files in `movable` (ones the
    /// user added one at a time) are moved there instead (see `removeOriginals`), and the rest copied. A copy an earlier
    /// version installed goes on again while it's the same as its file; once the file has changed, the file goes on
    /// instead, where it is with `.inPlace`, the old copy left off, or copied in its place with `.copy` and `.move` (see
    /// `currentVersion`). Files from Cicero's Inactive folder, which only keeps
    /// fonts while they're off, are always moved, whatever `method` is. Faces from
    /// app-only folders and from the Font Library are always registered in place, the former after going back into
    /// the folder if Cicero moved them out; faces in a Fonts folder that are off (turned off there, by Cicero or Font
    /// Book) are turned on there, and so is a copy installed before and turned off since. Temporarily active faces are
    /// made permanent.
    ///
    /// Copies are registered too: left alone, they reach apps only when macOS notices the file, seconds
    /// later. A file counts as activated once macOS reports it active, so it's usable in every app as
    /// soon as this returns.
    @concurrent
    public func activate(_ faces: [LibraryFace], method: InstallMethod, records: ActivationRecords, movable: Set<String> = []) async -> ActivationResult {
        let signpost = Signposts.activation.beginInterval("Activate", "\(faces.count) faces")
        defer { Signposts.activation.endInterval("Activate", signpost) }
        var records = records
        followRenamedOrigins(of: faces, records: &records)
        var failed: [String] = []
        // Files to copy, and the family each is copied for (see `placeCopy`).
        var toCopy: [(path: String, family: String)] = []
        // Files to register where they are; `record` for those Cicero must remember to unregister.
        var toRegister: [(path: String, record: Bool)] = []
        let targets = Self.uniqueByPath(faces.map { currentVersion(of: installedCopy(of: $0, records: records), records: records) })
            .filter(\.canActivate)
        // A session registration of the same file would shadow the permanent one. One of a file in a Fonts folder ends
        // only once the file is on there (below): ending it first would take the file off macOS's list of fonts it has
        // off, and leave it off.
        let temporary = targets.map(\.face.path).filter { records.temporary[$0] != nil }
        let sessionOnly = temporary.filter { !isInsideFontsFolder($0) }
        let stuckInSession = sessionOnly.isEmpty ? [] : await registrar.unregister(sessionOnly.map(Self.url), scope: .session)
        for path in temporary where !stuckInSession.contains(path) { records.temporary[path] = nil }
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
            } else if face.app != nil || isInFontLibrary(path) || method == .inPlace && !isInInactiveFolder(path) {
                toRegister.append((path, true))
            } else {
                toCopy.append((path, face.face.familyName))
            }
        }
        // Unregistering isn't needed: they're off. A new file where one turned off was a moment ago is turned on as it's
        // registered (see `CoreTextRegistrar.register`).
        for path in toCopy.flatMap({ outdatedCopies(of: $0.path, records: records) }) where (try? trash(Self.url(path))) != nil {
            records.installedCopies[path] = nil
            removeEmptyFolders(around: path)
        }
        var copies: [PlacedCopy] = []
        Signposts.activation.withIntervalSignpost("Copy", "\(toCopy.count) files") {
            for (path, family) in toCopy {
                do {
                    copies.append(try placeCopy(of: path, family: family, records: records))
                } catch {
                    failed.append(path)
                }
            }
        }
        // Files in a Fonts folder go on where they are; registering takes care of any macOS hasn't noticed yet.
        let inFontsFolders = (toRegister.map(\.path) + copies.filter { !$0.isNew }.map(\.destination)).filter(isInsideFontsFolder)
        var stillOff = inFontsFolders.isEmpty ? [] : await registrar.setEnabled(inFontsFolders.map(Self.url), true)
        // One that was on for a while seems on either way; with its session registration ended, it's on only if it went on.
        let wereTemporary = temporary.filter { isInsideFontsFolder($0) && !stillOff.contains($0) }
        if !wereTemporary.isEmpty {
            _ = await registrar.unregister(wereTemporary.map(Self.url), scope: .session)
            stillOff.formUnion(wereTemporary.filter { !registrar.isActive(Self.url($0)) })
        }
        let enabled = Set(inFontsFolders).subtracting(stillOff)
        let registering = (toRegister.map(\.path) + copies.map(\.destination)).filter { !enabled.contains($0) }
        let stuck = await registerAndConfirm(registering, scope: .persistent)
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
                                   done: Self.names(of: targets, in: done), undone: Self.names(of: targets, in: Set(failed)))
        let removed = removeOriginals(of: installed.filter { copy in
            method == .move && movable.contains(copy.source)
                || isInInactiveFolder(copy.source)
                    && !records.installedCopies.contains { $0.key != copy.destination && $0.value == copy.source }
        })
        // Back in ~/Library/Fonts, a file from the Inactive folder is the user's own again, no copy of anything.
        for copy in removed where isInInactiveFolder(copy.source) && !isInFontLibrary(copy.destination) {
            records.installedCopies[copy.destination] = nil
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Whether `activate` does the same with the face whatever the install method: it turns one from an app's own folder, a
    /// Fonts folder or Cicero's Library on where it is, and moves one from the Inactive folder where turning it on puts it,
    /// so there's nothing to ask.
    public func ignoresInstallMethod(_ face: LibraryFace) -> Bool {
        let path = face.face.path
        return face.app != nil || isInsideFontsFolder(path) || isInFontLibrary(path) || isInInactiveFolder(path)
    }

    /// Copies font files into ~/Library/Fonts and turns them on, as opening files the library doesn't have does when
    /// fonts are activated by copying. The originals stay where they are, out of the library; the copies stay in the
    /// Fonts folder when turned off. `moving`, as when fonts are activated by moving, they go (see `removeOriginals`).
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
        var result = ActivationResult(records: records, succeeded: installed.count, failed: failed, message: message)
        result.placed = Dictionary(installed.map { ($0.source, $0.destination) }, uniquingKeysWith: { first, _ in first })
        return result
    }

    /// Takes out the copies macOS didn't turn on: a copy macOS won't use only clutters the Fonts folder. Returns the ones
    /// it kept. Nothing is remembered as a copy of anything: once installed, a font is the user's own, wherever it came
    /// from (`records.installedCopies` only has what earlier versions wrote).
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
        followRenamedOrigins(of: faces, records: &records)
        var failed: [String] = []
        var succeeded = 0
        var done = Set<String>()
        var toRegister: [String] = []
        let session = Self.currentSession()
        // An old copy whose file has changed gives way to the new version, where it is, as `activate` copies it.
        let targets = Self.uniqueByPath(faces.map { currentVersion(of: $0, records: records) })
        // Never one of Creative Cloud's: one only Adobe apps load would be on in every app.
        for face in targets where !face.isAdobeFonts {
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
        if failed.isEmpty, let name = Self.names(of: targets, in: done) {
            message = "\(name) activated until Cicero quits"
        } else if failed.isEmpty {
            message = succeeded <= 1 ? "Activated until Cicero quits" : "Activated \(succeeded) files until Cicero quits"
        } else {
            message = Self.message("Activated", "activate", succeeded: succeeded, failed: failed.count,
                                   undone: Self.names(of: targets, in: Set(failed)))
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Moves styles to other copies of them (see `CopyChooser.plan`): the old copies go off first, and those Cicero
    /// installed in a Fonts folder from originals still in the library go to the Trash, so the new ones don't land
    /// beside them as "Name 2.otf"; then the new ones go on. A style whose new copy doesn't go on gets its old copies
    /// back rather than none; any that can't come back are among `failed`. With `.move`, new copies in `movable` are
    /// moved into the Fonts folder (see `activate`).
    @concurrent
    public func switchCopies(_ switches: [CopySwitch], method: InstallMethod, records: ActivationRecords, movable: Set<String> = []) async -> ActivationResult {
        let origins = records.installedCopies
        var moved: [String: String] = [:]
        let off = await deactivate(switches.flatMap(\.others), records: records, trashingCopies: true, moved: &moved)
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

    /// Turns copies back on as they were: in place, until Cicero quits, in ~/Library/Fonts where they stayed, or (when one
    /// went to the Trash, being the same as its original) installed again from its original.
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

    /// Files in a Fonts folder are turned off where they are, as Font Book does it: apps drop them at once, and macOS keeps
    /// them off until they're turned on again. Faces an app loads from its own folder leave that folder for Cicero's
    /// Inactive folder, so they're off in the app too.
    @concurrent
    public func deactivate(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var moved: [String: String] = [:]
        return await deactivate(faces, records: records, moved: &moved)
    }

    /// `moved` gets where the files that were on from a Fonts folder are now: still there, unless `trashingCopies` and
    /// the file is a spare copy Cicero installed (see `isSpareInstalledCopy`), which goes to the Trash.
    private func deactivate(_ faces: [LibraryFace], records: ActivationRecords, trashingCopies: Bool = false,
                            moved: inout [String: String]) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var locked: [String] = []
        var succeeded = 0
        var inFontsFolder: [String] = []
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
                inFontsFolder.append(path)
            case .temporary where isInsideFontsFolder(path):
                // Ending its session registration would take it off macOS's list of fonts it has off, and macOS would
                // turn it on again later: it's turned off there, which ends the session registration too.
                inFontsFolder.append(path)
            case .inPlace, .otherApp:
                persistent.append(path)
            case .temporary:
                session.append(path)
            case .macOS, .allUsers, .app, .adobeFonts:
                locked.append(path)
            }
        }
        // Cicero's spare copies, when another copy takes their place, go to the Trash. They're unregistered first, so apps
        // drop them at once: turned off, they'd be on macOS's list of fonts it has off, which turns a new file of the
        // same name there off too, until fontd notices the old one went.
        let spares = trashingCopies
            ? inFontsFolder.filter { records.temporary[$0] == nil && isSpareInstalledCopy($0, listed: listed[$0] ?? [], records: records) }
            : []
        var offThere = inFontsFolder.filter { !spares.contains($0) }
        if !spares.isEmpty {
            _ = await registrar.unregister(spares.map(Self.url), scope: .persistent)
            for path in spares {
                if (try? trash(Self.url(path))) != nil {
                    records.installedCopies[path] = nil
                    removeEmptyFolders(around: path)
                    succeeded += 1
                } else {
                    // Still in the Fonts folder: on again, as macOS would soon make it anyway, and then off there.
                    _ = await registrar.register([Self.url(path)], scope: .persistent)
                    offThere.append(path)
                }
            }
        }
        if !offThere.isEmpty {
            let stillOn = await registrar.setEnabled(offThere.map(Self.url), false)
            for path in offThere {
                if stillOn.contains(path) {
                    failed.append(path)
                } else {
                    records.temporary[path] = nil
                    moved[path] = path
                    succeeded += 1
                }
            }
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
        let done = Set(inFontsFolder + persistent + session + leaving).subtracting(failed)
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
        // Not one that's off in the Fonts folder: one that stays would go on again.
        let persistent = plan.paths.filter { records.inPlace.contains($0) || isInsideUserFonts($0) && registrar.isActive(Self.url($0)) }
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

    /// Stops using files registered in place (e.g. ones whose files are gone) and forgets them.
    @concurrent
    public func forgetInPlace(_ paths: [String], records: ActivationRecords) async -> ActivationRecords {
        var records = records
        _ = await registrar.unregister(paths.map(Self.url), scope: .persistent)
        records.inPlace.subtract(paths)
        return records
    }

    /// Copies a font used in place into ~/Library/Fonts (or the Font Library), then stops using the original in place.
    /// One in the Font Library is installed already.
    @concurrent
    public func installCopy(of face: LibraryFace, records: ActivationRecords) async -> ActivationResult {
        var records = records
        let path = face.face.path
        let name = FontNames.describe([face])
        guard !isInFontLibrary(path) else { return ActivationResult(records: records, succeeded: 0, failed: [], message: "\(name ?? "The font") is in Cicero’s Library") }
        let place = installsIntoFontLibrary && fontLibrary != nil ? "Cicero’s Library" : "your Fonts folder"
        let failure = ActivationResult(records: records, succeeded: 0, failed: [path], message: "Couldn’t copy \(name ?? "the font") into \(place)")
        guard let copy = try? placeCopy(of: path, family: face.face.familyName) else { return failure }
        guard await registerAndConfirm([copy.destination], scope: .persistent).isEmpty else {
            if copy.isNew {
                try? FileManager.default.removeItem(atPath: copy.destination)
                removeEmptyFolders(around: copy.destination)
            }
            return failure
        }
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
        var earlier: [String] = []
        for (path, record) in records.temporary {
            switch record.scope {
            case .untilQuit: leftovers.append(path)
            case .whileAppsRun: if record.session != session { earlier.append(path) }
            }
        }
        if !leftovers.isEmpty {
            _ = await endSessionRegistrations(leftovers)
            for path in leftovers { records.temporary[path] = nil }
        }
        // An application set's registration from before a logout ended with it. One in a Fonts folder is off there again;
        // one that's on was turned on for good along the way, and goes off.
        let stillOn = earlier.filter { isInsideFontsFolder($0) && registrar.isActive(Self.url($0)) }
        if !stillOn.isEmpty { _ = await registrar.setEnabled(stillOn.map(Self.url), false) }
        for path in earlier { records.temporary[path] = nil }
        return records
    }

    /// Turns on again what macOS has let go of, as clearing its font caches does: files Cicero registered where they are,
    /// for good or for the session, that are there but off now. The records stay as they are; one that won't go on is among
    /// `failed`.
    @concurrent
    public func registerAgain(_ records: ActivationRecords) async -> ActivationResult {
        func lost(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) && !registrar.isActive(Self.url(path)) }
        let persistent = records.inPlace.filter(lost).sorted()
        let session = records.temporary.keys.filter(lost).sorted()
        let failed = await registerAndConfirm(persistent, scope: .persistent).union(await registerAndConfirm(session, scope: .session))
        return ActivationResult(records: records, succeeded: persistent.count + session.count - failed.count, failed: failed.sorted(), message: "")
    }

    /// Ends session registrations ("until Cicero quits", application sets) and returns the paths still on. A file in a
    /// Fonts folder is turned off there instead: unregistering it would take it off macOS's list of fonts it has off,
    /// leaving it to be turned on again later.
    func endSessionRegistrations(_ paths: [String]) async -> Set<String> {
        let inFontsFolders = paths.filter(isInsideFontsFolder)
        let elsewhere = paths.filter { !isInsideFontsFolder($0) }
        var stillOn = inFontsFolders.isEmpty ? [] : await registrar.setEnabled(inFontsFolders.map(Self.url), false)
        if !elsewhere.isEmpty { stillOn.formUnion(await registrar.unregister(elsewhere.map(Self.url), scope: .session)) }
        return stillOn
    }

    /// At launch: turning a font on used to leave its file in the Inactive folder, as the original of the copy that
    /// went into ~/Library/Fonts or the Font Library. The copy is the font now, so the file goes, once the copy has the
    /// same contents and it's the original of no other copy, as `activate` does it now; in ~/Library/Fonts, the copy
    /// is the user's own again. Returns how many files went.
    @concurrent
    public func tidyInactiveFolder(_ records: ActivationRecords) async -> (records: ActivationRecords, removed: Int) {
        var records = records
        var removed = 0
        let copiesOf = Dictionary(grouping: records.installedCopies.values, by: { $0 }).mapValues(\.count)
        for (copy, original) in records.installedCopies where isInInactiveFolder(original) && copiesOf[original] == 1 {
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
        // As `endSessionRegistrations` does it.
        let inFontsFolders = paths.filter(isInsideFontsFolder)
        let elsewhere = paths.filter { !isInsideFontsFolder($0) }
        if !inFontsFolders.isEmpty { registrar.disableNow(inFontsFolders.map(Self.url)) }
        if !elsewhere.isEmpty { registrar.unregisterNow(elsewhere.map(Self.url), scope: .session) }
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

    func isInsideUserFonts(_ path: String) -> Bool {
        path.hasPrefix(locations.userFonts.path + "/")
    }

    /// ~/Library/Fonts or /Library/Fonts, where a file is active unless it's turned off in macOS.
    func isInsideFontsFolder(_ path: String) -> Bool {
        isInsideUserFonts(path) || path.hasPrefix(locations.allUsersFonts.path + "/")
    }

    /// Registers files and returns the ones that aren't active afterwards: those CoreText rejects and
    /// any it accepts but doesn't turn on. One it took without an error can show as on a moment after, ~0.3 s in a
    /// macOS 26 VM, so those are given `confirmationWait`.
    func registerAndConfirm(_ paths: [String], scope: CTFontManagerScope) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let signpost = Signposts.activation.beginInterval("Register", "\(paths.count) files")
        var stuck = await registrar.register(paths.map(Self.url), scope: scope)
        Signposts.activation.endInterval("Register", signpost)
        let confirming = Signposts.activation.beginInterval("Confirm")
        var pending = paths.filter { !stuck.contains($0) && !registrar.isActive(Self.url($0)) }
        let deadline = ContinuousClock.now + confirmationWait
        while !pending.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            pending = pending.filter { !registrar.isActive(Self.url($0)) }
        }
        stuck.formUnion(pending)
        Signposts.activation.endInterval("Confirm", confirming)
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
    /// half-written file. A file of the same name with the same contents is already installed, and so is a copy
    /// `records` say was installed from it there before, by whatever name, if it still has the same contents (turned off
    /// since, it's still there); another file of that name gets "Name 2.otf".
    private func placeCopy(of path: String, family: String?, records: ActivationRecords? = nil) throws -> PlacedCopy {
        let fm = FileManager.default
        let source = Self.url(path)
        let folder = installFolder(for: path, family: family)
        if let records, let earlier = earlierCopy(of: path, family: family, records: records) {
            return PlacedCopy(destination: earlier, source: path, isNew: false)
        }
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
        // A font back from the Inactive folder, which it only left the Fonts folder for, arrives no more than then.
        if isInInactiveFolder(path), let added = Self.dateAdded(of: source) { Self.setDateAdded(added, of: destination) }
        return PlacedCopy(destination: destination.path, source: path, isNew: true)
    }

    /// The copy of `path` Cicero installed before where it would install one now, if it's still the same as the file.
    private func earlierCopy(of path: String, family: String?, records: ActivationRecords) -> String? {
        let folder = installFolder(for: path, family: family).path
        return records.installedCopies.filter { copy, origin in
            origin == path && (copy as NSString).deletingLastPathComponent == folder && Self.isIdenticalCopy(copy, of: path)
        }.keys.min()
    }

    /// The copies of `path` Cicero installed before that are off, the file having changed since, to a new version or to
    /// another font saved under its name: they follow the file, as the new copy takes their place (left there, it would
    /// land beside them as "Name 2.otf"). None while the file can't be read, as it can't be copied either.
    private func outdatedCopies(of path: String, records: ActivationRecords) -> [String] {
        let candidates = records.installedCopies.filter { copy, origin in
            origin == path && Self.hasChanged(path, since: copy) && !registrar.isActive(Self.url(copy))
        }.keys.sorted()
        guard !candidates.isEmpty, !FontFileReader.faces(atPath: path).isEmpty else { return [] }
        return candidates
    }

    /// For a file Cicero installed a copy of before, that copy, when it's off and still the same as the file: a font that
    /// was installed goes on again where it was installed, also when it's turned on where it is now (Ask, Leave), so it
    /// stays in the Fonts folder for Microsoft Office.
    private func installedCopy(of face: LibraryFace, records: ActivationRecords) -> LibraryFace {
        let path = face.face.path
        guard !face.state.isActive, face.app == nil, !isInsideFontsFolder(path), !isInFontLibrary(path), !isInInactiveFolder(path)
        else { return face }
        let copy = face.copies.filter { copy in
            records.installedCopies[copy.face.path] == path && !copy.state.isActive && copy.app == nil
                && Self.isIdenticalCopy(copy.face.path, of: path)
        }.min { $0.face.path < $1.face.path }
        return copy?.libraryFace ?? face
    }

    /// For an installed copy that's off, the file it was copied from, when that's in the library and has changed since:
    /// with both off, the library shows the copy in the Fonts folder, and turning it on would bring back the old version.
    private func currentVersion(of face: LibraryFace, records: ActivationRecords) -> LibraryFace {
        let path = face.face.path
        guard let origin = records.installedCopies[path], let file = face.copies.first(where: { $0.face.path == origin }),
              Self.hasChanged(origin, since: path), !registrar.isActive(Self.url(path))
        else { return face }
        return file.libraryFace
    }

    /// Copies Cicero installed whose file is gone, among `faces`' files, follow the one file with the same font left in
    /// its folder: a new version saved under another name, or the same file renamed. It's then that copy's file, which
    /// `installedCopy` and `currentVersion` go by. Not while the folder can't be reached, or with several to choose from.
    private func followRenamedOrigins(of faces: [LibraryFace], records: inout ActivationRecords) {
        let fm = FileManager.default
        for face in faces {
            let files = [face.face.path] + face.copies.map(\.face.path)
            for copy in files {
                guard let origin = records.installedCopies[copy], !fm.fileExists(atPath: origin) else { continue }
                let folder = (origin as NSString).deletingLastPathComponent
                let successors = files.filter {
                    $0 != copy && records.installedCopies[$0] == nil && ($0 as NSString).deletingLastPathComponent == folder
                        && fm.fileExists(atPath: $0)
                }
                if successors.count == 1 { records.installedCopies[copy] = successors[0] }
            }
        }
    }

    /// Whether `original` no longer has the contents `copy` was made with. Not when either is only in iCloud Drive or
    /// Dropbox, not downloaded: reading it to compare would download it.
    private static func hasChanged(_ original: String, since copy: String) -> Bool {
        var copyInfo = stat(), originalInfo = stat()
        guard stat(copy, &copyInfo) == 0, stat(original, &originalInfo) == 0,
              copyInfo.st_mode & S_IFMT == S_IFREG, originalInfo.st_mode & S_IFMT == S_IFREG,
              copyInfo.st_dev != originalInfo.st_dev || copyInfo.st_ino != originalInfo.st_ino,
              (copyInfo.st_flags | originalInfo.st_flags) & UInt32(SF_DATALESS) == 0
        else { return false }
        return !isIdenticalCopy(copy, of: original)
    }

    /// Moves a file out of an app's folder into Cicero's Inactive folder, so the app stops loading it,
    /// and remembers where it was.
    private func moveOutOfAppFolder(_ path: String, records: inout ActivationRecords) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: locations.inactiveFolder, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: locations.inactiveFolder)
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

    /// A copy Cicero installed whose original is still there, unchanged, and in the library (among `listed`, the library's
    /// other files with the same fonts), so it can go without the font leaving the library. Any other file, the user's
    /// own or a copy whose origin is gone, changed or not in the library (like a font installed by opening it), is
    /// no spare: another file with the same font names (macOS's, Adobe Fonts', another version) is no copy of it. The
    /// whole file decides, so a collection or variable font is spare only when every face in it is in the origin.
    private func isSpareInstalledCopy(_ path: String, listed: Set<String>, records: ActivationRecords) -> Bool {
        guard let origin = records.installedCopies[path] else { return false }
        return listed.contains(origin) && Self.isIdenticalCopy(path, of: origin)
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
