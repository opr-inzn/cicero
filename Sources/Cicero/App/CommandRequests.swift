import CiceroCommands
import CiceroCore
import Foundation

/// The changes the `cicero` command asks for while Cicero is open (Design B: one writer at a time). Cicero holds
/// `AppLock`, so the command puts each change in `Requests/` instead of writing Cicero's data itself; Cicero takes it,
/// makes it with the same functions as a click (so the window shows it at once, with a toast and Undo for fonts turned on
/// or off), saves, and answers in the contract's JSON. One request at a time, in the order they came.
final class CommandRequests {
    private let support: URL
    private weak var model: AppModel?
    private var source: DispatchSourceFileSystemObject?
    private var working = false
    private var lookAgain = false

    init(model: AppModel) {
        self.model = model
        support = model.locations.support
    }

    /// Watches the folder, and takes what's there already: requests sent while Cicero was starting.
    func start() {
        let folder = Requests.folder(support: support)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Requests.tidy(support: support)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.look() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        look()
    }

    /// As Cicero quits: requests not taken yet stay, and the command makes them itself once Cicero has let go of the lock.
    func stop() {
        source?.cancel()
        source = nil
    }

    private func look() {
        guard source != nil else { return }
        guard !working else { return lookAgain = true }
        let taken = Requests.take(support: support)
        guard !taken.isEmpty else { return }
        working = true
        Task {
            for request in taken { await answer(request) }
            working = false
            if lookAgain {
                lookAgain = false
                look()
            }
        }
    }

    private func answer(_ taken: Requests.Taken) async {
        guard let model else { return }
        let answer: JSON
        if let request = taken.request {
            // Names are looked up in the library this launch's first scan found, not in one saved before, or none.
            if request.command.needsLibrary {
                while !model.hasScanned, model.lastEndedScan == 0 { try? await Task.sleep(for: .milliseconds(100)) }
            }
            let environment = ToolEnvironment(locations: model.locations, defaults: .standard, resources: nil, registrar: CoreTextRegistrar())
            let context = LibraryContext(library: model.library, data: model.data, shown: request.shown, environment: environment)
            do {
                guard model.hasScanned || !request.command.needsLibrary else {
                    throw CommandError(.failed, "Cicero couldn’t read the library. Try again in a moment.")
                }
                answer = try await WriteRunner.run(request, in: context, writer: AppRequestWriter(model: model))
            } catch let error as CommandError {
                answer = error.json
            } catch {
                answer = CommandError(.failed, error.localizedDescription).json
            }
        } else {
            answer = Requests.unreadable
        }
        // On the disk before the answer, so the command's next read has it.
        let saved = model.store.flush()
        let failed = CommandError(answer: answer) != nil
        Requests.reply(saved || failed ? answer : CommandError(.failed, "Cicero made the change but couldn’t save it. Check that the disk has space and can be written to.").json,
                       to: taken.id, support: support)
    }
}

/// Cicero making a change the command asked for, as the same click would.
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

    func activate(_ faces: [LibraryFace], untilQuit: Bool, title: String) async -> ActivationResult {
        let operation = model.expect(faces, at: .on)
        return await withCheckedContinuation { continuation in
            model.enqueue { model in
                let result = untilQuit
                    ? await model.engine.activateTemporarily(faces, records: model.data.records)
                    : await model.engine.activate(faces, method: .inPlace, records: model.data.records)
                model.finish(result, operation: operation, undo: model.undo(turning: faces, on: false, failed: result.failed))
                continuation.resume(returning: result)
            }
        }
    }

    /// A scan of everything, as when Cicero becomes active, finished (or replaced by a later one that finished) before
    /// the answer, so the command reads what it found.
    func rescan() async {
        let id = model.rescan()
        while model.lastEndedScan < id { try? await Task.sleep(for: .milliseconds(100)) }
    }

    func deactivate(_ faces: [LibraryFace]) async -> ActivationResult {
        let operation = model.expect(faces, at: .off)
        return await withCheckedContinuation { continuation in
            model.enqueue { model in
                let result = await model.engine.deactivate(faces, records: model.data.records)
                model.finish(result, operation: operation, undo: model.undo(turning: faces, on: true, failed: result.failed))
                continuation.resume(returning: result)
            }
        }
    }
}
