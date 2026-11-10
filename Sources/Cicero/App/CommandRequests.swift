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
    }

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

    func stop() {
        source?.cancel()
        source = nil
    }

    private func look() {
        guard source != nil, !working, let taken = Requests.take(support: support) else { return }
        working = true
        Task {
            await answer(taken)
            working = false
            look()
        }
    }

    private func answer(_ taken: Requests.Taken) async {
        guard let model else { return }
        let answer: JSON
        if let request = taken.request {
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
