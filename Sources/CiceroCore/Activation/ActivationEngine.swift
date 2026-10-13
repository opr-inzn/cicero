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
    /// returns. Files Font Book turned off stay off when registered again, so those are turned back on.
    public func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let result = await Self.perform(urls, ignoring: .alreadyRegistered) { handler in
            CTFontManagerRegisterFontURLs(urls as CFArray, scope, true, handler)
        }
        let disabled = urls.filter { result.ignored.contains($0.path(percentEncoded: false)) && !isActive($0) }
        if !disabled.isEmpty {
            let descriptors = disabled.flatMap { CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor] ?? [] }
            CTFontManagerEnableFontDescriptors(descriptors as CFArray, true)
        }
        return result.failed
    }

    public func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        return await Self.perform(urls, ignoring: .notRegistered) { handler in
            CTFontManagerUnregisterFontURLs(urls as CFArray, scope, handler)
        }.failed
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

    public func isActive(_ url: URL) -> Bool {
        CTFontManagerGetScopeForURL(url as CFURL) != .none
    }

    /// Runs a CoreText registration call and waits for its last callback. fontd can hang, and an
    /// operation that never finishes would hold up every one after it, so after a while every file counts
    /// as failed (fontd takes a few milliseconds a file).
    private static func perform(
        _ urls: [URL], ignoring ignored: CTFontManagerError, _ start: (@escaping (CFArray, Bool) -> Bool) -> Void
    ) async -> (failed: Set<String>, ignored: Set<String>) {
        await withCheckedContinuation { continuation in
            let collector = FailureCollector(ignoring: ignored, continuation: continuation)
            start { errors, done in
                collector.add(errors as! [CFError])
                if done { collector.finish() }
                return true
            }
            let timeout = 15 + 0.05 * Double(urls.count)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                collector.finish(failing: Set(urls.map { $0.path(percentEncoded: false) }))
            }
        }
    }

    /// Gathers the files named by CoreText's errors (the handler can run more than once) and resumes
    /// the caller once, when CoreText is done or the wait times out.
    private final class FailureCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let ignoredCode: CTFontManagerError
        private var continuation: CheckedContinuation<(failed: Set<String>, ignored: Set<String>), Never>?
        private var failed = Set<String>()
        private var ignored = Set<String>()

        init(ignoring: CTFontManagerError, continuation: CheckedContinuation<(failed: Set<String>, ignored: Set<String>), Never>) {
            ignoredCode = ignoring
            self.continuation = continuation
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

        func finish(failing extra: Set<String> = []) {
            let resume = lock.withLock { () -> (CheckedContinuation<(failed: Set<String>, ignored: Set<String>), Never>, Set<String>, Set<String>)? in
                guard let continuation else { return nil }
                self.continuation = nil
                return (continuation, failed.union(extra), ignored)
            }
            guard let (continuation, failed, ignored) = resume else { return }
            continuation.resume(returning: (failed, ignored))
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
    /// A short toast, e.g. "Activated." or "Couldn’t activate 2 of 5 files."
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

    public init(title: String, paths: [String], otherFamilies: [String], protectedCount: Int, removedFamilies: [String], includesCopies: Bool = true) {
        self.title = title
        self.paths = paths
        self.otherFamilies = otherFamilies
        self.protectedCount = protectedCount
        self.removedFamilies = removedFamilies
        self.includesCopies = includesCopies
    }
}

/// Turns fonts on and off. Never deletes a user's only copy: installed copies go to the Trash only
/// when another copy exists, other files in ~/Library/Fonts move to Cicero's Deactivated folder.
public struct ActivationEngine: Sendable {
    private let locations: Locations
    let registrar: any FontRegistrar
    /// Moves a file to the Trash. Tests replace it so they don't fill the user's Trash.
    public var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    public init(locations: Locations, registrar: any FontRegistrar = CoreTextRegistrar()) {
        self.locations = locations
        self.registrar = registrar
    }

    /// Copies into ~/Library/Fonts or registers in place (`method` is `.copy` or `.inPlace`). Faces
    /// from app-only folders are always registered in place, after going back into the folder if Cicero
    /// moved them out; faces in a Fonts folder that macOS has off (Font Book turned them off) are turned
    /// on there. Temporarily active faces are made permanent.
    ///
    /// Copies are registered too: left alone, they reach apps only when macOS notices the file, seconds
    /// later. A file counts as activated once macOS reports it active, so it's usable in every app as
    /// soon as this returns.
    @concurrent
    public func activate(_ faces: [LibraryFace], method: InstallMethod, records: ActivationRecords) async -> ActivationResult {
        let signpost = Signposts.activation.beginInterval("Activate", "\(faces.count) faces")
        defer { Signposts.activation.endInterval("Activate", signpost) }
        var records = records
        var failed: [String] = []
        var toCopy: [String] = []
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
            } else if face.app != nil || method == .inPlace {
                toRegister.append((path, true))
            } else {
                toCopy.append(path)
            }
        }
        var copies: [PlacedCopy] = []
        Signposts.activation.withIntervalSignpost("Copy", "\(toCopy.count) files") {
            for path in toCopy {
                do {
                    copies.append(try placeCopy(of: path))
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
        for copy in copies {
            if stuck.contains(copy.destination) {
                failed.append(copy.source)
                // A copy macOS won't use only clutters the Fonts folder.
                if copy.isNew { try? FileManager.default.removeItem(atPath: copy.destination) }
            } else {
                records.installedCopies[copy.destination] = copy.source
                succeeded += 1
            }
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: Self.message("Activated", "activate", succeeded: succeeded, failed: failed.count))
    }

    /// Registers for the session until Cicero quits. Faces already on for an application set stay on
    /// until then too.
    @concurrent
    public func activateTemporarily(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var succeeded = 0
        var toRegister: [String] = []
        let session = Self.currentSession()
        for face in Self.uniqueByPath(faces) {
            let path = face.face.path
            if records.temporary[path] != nil {
                records.temporary[path] = TemporaryRecord(scope: .untilQuit, session: session)
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
                succeeded += 1
            }
        }
        let message: String
        if failed.isEmpty {
            message = succeeded <= 1 ? "Activated until Cicero quits." : "Activated \(succeeded) files until Cicero quits."
        } else {
            message = Self.message("Activated", "activate", succeeded: succeeded, failed: failed.count)
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

    /// Faces in ~/Library/Fonts that Cicero didn't install and that have no other copy: deactivating
    /// them moves the file into Cicero's Deactivated folder, so the app asks first.
    public func unmanaged(_ faces: [LibraryFace], records: ActivationRecords) -> [LibraryFace] {
        faces.filter { face in
            face.state.source == .fontsFolder && records.installedCopies[face.face.path] == nil && restorableOriginal(of: face, records: records) == nil
        }
    }

    /// Faces an app loads from its own folder also leave that folder for Cicero's Deactivated folder,
    /// so they're off in the app too. Files in ~/Library/Fonts are unregistered before they move, so
    /// apps drop them at once rather than when macOS notices they're gone, seconds later.
    @concurrent
    public func deactivate(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        var failed: [String] = []
        var locked: [String] = []
        var succeeded = 0
        var installed: [LibraryFace] = []
        var persistent: [String] = []
        var session: [String] = []
        var leaving: [String] = []
        for face in Self.uniqueByPath(faces) {
            let path = face.face.path
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
                    try moveOutOfFontsFolder(face, records: records)
                    records.installedCopies[face.face.path] = nil
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
        let message = failed.isEmpty && succeeded == 0 && !locked.isEmpty
            ? "These fonts are managed by macOS or another app."
            : Self.message("Deactivated", "deactivate", succeeded: succeeded, failed: failed.count + locked.count)
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
            ? "On in \(app) only."
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

    /// Files in use are unregistered first, so apps drop them at once.
    @concurrent
    public func moveToTrash(_ plan: TrashPlan, records: ActivationRecords) async -> ActivationResult {
        var records = records
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
        for path in plan.paths {
            do {
                try trash(Self.url(path))
                records.installedCopies[path] = nil
                records.inPlace.remove(path)
                records.temporary[path] = nil
                records.appFolderOrigins[path] = nil
                succeeded += 1
            } catch {
                failed.append(path)
            }
        }
        // Files that stayed where they were stay in use.
        let kept = persistent.filter(failed.contains)
        if !kept.isEmpty { _ = await registrar.register(kept.map(Self.url), scope: .persistent) }
        let message: String
        if failed.isEmpty {
            message = succeeded <= 1 ? "Moved to the Trash." : "Moved \(succeeded) files to the Trash."
        } else if succeeded == 0 {
            message = failed.count == 1 ? "Couldn’t move the file to the Trash." : "Couldn’t move \(failed.count) files to the Trash."
        } else {
            message = "Couldn’t move \(failed.count) of \(succeeded + failed.count) files to the Trash."
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

    /// Copies a font used in place into ~/Library/Fonts, then stops using the original in place.
    @concurrent
    public func installCopy(of face: LibraryFace, records: ActivationRecords) async -> ActivationResult {
        var records = records
        let path = face.face.path
        let failure = ActivationResult(records: records, succeeded: 0, failed: [path], message: "Couldn’t copy the font into your Fonts folder.")
        guard let copy = try? placeCopy(of: path) else { return failure }
        guard await registerAndConfirm([copy.destination], scope: .persistent).isEmpty else {
            if copy.isNew { try? FileManager.default.removeItem(atPath: copy.destination) }
            return failure
        }
        records.installedCopies[copy.destination] = path
        if records.inPlace.contains(path) {
            _ = await registrar.unregister([Self.url(path)], scope: .persistent)
            records.inPlace.remove(path)
        }
        return ActivationResult(records: records, succeeded: 1, failed: [], message: "Installed a copy.")
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
            || path.contains(".app/") || path.contains("/Adobe/CoreSync/")
    }

    // MARK: Files

    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: false)
    }

    private static func uniqueByPath(_ faces: [LibraryFace]) -> [LibraryFace] {
        var seen = Set<String>()
        return faces.filter { seen.insert($0.face.path).inserted }
    }

    private func isInsideUserFonts(_ path: String) -> Bool {
        path.hasPrefix(locations.userFonts.path + "/")
    }

    /// ~/Library/Fonts or /Library/Fonts, where a file is active unless Font Book turned it off.
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

    /// Puts a copy of a file into ~/Library/Fonts. It's copied into Cicero's staging folder first (a clone,
    /// on the same disk) and then moved in, so macOS never sees a half-written file. A file of the same
    /// name with the same contents is already installed; another file of that name gets "Name 2.otf".
    private func placeCopy(of path: String) throws -> PlacedCopy {
        let fm = FileManager.default
        let source = Self.url(path)
        try fm.createDirectory(at: locations.userFonts, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let first = locations.userFonts.appendingPathComponent(name, isDirectory: false)
        if fm.fileExists(atPath: first.path), Self.size(of: first) == Self.size(of: source), fm.contentsEqual(atPath: first.path, andPath: path) {
            return PlacedCopy(destination: first.path, source: path, isNew: false)
        }
        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: false)
        let destination = Self.uniqueURL(for: name, in: locations.userFonts)
        do {
            try fm.copyItem(at: source, to: staged)
            try fm.moveItem(at: staged, to: destination)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return PlacedCopy(destination: destination.path, source: path, isNew: true)
    }

    /// Moves a file out of an app's folder into Cicero's Deactivated folder, so the app stops loading it,
    /// and remembers where it was.
    private func moveOutOfAppFolder(_ path: String, records: inout ActivationRecords) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: locations.deactivated, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: locations.deactivated)
        try fm.moveItem(at: Self.url(path), to: destination)
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
        try FileManager.default.moveItem(at: Self.url(path), to: destination)
        records.appFolderOrigins[path] = nil
        return destination.path
    }

    /// Trashes an installed copy when its original is still there, else keeps the file in Cicero's Deactivated folder.
    private func moveOutOfFontsFolder(_ face: LibraryFace, records: ActivationRecords) throws {
        let url = Self.url(face.face.path)
        if restorableOriginal(of: face, records: records) != nil {
            try trash(url)
        } else {
            let fm = FileManager.default
            try fm.createDirectory(at: locations.deactivated, withIntermediateDirectories: true)
            try fm.moveItem(at: url, to: Self.uniqueURL(for: url.lastPathComponent, in: locations.deactivated))
        }
    }

    /// The recorded origin, or another copy outside ~/Library/Fonts, when it still exists.
    private func restorableOriginal(of face: LibraryFace, records: ActivationRecords) -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let origin = records.installedCopies[face.face.path] { candidates.append(origin) }
        candidates += face.otherCopies.filter { !isInsideUserFonts($0) }
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    /// "Name.otf", then "Name 2.otf", "Name 3.otf"…
    private static func uniqueURL(for name: String, in folder: URL) -> URL {
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

    private static func message(_ past: String, _ verb: String, succeeded: Int, failed: Int) -> String {
        if failed == 0 { return succeeded <= 1 ? "\(past)." : "\(past) \(succeeded) files." }
        if succeeded == 0 { return failed == 1 ? "Couldn’t \(verb) the font." : "Couldn’t \(verb) \(failed) files." }
        return "Couldn’t \(verb) \(failed) of \(succeeded + failed) files."
    }
}
