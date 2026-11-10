import AppKit
import CiceroCore
import Foundation

@MainActor
public enum WriteDispatcher {
    static let startingCicero: TimeInterval = 15
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
            if runningApp(environment) != nil, AppLock.holder(support: support) != .command {
                guard let answer = try await Requests.send(request, support: support) else { continue }
                if let error = CommandError(answer: answer) { throw error }
                return answer
            }
            guard let lock = await AppLock.wait(support: support, timeout: otherCommand) else {
                throw CommandError(.busy, "The Cicero CLI is making another change. Nothing changed. Try again in a moment.")
            }
            lock.release()
        }
    }

    static func runningApp(_ environment: ToolEnvironment) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: environment.appBundleID).first {
            // Asked of the process too: without a run loop, the command's list of running apps isn't told when one quits.
            !$0.isTerminated && kill($0.processIdentifier, 0) == 0
        }
    }

    private static func closed(_ request: WriteRequest, environment: ToolEnvironment) async throws -> JSON {
        if try LibraryContext.loadUserData(environment).isFromNewerVersion { throw CommandError(.failed, UserData.newerVersionMessage) }
        try repairIfNeeded(environment)
        let context = request.command.needsLibrary
            ? try await LibraryContext.load(environment, rescan: request.command.activates, shown: request.shown)
            : LibraryContext(library: .empty, data: try LibraryContext.loadUserData(environment), shown: request.shown, environment: environment)
        let writer = ClosedAppWriter(environment: environment, data: context.savedData)
        let answer = try await WriteRunner.run(request, in: context, writer: writer)
        if writer.activated { _ = try? await LibraryContext.load(environment, rescan: true) }
        if writer.saveFailed {
            throw CommandError(.failed, "The change couldn’t be saved in \(environment.locations.support.appendingPathComponent("user-data.json").path). Check that the disk has space and can be written to.")
        }
        return answer
    }
}

extension WriteDispatcher {
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

@MainActor
final class ClosedAppWriter: Writer {
    let environment: ToolEnvironment
    private let store: UserDataStore
    private(set) var data: UserData
    private(set) var activated = false
    private(set) var saveFailed = false

    init(environment: ToolEnvironment, data: UserData) {
        self.environment = environment
        self.data = data
        store = UserDataStore(locations: environment.locations)
    }

    var isApp: Bool { false }

    func update(_ change: (inout UserData) -> Void) {
        change(&data)
        store.save(data)
        if !store.flush(durably: true) { saveFailed = true }
    }

    private var engine: ActivationEngine {
        var engine = ActivationEngine(locations: environment.locations, registrar: environment.registrar)
        engine.fontLibrary = data.fontLibrary?.url
        engine.installsIntoFontLibrary = data.installsIntoFontLibrary
        return engine
    }

    func activate(_ faces: [LibraryFace], untilQuit: Bool, title: String) async -> ActivationResult {
        guard begin(faces, turningOn: true) else { return unjournaled(faces) }
        let result = await engine.activate(faces, method: .inPlace, records: data.records)
        finish(result)
        return result
    }

    func deactivate(_ faces: [LibraryFace]) async -> ActivationResult {
        guard begin(faces, turningOn: false) else { return unjournaled(faces) }
        let result = await engine.deactivate(faces, records: data.records)
        finish(result)
        return result
    }

    func rescan() async {
        _ = try? await LibraryContext.load(environment, rescan: true)
    }

    // Nothing turns without the note: a command stopped halfway would leave changes the records never learn of.
    private func unjournaled(_ faces: [LibraryFace]) -> ActivationResult {
        ActivationResult(records: data.records, succeeded: 0, failed: faces.map(\.face.path),
                         message: "Couldn’t write a note in \(environment.locations.support.path) before the change, so nothing changed. Check that the disk has space and can be written to.")
    }

    private func begin(_ faces: [LibraryFace], turningOn: Bool) -> Bool {
        let journal = ActivationJournal(turningOn: turningOn, paths: faces.map(\.face.path))
        return (try? journal.write(support: environment.locations.support)) != nil
    }

    private func finish(_ result: ActivationResult) {
        activated = true
        if ProcessInfo.processInfo.environment["CICERO_STOP_BEFORE_RECORDS"] == "1" { exit(9) }
        update { data in
            data.records = result.records
            data.forgetInstalledAddedFiles()
        }
        // Kept when the records couldn't be saved, so the next program to hold the lock repairs them.
        if !saveFailed { ActivationJournal.remove(support: environment.locations.support) }
    }
}
