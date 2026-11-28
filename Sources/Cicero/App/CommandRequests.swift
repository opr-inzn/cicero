import CiceroCommands
import CiceroCore
import Foundation

final class CommandRequests {
    private let support: URL
    private weak var model: AppModel?
    private var source: DispatchSourceFileSystemObject?
    private var working = false

    var isAnswering: Bool { working }

    init(model: AppModel) {
        self.model = model
        support = model.locations.support
        Requests.tidy(support: support)
    }

    func start() {
        guard source == nil else { return }
        let folder = Requests.folder(support: support)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.look() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        look()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func look() {
        guard source != nil, !working, let taken = Requests.take(support: support) else { return }
        working = true
        let support = support
        // On the main actor, so a Cicero that hangs stops telling the command it's still at work.
        let beat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Requests.beat)
                guard !Task.isCancelled else { break }
                Requests.stillAnswering(taken.id, support: support)
            }
        }
        Task {
            await answer(taken)
            beat.cancel()
            working = false
            look()
        }
    }

    private func answer(_ taken: Requests.Taken) async {
        guard let model else { return }
        let answer: JSON
        if let request = taken.request {
            if request.command.needsLibrary {
                let deadline = ContinuousClock.now + .seconds(300)
                while !model.hasScanned, model.lastEndedScan == 0, ContinuousClock.now < deadline, source != nil,
                      request.sender?.isRunning != false {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let environment = ToolEnvironment(locations: model.locations, defaults: .standard, resources: nil, registrar: CoreTextRegistrar())
            func refuseIfNotWanted() throws {
                if let sender = request.sender, !sender.isRunning { throw CommandError(.failed, "The command stopped, so nothing changed.") }
                guard !model.store.isReadOnly || request.command == .rescan else { throw CommandError(.failed, model.store.readOnlyMessage) }
                // A restore replaces the setup with the backup's when it ends, and a change made meanwhile would be lost.
                guard model.job != .restoring || request.command == .rescan else {
                    throw CommandError(.busy, "Cicero is restoring a backup. Nothing changed. Try again when it’s done.")
                }
                guard model.hasScanned || !request.command.needsLibrary else {
                    throw model.lastEndedScan == 0 ? CommandError(.busy, "Cicero is still reading the library. Nothing changed. Try again in a moment.")
                        : CommandError(.failed, "Cicero couldn’t read the library. Try again in a moment.")
                }
            }
            do {
                try refuseIfNotWanted()
                let proofing = request.command.needsLibrary ? try await LibraryContext.scanForProofing(model.data, shown: request.shown, environment: environment) : nil
                let context = LibraryContext(library: proofing ?? model.library, data: model.data, shown: request.shown, environment: environment)
                // Asked again after the proofing scan: a change the user cancelled meanwhile must never be made.
                try refuseIfNotWanted()
                answer = try await WriteRunner.run(request, in: context, writer: AppRequestWriter(model: model))
            } catch let error as CommandError {
                answer = error.json
            } catch {
                answer = CommandError(.failed, error.localizedDescription).json
            }
        } else {
            answer = Requests.unreadable
        }
        let saved = model.store.flush()
        let failed = CommandError(answer: answer) != nil
        Requests.reply(saved || failed ? answer : CommandError(.failed, "Cicero made the change but couldn’t save it. Check that the disk has space and can be written to.").json,
                       to: taken.id, support: support)
    }
}

final class AppRequestWriter: Writer {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var data: UserData { model.data }
    var isApp: Bool { true }

    func renameTag(_ old: String, to new: String) { model.renameTag(old, to: new) }
    func deleteTags(_ names: Set<String>) { model.deleteTags(names) }
    func renameFolder(_ id: UUID, to name: String) { model.renameSet(id, to: name) }
    func deleteFolders(_ ids: Set<UUID>) { model.deleteSets(ids) }

    func update(_ change: (inout UserData) -> Void) {
        var data = model.data
        change(&data)
        model.data = data
    }

    func activate(_ faces: [LibraryFace], untilQuit: Bool) async throws -> ActivationResult {
        try await withCheckedThrowingContinuation { continuation in
            let queued = model.enqueue { model in
                let operation = model.expect(faces, at: .on)
                let result = untilQuit
                    ? await model.engine.activateTemporarily(faces, records: model.data.records)
                    : await model.engine.activate(faces, method: .inPlace, records: model.data.records)
                model.finish(result, operation: operation, undo: model.undo(restoring: faces, failed: result.failed))
                continuation.resume(returning: result)
            }
            if !queued { continuation.resume(throwing: CommandError(.failed, model.store.readOnlyMessage)) }
        }
    }

    func rescan() async {
        let id = model.rescan()
        while model.lastEndedScan < id { try? await Task.sleep(for: .milliseconds(100)) }
    }

    func deactivate(_ faces: [LibraryFace]) async throws -> ActivationResult {
        try await withCheckedThrowingContinuation { continuation in
            let queued = model.enqueue { model in
                let operation = model.expect(faces, at: .off)
                let result = await model.engine.deactivate(faces, records: model.data.records)
                model.finish(result, operation: operation, undo: model.undo(restoring: faces, failed: result.failed))
                continuation.resume(returning: result)
            }
            if !queued { continuation.resume(throwing: CommandError(.failed, model.store.readOnlyMessage)) }
        }
    }
}
