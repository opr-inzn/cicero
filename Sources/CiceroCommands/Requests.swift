import CiceroCore
import Foundation

/// `Requests/` in Cicero's support folder: while Cicero is open (holding `AppLock`), the `cicero` command asks it there
/// to make a change, so one program at a time writes Cicero's data. A request goes from `<id>.request.json` (written
/// whole, then renamed into place) to `<id>.taken.json` when Cicero takes it, and Cicero answers in `<id>.reply.json`,
/// the answer in the contract's JSON. Taking and withdrawing are renames of the same file, so only one of them happens:
/// a request Cicero took is never made twice, and one it didn't is never made by both.
public enum Requests {
    public static func folder(support: URL) -> URL {
        support.appendingPathComponent("Requests", isDirectory: true)
    }

    /// How long Cicero has to take a request; after that the command waits as long as Cicero works on it.
    public static let takeWithin: Duration = .seconds(5)

    static func file(_ id: String, _ kind: String, in folder: URL) -> URL {
        folder.appendingPathComponent("\(id).\(kind).json", isDirectory: false)
    }

    // MARK: The command

    /// Sends the request to Cicero and returns its answer. Nil when Cicero quit before taking it: the request is
    /// withdrawn, and the caller makes the change itself. `busy` when Cicero is open but doesn't take it in time;
    /// `failed` when Cicero quits after taking it without answering.
    static func send(_ request: WriteRequest, support: URL) async throws -> JSON? {
        let folder = folder(support: support)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staged = folder.appendingPathComponent("\(id).staged", isDirectory: false)
        let waiting = file(id, "request", in: folder), taken = file(id, "taken", in: folder), reply = file(id, "reply", in: folder)
        do {
            try JSONEncoder().encode(request).write(to: staged, options: .atomic)
            try fm.moveItem(at: staged, to: waiting)
        } catch {
            try? fm.removeItem(at: staged)
            throw CommandError(.failed, "The change couldn’t be sent to Cicero (\(folder.path)).")
        }
        let start = ContinuousClock.now
        while true {
            if let answer = readReply(reply) {
                try? fm.removeItem(at: reply)
                try? fm.removeItem(at: taken)
                return answer
            }
            let open = AppLock.isHeld(support: support)
            if fm.fileExists(atPath: waiting.path) {
                if !open || ContinuousClock.now - start > takeWithin {
                    // Withdrawn, unless Cicero takes it at this moment: then its answer comes.
                    let withdrawn = folder.appendingPathComponent("\(id).withdrawn", isDirectory: false)
                    if (try? fm.moveItem(at: waiting, to: withdrawn)) != nil {
                        try? fm.removeItem(at: withdrawn)
                        if !open { return nil }
                        throw CommandError(.busy, "Cicero is open but didn’t take the change within \(takeWithin.components.seconds) seconds. Nothing changed. Try again in a moment.")
                    }
                }
            } else if !fm.fileExists(atPath: taken.path) {
                if let answer = readReply(reply) {
                    try? fm.removeItem(at: reply)
                    return answer
                }
                throw CommandError(.busy, "Cicero didn’t take the change in time. Nothing changed. Try again in a moment.")
            } else if !open {
                // Taken, and Cicero went away: an answer written just before is read once more.
                if let answer = readReply(reply) {
                    try? fm.removeItem(at: reply)
                    try? fm.removeItem(at: taken)
                    return answer
                }
                try? fm.removeItem(at: taken)
                throw CommandError(.failed, "Cicero quit before it said whether it made the change. Check with cicero status.")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func readReply(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return JSON(text: text)
    }

    // MARK: Cicero

    /// A request Cicero took: its id, and the request, nil when this version can't read it.
    public struct Taken: Sendable {
        public var id: String
        public var request: WriteRequest?
    }

    /// Takes the requests waiting, oldest first; one the command withdrew meanwhile is left out.
    public static func take(support: URL) -> [Taken] {
        let folder = folder(support: support)
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let waiting = names.filter { $0.hasSuffix(".request.json") }.map { folder.appendingPathComponent($0, isDirectory: false) }
        let dated = waiting.map { url in
            (url, (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date ?? .distantPast)
        }
        let late = Date.now.addingTimeInterval(-Double(takeWithin.components.seconds) - 5)
        return dated.sorted { $0.1 < $1.1 }.compactMap { url, date in
            let id = String(url.lastPathComponent.dropLast(".request.json".count))
            // Its command would have withdrawn it by now, unless it was stopped: a change the user cancelled must never be made.
            if date < late {
                try? fm.removeItem(at: url)
                return nil
            }
            let taken = file(id, "taken", in: folder)
            guard (try? fm.moveItem(at: url, to: taken)) != nil else { return nil }
            let request = (try? Data(contentsOf: taken)).flatMap { try? JSONDecoder().decode(WriteRequest.self, from: $0) }
            return Taken(id: id, request: request)
        }
    }

    /// Answers a request Cicero took.
    public static func reply(_ answer: JSON, to id: String, support: URL) {
        let folder = folder(support: support)
        let staged = folder.appendingPathComponent("\(id).reply.staged", isDirectory: false)
        do {
            try Data(answer.text().utf8).write(to: staged, options: .atomic)
            try FileManager.default.moveItem(at: staged, to: file(id, "reply", in: folder))
        } catch {
            try? FileManager.default.removeItem(at: staged)
        }
    }

    /// The answer to a request this version can't read, as from a newer `cicero` command.
    public static var unreadable: JSON {
        CommandError(.failed, "This version of Cicero can’t read the change. Update Cicero.").json
    }

    /// Takes away what's left of requests whose command stopped before reading the answer, older than an hour.
    public static func tidy(support: URL) {
        let folder = folder(support: support)
        let fm = FileManager.default
        let hourAgo = Date.now.addingTimeInterval(-3600)
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasSuffix(".taken.json") {
            let id = String(name.dropLast(".taken.json".count))
            guard !names.contains("\(id).reply.json") else { continue }
            reply(CommandError(.failed, "Cicero quit before it said whether it made the change. Check with cicero status.").json, to: id, support: support)
        }
        for name in names where !name.hasSuffix(".request.json") {
            let url = folder.appendingPathComponent(name, isDirectory: false)
            if let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, date < hourAgo {
                try? fm.removeItem(at: url)
            }
        }
    }
}
