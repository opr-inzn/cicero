import CoreText
import Foundation
import os
import Security

public protocol FontRegistrar: Sendable {
    func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String>
    func unregisterNow(_ urls: [URL], scope: CTFontManagerScope)
    func setEnabled(_ urls: [URL], _ enabled: Bool) async -> Set<String>
    func disableNow(_ urls: [URL])
    func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String>
    func activeFontURLs() -> [URL]
    func isActive(_ url: URL) -> Bool
    func offFontPaths() -> Set<String>
}

extension FontRegistrar {
    public func offFontPaths() -> Set<String> { [] }
}

public struct CoreTextRegistrar: FontRegistrar {
    public init() {}

    private static func fontdTimeout(for count: Int) -> TimeInterval { 15 + 0.05 * Double(count) }

    public func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let result = await Self.perform(urls, ignoring: .alreadyRegistered, undone: { !Self.isActive($0) }) { handler in
            CTFontManagerRegisterFontURLs(urls as CFArray, scope, true, handler)
        }
        if result.timedOut, !result.failed.isEmpty {
            // fontd may still turn on the files it hadn't by then; they're taken back without waiting, as fontd may not be answering.
            let late = urls.filter { result.failed.contains($0.path(percentEncoded: false)) }
            DispatchQueue.global(qos: .utility).async {
                CTFontManagerUnregisterFontURLs(late as CFArray, scope) { _, _ in true }
            }
        }
        let ignored = Self.given(result.ignored, among: urls)
        let failed = Self.given(result.failed, among: urls)
        // A file turned off in macOS stays off when registered again, and so does a new one registered for good where a file turned off was a moment ago, until fontd notices the old one went.
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
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.fontdTimeout(for: urls.count), execute: resume)
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

    private static func setEnabledNow(_ urls: [URL], _ enabled: Bool) {
        // Each font by its file and PostScript name, never the descriptors CoreText makes from the file: those would turn off every file with fonts of those names in the Fonts folders too.
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
            // Asked about the files, fontd runs, and it lets go of gone files only while it does.
            for path in left { _ = CTFontManagerGetScopeForURL(URL(fileURLWithPath: path) as CFURL) }
            left.formIntersection(Self.offListPaths())
            if left.isEmpty || ContinuousClock.now >= deadline { return left }
            try? await Task.sleep(for: every)
        }
    }

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

    public func offFontPaths() -> Set<String> {
        Self.offListPaths()
    }

    public func isActive(_ url: URL) -> Bool {
        Self.isActive(url)
    }

    private static func isActive(_ url: URL) -> Bool {
        if CTFontManagerGetScopeForURL(url as CFURL) != .none { return true }
        // CoreText knows a file registered through a symlink only by its path with the symlink resolved.
        return LibraryScanner.linkedPaths(url.path(percentEncoded: false)).contains { path in
            CTFontManagerGetScopeForURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL) != .none
        }
    }

    private static func given(_ named: Set<String>, among urls: [URL]) -> Set<String> {
        guard !named.isEmpty else { return named }
        // CoreText's errors name a file by its path with every symlink resolved.
        return Set(urls.map { $0.path(percentEncoded: false) }.filter { path in
            named.contains(path) || !LibraryScanner.linkedPaths(path).isDisjoint(with: named)
        })
    }

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
            // fontd can hang, and a call that never finishes would hold up every one after it.
            let timeout = Self.fontdTimeout(for: urls.count)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard collector.isWaiting else { return }
                // Asking about each file takes fontd too, which may not answer either.
                let all = Set(urls.map { $0.path(percentEncoded: false) })
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { collector.finish(failing: all, timedOut: true) }
                collector.finish(failing: Set(urls.filter(undone).map { $0.path(percentEncoded: false) }), timedOut: true)
            }
        }
    }

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

public struct ActivationResult: Sendable {
    public var records: ActivationRecords
    public var succeeded: Int
    public var failed: [String]
    public var message: String
    public var placed: [String: String] = [:]
    public var renameLater: [String: String] = [:]
    public var trashed: [String: String] = [:]

    public init(records: ActivationRecords, succeeded: Int, failed: [String], message: String) {
        self.records = records
        self.succeeded = succeeded
        self.failed = failed
        self.message = message
    }
}

public struct TrashPlan: Sendable, Identifiable {
    public let id = UUID()
    public var title: String
    public var paths: [String]
    public var otherFamilies: [String]
    public var protectedCount: Int
    public var removedFamilies: [String]
    public var includesCopies: Bool
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

public struct ActivationEngine: Sendable {
    let locations: Locations
    let registrar: any FontRegistrar
    public var trash: @Sendable (URL) throws -> URL? = { url in
        var location: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &location)
        return location as URL?
    }
    public var trashAsAdministrator: @Sendable ([URL]) async -> Set<String> = { await AdministratorTrash.move($0) }
    public var fontLibrary: URL?
    public var installsIntoFontLibrary = false
    public var appFontFolders: [URL] = []
    public var confirmationWait: Duration = .seconds(2)
    public var forgetWait: Duration = .seconds(10)
    public var renameBackWait: Duration = .seconds(120)

    public init(locations: Locations, registrar: any FontRegistrar = CoreTextRegistrar()) {
        self.locations = locations
        self.registrar = registrar
    }

    @concurrent
    public func activate(_ faces: [LibraryFace], method: InstallMethod, records: ActivationRecords, movable: Set<String> = []) async -> ActivationResult {
        let signpost = Signposts.activation.beginInterval("Activate", "\(faces.count) faces")
        defer { Signposts.activation.endInterval("Activate", signpost) }
        var records = records
        followRenamedOrigins(of: faces, records: &records)
        var failed: [String] = []
        var toCopy: [(path: String, family: String)] = []
        var toRegister: [(path: String, record: Bool)] = []
        let targets = Self.uniqueByPath(faces.map { currentVersion(of: installedCopy(of: $0, records: records), records: records) })
            .filter(\.canActivate)
        Self.stopKeepingOff(targets.map(\.face.path))
        // A session registration of the same file would shadow the permanent one; one of a file in a Fonts folder ends only once the file is on there (below), as ending it first would take the file off macOS's list of fonts it has off, and leave it off.
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
        for path in toCopy.flatMap({ outdatedCopies(of: $0.path, records: records) }) where didTrash(Self.url(path)) {
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
        for copy in removed where isInInactiveFolder(copy.source) && !isInFontLibrary(copy.destination) {
            records.installedCopies[copy.destination] = nil
        }
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }

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
        let message = Self.message("Installed", "install", succeeded: installed.count, failed: failed.count,
                                   done: FontNames.describe(FontNames.fonts(inFiles: installed.map(\.destination))),
                                   undone: FontNames.describe(FontNames.fonts(inFiles: failed)))
        var result = ActivationResult(records: records, succeeded: installed.count, failed: failed, message: message)
        result.placed = Dictionary(installed.map { ($0.source, $0.destination) }, uniquingKeysWith: { first, _ in first })
        return result
    }

    @concurrent
    public func place(_ paths: [String], into folder: URL, named name: String, moving: Bool = false,
                      records: ActivationRecords) async -> ActivationResult {
        var failed: [String] = []
        var copies: [PlacedCopy] = []
        for path in Set(paths).sorted() {
            do {
                copies.append(try placeCopy(of: path, family: nil, into: folder))
            } catch {
                failed.append(path)
            }
        }
        if moving { removeOriginals(of: copies) }
        let message = Self.message(moving ? "Moved" : "Copied", moving ? "move" : "copy", succeeded: copies.count, failed: failed.count,
                                   done: FontNames.describe(FontNames.fonts(inFiles: copies.map(\.destination))),
                                   undone: FontNames.describe(FontNames.fonts(inFiles: failed)))
        var result = ActivationResult(records: records, succeeded: copies.count, failed: failed, message: message + " into “\(name)”")
        result.placed = Dictionary(copies.map { ($0.source, $0.destination) }, uniquingKeysWith: { first, _ in first })
        return result
    }

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

    @discardableResult
    private func removeOriginals(of copies: [PlacedCopy]) -> [PlacedCopy] {
        copies.filter { copy in
            // An original is deleted only once its copy has the same contents, so the font is never lost.
            !Self.isProtected(copy.source) && Self.isIdenticalCopy(copy.destination, of: copy.source)
                && (try? FileManager.default.removeItem(atPath: copy.source)) != nil
        }
    }

    @concurrent
    public func activateTemporarily(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        followRenamedOrigins(of: faces, records: &records)
        var failed: [String] = []
        var succeeded = 0
        var done = Set<String>()
        var toRegister: [String] = []
        let session = Self.currentSession()
        let targets = Self.uniqueByPath(faces.map { currentVersion(of: $0, records: records) })
        Self.stopKeepingOff(targets.map(\.face.path))
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

    @concurrent
    private func unregisterPersistent(_ paths: [String]) async -> Set<String> {
        let stuck = await registrar.unregister(paths.map(Self.url), scope: .persistent)
        return stuck.isEmpty ? stuck : await registrar.unregister(stuck.sorted().map(Self.url), scope: .session)
    }

    public func deactivate(_ faces: [LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var moved: [String: String] = [:]
        return await deactivate(faces, records: records, moved: &moved)
    }

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
        var listed: [String: Set<String>] = [:]
        for face in faces { listed[face.face.path, default: []].formUnion(face.otherCopies) }
        for face in Self.uniqueByPath(faces) {
            let path = face.face.path
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
                // Ending its session registration would take it off macOS's list of fonts it has off, and macOS would turn it on again later: it's turned off there, which ends the session registration too.
                inFontsFolder.append(path)
            case .inPlace, .otherApp:
                persistent.append(path)
            case .temporary:
                session.append(path)
            case .macOS, .allUsers, .app, .adobeFonts:
                locked.append(path)
            }
        }
        // Unregistered before they go to the Trash: turned off, they'd be on macOS's list of fonts it has off, which turns a new file of the same name there off too, until fontd notices the old one went.
        let spares = trashingCopies
            ? inFontsFolder.filter { records.temporary[$0] == nil && isSpareInstalledCopy($0, listed: listed[$0] ?? [], records: records) }
            : []
        var offThere = inFontsFolder.filter { !spares.contains($0) }
        if !spares.isEmpty {
            _ = await registrar.unregister(spares.map(Self.url), scope: .persistent)
            for path in spares {
                if didTrash(Self.url(path)) {
                    records.installedCopies[path] = nil
                    removeEmptyFolders(around: path)
                    succeeded += 1
                } else {
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
            let stuck = await unregisterPersistent(persistent)
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
            let stuck = await unregisterPersistent(persistent)
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

    public func spareCopiesTrashPlan(_ paths: [String], families: Set<String>, in library: Library) -> TrashPlan? {
        let allowed = paths.filter { !Self.isProtected($0) }
        guard !allowed.isEmpty else { return nil }
        let set = Set(allowed)
        let otherFamilies = library.families
            .filter { !families.contains($0.id) && $0.faces.contains { set.contains($0.face.path) || $0.otherCopies.contains(where: set.contains) } }
            .map(\.id)
        return TrashPlan(
            title: allowed.count == 1 ? "“\((allowed[0] as NSString).lastPathComponent)”" : "\(allowed.count) Files",
            paths: allowed, otherFamilies: otherFamilies, protectedCount: paths.count - allowed.count, removedFamilies: [],
            includesCopies: false, spareCopiesOf: library
        )
    }

    @concurrent
    public func moveToTrash(_ plan: TrashPlan, records: ActivationRecords) async -> ActivationResult {
        var records = records
        // Checked again right before trashing, as a copy may have gone since the plan was made.
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
        var inTrash: [String: String] = [:]
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
                if let location = try trash(Self.url(path)) { inTrash[path] = location.path }
                trashed(path)
            } catch CocoaError.fileWriteNoPermission where !Self.isLocked(path) {
                forbidden.append(path)
            } catch {
                failed.append(path)
            }
        }
        if !forbidden.isEmpty {
            let moved = await trashAsAdministrator(forbidden.map(Self.url))
            for path in forbidden {
                if moved.contains(path) { trashed(path) } else { failed.append(path) }
            }
        }
        let kept = persistent.filter(failed.contains)
        if !kept.isEmpty { _ = await registrar.register(kept.map(Self.url), scope: .persistent) }
        let keptSession = session.filter(failed.contains)
        if !keptSession.isEmpty {
            for path in await registerAndConfirm(keptSession, scope: .session) { records.temporary[path] = nil }
        }
        let message: String
        if failed.isEmpty {
            message = succeeded <= 1 ? "Moved to the Trash" : "Moved \(succeeded) files to the Trash"
        } else if succeeded == 0 {
            message = failed.count == 1 ? "Couldn’t move the file to the Trash" : "Couldn’t move \(failed.count) files to the Trash"
        } else {
            message = "Couldn’t move \(failed.count) of \(succeeded + failed.count) files to the Trash"
        }
        var result = ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
        result.trashed = inTrash
        return result
    }

    public enum PutBackProblem: Sendable, Equatable {
        case notInTrash
        case pathTaken
        case failed
    }

    public func putBack(_ trashed: [String: String], off: Set<String> = []) async -> (back: [String], problems: [String: PutBackProblem]) {
        let fm = FileManager.default
        var back: [String] = []
        var problems: [String: PutBackProblem] = [:]
        var offInFontsFolder: [String: String] = [:]
        for (path, location) in trashed.sorted(by: { $0.key < $1.key }) {
            guard Self.exists(location) else { problems[path] = .notInTrash; continue }
            guard !Self.exists(path) else { problems[path] = .pathTaken; continue }
            // macOS turns on whatever arrives in a Fonts folder, and turning a file off before macOS has it doesn't stick.
            if off.contains(path), isInsideFontsFolder(path) {
                offInFontsFolder[location] = path
                continue
            }
            do {
                try fm.createDirectory(at: Self.url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: Self.url(location), to: Self.url(path))
                back.append(path)
            } catch {
                problems[path] = .failed
            }
        }
        if !offInFontsFolder.isEmpty {
            let placed = await moveIntoFontsFolderOff(offInFontsFolder, exactly: true).placed
            for (location, path) in offInFontsFolder.sorted(by: { $0.value < $1.value }) {
                if placed[location] != nil { back.append(path) } else { problems[path] = .failed }
            }
        }
        return (back, problems)
    }

    func didTrash(_ url: URL) -> Bool {
        do {
            _ = try trash(url)
            return true
        } catch {
            return false
        }
    }

    @concurrent
    public func forgetInPlace(_ paths: [String], records: ActivationRecords) async -> ActivationRecords {
        var records = records
        _ = await registrar.unregister(paths.map(Self.url), scope: .persistent)
        records.inPlace.subtract(paths)
        return records
    }

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
            let stillOn = await endSessionRegistrations(leftovers)
            for path in leftovers where !stillOn.contains(path) || records.inPlace.contains(path) { records.temporary[path] = nil }
        }
        let stillOn = earlier.filter { isInsideFontsFolder($0) && registrar.isActive(Self.url($0)) }
        if !stillOn.isEmpty { _ = await registrar.setEnabled(stillOn.map(Self.url), false) }
        for path in earlier { records.temporary[path] = nil }
        return records
    }

    @concurrent
    public func registerAgain(_ records: ActivationRecords) async -> ActivationResult {
        func lost(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) && !registrar.isActive(Self.url(path)) }
        let persistent = records.inPlace.filter(lost).sorted()
        let session = records.temporary.keys.filter(lost).sorted()
        let failed = await registerAndConfirm(persistent, scope: .persistent).union(await registerAndConfirm(session, scope: .session))
        return ActivationResult(records: records, succeeded: persistent.count + session.count - failed.count, failed: failed.sorted(), message: "")
    }

    func endSessionRegistrations(_ paths: [String]) async -> Set<String> {
        // Unregistering a file in a Fonts folder would take it off macOS's list of fonts it has off, and macOS would turn it on again later.
        let inFontsFolders = paths.filter(isInsideFontsFolder)
        let elsewhere = paths.filter { !isInsideFontsFolder($0) }
        var stillOn = inFontsFolders.isEmpty ? [] : await registrar.setEnabled(inFontsFolders.map(Self.url), false)
        if !elsewhere.isEmpty { stillOn.formUnion(await registrar.unregister(elsewhere.map(Self.url), scope: .session)) }
        return stillOn
    }

    @concurrent
    public func tidyInactiveFolder(_ records: ActivationRecords) async -> (records: ActivationRecords, removed: Int) {
        var records = records
        var removed = 0
        let copiesOf = Dictionary(grouping: records.installedCopies.values, by: { $0 }).mapValues(\.count)
        for (copy, original) in records.installedCopies where isInInactiveFolder(original) && copiesOf[original] == 1 {
            // The original is deleted only once the copy has the same contents and no other copy was made from it.
            guard isInsideUserFonts(copy) || isInFontLibrary(copy), Self.isIdenticalCopy(copy, of: original),
                  (try? FileManager.default.removeItem(atPath: original)) != nil
            else { continue }
            if !isInFontLibrary(copy) { records.installedCopies[copy] = nil }
            removed += 1
        }
        return (records, removed)
    }

    public func endUntilQuit(_ records: ActivationRecords) -> ActivationRecords {
        var records = records
        let paths = records.temporary.filter { $0.value.scope == .untilQuit }.map(\.key)
        guard !paths.isEmpty else { return records }
        let inFontsFolders = paths.filter(isInsideFontsFolder)
        let elsewhere = paths.filter { !isInsideFontsFolder($0) }
        if !inFontsFolders.isEmpty { registrar.disableNow(inFontsFolders.map(Self.url)) }
        if !elsewhere.isEmpty { registrar.unregisterNow(elsewhere.map(Self.url), scope: .session) }
        for path in paths where records.inPlace.contains(path) || !registrar.isActive(Self.url(path)) { records.temporary[path] = nil }
        return records
    }

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

    public static func isProtected(_ path: String) -> Bool {
        ["/System/", "/Library/Application Support/Apple/", "/usr/", "/private/"].contains(where: path.hasPrefix)
            || path.contains(".app/") || ActiveSource.isAdobeFonts(path)
    }

    // MARK: Files

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: false)
    }

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

    func isInsideFontsFolder(_ path: String) -> Bool {
        isInsideUserFonts(path) || path.hasPrefix(locations.allUsersFonts.path + "/")
    }

    func registerAndConfirm(_ paths: [String], scope: CTFontManagerScope) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let signpost = Signposts.activation.beginInterval("Register", "\(paths.count) files")
        var stuck = await registrar.register(paths.map(Self.url), scope: scope)
        Signposts.activation.endInterval("Register", signpost)
        let confirming = Signposts.activation.beginInterval("Confirm")
        var pending = paths.filter { !stuck.contains($0) && !registrar.isActive(Self.url($0)) }
        // A file CoreText took without an error can show as on only a moment later.
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
        var isNew: Bool
    }

    private func placeCopy(of path: String, family: String?, into folder: URL? = nil, records: ActivationRecords? = nil) throws -> PlacedCopy {
        let fm = FileManager.default
        let source = Self.url(path)
        let folder = folder ?? installFolder(for: path, family: family)
        if let records, let earlier = earlierCopy(of: path, family: family, records: records) {
            return PlacedCopy(destination: earlier, source: path, isNew: false)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let first = folder.appendingPathComponent(name, isDirectory: false)
        if Self.isIdenticalCopy(first.path, of: path) {
            return PlacedCopy(destination: first.path, source: path, isNew: false)
        }
        // Copied into the staging folder first and then moved in, so macOS never sees a half-written file.
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
        if isInInactiveFolder(path), let added = Self.dateAdded(of: source) { Self.setDateAdded(added, of: destination) }
        return PlacedCopy(destination: destination.path, source: path, isNew: true)
    }

    private func earlierCopy(of path: String, family: String?, records: ActivationRecords) -> String? {
        let folder = installFolder(for: path, family: family).path
        return records.installedCopies.filter { copy, origin in
            origin == path && (copy as NSString).deletingLastPathComponent == folder && Self.isIdenticalCopy(copy, of: path)
        }.keys.min()
    }

    private func outdatedCopies(of path: String, records: ActivationRecords) -> [String] {
        let candidates = records.installedCopies.filter { copy, origin in
            origin == path && Self.hasChanged(path, since: copy) && !registrar.isActive(Self.url(copy))
        }.keys.sorted()
        // Not while the file can't be read: it can't be copied either, and its old copies would go with nothing in their place.
        guard !candidates.isEmpty, !FontFileReader.faces(atPath: path).isEmpty else { return [] }
        return candidates
    }

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

    private func currentVersion(of face: LibraryFace, records: ActivationRecords) -> LibraryFace {
        let path = face.face.path
        guard let origin = records.installedCopies[path], let file = face.copies.first(where: { $0.face.path == origin }),
              Self.hasChanged(origin, since: path), !registrar.isActive(Self.url(path))
        else { return face }
        return file.libraryFace
    }

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

    private static func hasChanged(_ original: String, since copy: String) -> Bool {
        var copyInfo = stat(), originalInfo = stat()
        guard stat(copy, &copyInfo) == 0, stat(original, &originalInfo) == 0,
              copyInfo.st_mode & S_IFMT == S_IFREG, originalInfo.st_mode & S_IFMT == S_IFREG,
              copyInfo.st_dev != originalInfo.st_dev || copyInfo.st_ino != originalInfo.st_ino,
              // Never a file only in iCloud Drive or Dropbox and not downloaded: reading it to compare would download it.
              (copyInfo.st_flags | originalInfo.st_flags) & UInt32(SF_DATALESS) == 0
        else { return false }
        return !isIdenticalCopy(copy, of: original)
    }

    private func moveOutOfAppFolder(_ path: String, records: inout ActivationRecords) throws {
        let destination = Self.uniqueURL(for: Self.url(path).lastPathComponent, in: try locations.inactiveFolderForNewFiles())
        AppFolderMoves.note(moved: destination.path, origin: path, support: locations.support)
        try Self.moveItem(Self.url(path), to: destination)
        records.appFolderOrigins[destination.path] = path
    }

    private func moveBackToAppFolder(_ path: String, records: inout ActivationRecords) throws -> String {
        guard let origin = records.appFolderOrigins[path] else { return path }
        let original = Self.url(origin)
        let destination = FileManager.default.fileExists(atPath: origin)
            ? Self.uniqueURL(for: original.lastPathComponent, in: original.deletingLastPathComponent())
            : original
        try Self.moveItem(Self.url(path), to: destination)
        records.appFolderOrigins[path] = nil
        return destination.path
    }

    private func isSpareInstalledCopy(_ path: String, listed: Set<String>, records: ActivationRecords) -> Bool {
        guard let origin = records.installedCopies[path] else { return false }
        return listed.contains(origin) && Self.isIdenticalCopy(path, of: origin)
    }

    public static func isIdenticalCopy(_ path: String, of original: String) -> Bool {
        var copy = stat(), source = stat()
        guard stat(path, &copy) == 0, stat(original, &source) == 0,
              copy.st_mode & S_IFMT == S_IFREG, source.st_mode & S_IFMT == S_IFREG,
              // The same file reached twice, by a symbolic or a hard link, is no copy: trashing one would lose the font.
              copy.st_dev != source.st_dev || copy.st_ino != source.st_ino,
              copy.st_size == source.st_size,
              // A file iCloud has taken off the Mac is never read, which would download it.
              (copy.st_flags | source.st_flags) & UInt32(SF_DATALESS) == 0
        else { return false }
        return FileManager.default.contentsEqual(atPath: path, andPath: original)
    }

    static func dateAdded(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    static func setDateAdded(_ date: Date, of url: URL) {
        var list = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: attrgroup_t(ATTR_CMN_ADDEDTIME),
                            volattr: 0, dirattr: 0, fileattr: 0, forkattr: 0)
        let seconds = date.timeIntervalSince1970.rounded(.down)
        var time = timespec(tv_sec: Int(seconds), tv_nsec: Int((date.timeIntervalSince1970 - seconds) * 1_000_000_000))
        _ = setattrlist(url.path, &list, &time, MemoryLayout<timespec>.size, 0)
    }

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

    private static func names(of faces: [LibraryFace], in paths: Set<String>) -> String? {
        FontNames.describe(faces.filter { paths.contains($0.face.path) })
    }
}
