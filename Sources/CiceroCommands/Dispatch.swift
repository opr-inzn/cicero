import AppKit
import CiceroCore
import Foundation

/// Makes a change the one way it may be made now (Design B): while Cicero is open, Cicero makes it (`Requests`); while
/// it's closed, the command makes it itself, holding `AppLock` so a Cicero that starts meanwhile waits for it.
@MainActor
public enum WriteDispatcher {
    /// How long a Cicero that's open may leave the lock free before the command takes it for one that can't (a
    /// version from before the command could write). A Cicero that's starting, or that waited for another command,
    /// takes it within moments.
    static let startingCicero: TimeInterval = 15
    /// How long the command waits for another `cicero` command's change.
    static let otherCommand: Duration = .seconds(60)

    public static func perform(_ request: WriteRequest, environment: ToolEnvironment) async throws -> JSON {
        let support = environment.locations.support
        var freeSince: Date?
        while true {
            if let lock = AppLock.take(support: support) {
                guard runningApp(environment) != nil else {
                    defer { lock.release() }
                    return try await closed(request, environment: environment)
                }
                lock.release()
                let since = freeSince ?? .now
                if Date.now.timeIntervalSince(since) > startingCicero {
                    throw CommandError(.failed, "This version of Cicero doesn’t take changes from the Cicero CLI. Update Cicero, or quit it to make the change from here.")
                }
                freeSince = since
                try await Task.sleep(for: .milliseconds(200))
                continue
            }
            freeSince = nil
            if runningApp(environment) != nil {
                guard let answer = try await Requests.send(request, support: support) else { continue }
                if let error = CommandError(answer: answer) { throw error }
                return answer
            }
            // Another cicero command is making a change.
            guard let lock = AppLock.wait(support: support, timeout: otherCommand) else {
                throw CommandError(.busy, "The Cicero CLI is making another change. Nothing changed. Try again in a moment.")
            }
            lock.release()
        }
    }

    /// Asked of the process itself too: without a run loop, the command's list of running apps isn't told when one quits.
    static func runningApp(_ environment: ToolEnvironment) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: environment.appBundleID).first {
            !$0.isTerminated && kill($0.processIdentifier, 0) == 0
        }
    }

    /// With Cicero closed and the lock held: the library scanned first when fonts turn on or off, so the files are where
    /// the change finds them, and again after, so the saved library has what changed.
    private static func closed(_ request: WriteRequest, environment: ToolEnvironment) async throws -> JSON {
        try repairIfNeeded(environment)
        let context = request.command.needsLibrary
            ? try await LibraryContext.load(environment, rescan: request.command.activates, shown: request.shown)
            : LibraryContext(library: .empty, data: try LibraryContext.loadUserData(environment), shown: request.shown, environment: environment)
        let writer = ClosedAppWriter(environment: environment, data: context.savedData)
        let answer = try await WriteRunner.run(request, in: context, writer: writer)
        if writer.activated { _ = try? await LibraryContext.load(environment, rescan: true) }
        return answer
    }
}

extension WriteDispatcher {
    /// Repairs the records after a command that stopped while it turned fonts on or off (see `ActivationJournal`), with
    /// the lock held.
    static func repairIfNeeded(_ environment: ToolEnvironment) throws {
        let support = environment.locations.support
        guard let journal = ActivationJournal.read(support: support) else { return }
        var data = try LibraryContext.loadUserData(environment)
        data.records = journal.repair(data.records, registrar: environment.registrar, locations: environment.locations)
        let store = UserDataStore(locations: environment.locations)
        store.save(data)
        if store.flush(durably: true) { ActivationJournal.remove(support: support) }
    }
}

/// Makes changes while Cicero is closed, as Cicero would: user-data.json written as `UserDataStore` writes it, at once
/// and onto the disk, and fonts turned on and off with the same `ActivationEngine`.
@MainActor
final class ClosedAppWriter: Writer {
    let environment: ToolEnvironment
    private let store: UserDataStore
    private(set) var data: UserData
    /// Whether fonts turned on or off.
    private(set) var activated = false

    init(environment: ToolEnvironment, data: UserData) {
        self.environment = environment
        self.data = data
        store = UserDataStore(locations: environment.locations)
    }

    var isApp: Bool { false }

    func update(_ change: (inout UserData) -> Void) {
        change(&data)
        store.save(data)
        store.flush(durably: true)
    }

    /// As the app has it (`AppModel.engine`).
    private var engine: ActivationEngine {
        var engine = ActivationEngine(locations: environment.locations, registrar: environment.registrar)
        engine.fontLibrary = data.fontLibrary?.url
        engine.installsIntoFontLibrary = data.installsIntoFontLibrary
        return engine
    }

    func activate(_ faces: [LibraryFace], untilQuit: Bool, title: String) async -> ActivationResult {
        let journal = begin(faces, turningOn: true)
        let result = await engine.activate(faces, method: .inPlace, records: data.records)
        finish(result, journal: journal)
        return result
    }

    func deactivate(_ faces: [LibraryFace]) async -> ActivationResult {
        let journal = begin(faces, turningOn: false)
        let result = await engine.deactivate(faces, records: data.records)
        finish(result, journal: journal)
        return result
    }

    func rescan() async {
        _ = try? await LibraryContext.load(environment, rescan: true)
    }

    /// What's about to turn, written down first (see `ActivationJournal`); false when it couldn't be.
    private func begin(_ faces: [LibraryFace], turningOn: Bool) -> Bool {
        let journal = ActivationJournal(turningOn: turningOn, paths: faces.map(\.face.path))
        return (try? journal.write(support: environment.locations.support)) != nil
    }

    /// As the app's `finish`: the records saved, and added files a copy was installed of forgotten; then the journal goes.
    private func finish(_ result: ActivationResult, journal: Bool) {
        activated = true
        // For the end-to-end test of a command that stops here, before the records are saved.
        if ProcessInfo.processInfo.environment["CICERO_STOP_BEFORE_RECORDS"] == "1" { exit(9) }
        update { data in
            data.records = result.records
            data.forgetInstalledAddedFiles()
        }
        if journal { ActivationJournal.remove(support: environment.locations.support) }
    }
}
