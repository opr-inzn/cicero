import CiceroCore
import Foundation

public enum Requests {
    public static func folder(support: URL) -> URL {
        support.appendingPathComponent("Requests", isDirectory: true)
    }

    public static let takeWithin: Duration = .seconds(5)
    public static let whileStarting: TimeInterval = 30

    static func isStarting(support: URL) -> Bool {
        AppLock.appStarted(support: support).map { Date.now.timeIntervalSince($0) < whileStarting } ?? false
    }

    static func file(_ id: String, _ kind: String, in folder: URL) -> URL {
        folder.appendingPathComponent("\(id).\(kind).json", isDirectory: false)
    }

    // MARK: The command

    public struct Sender: Codable, Sendable, Equatable {
        var process: Int32
        var started: Int

        static var current: Sender? { started(getpid()).map { Sender(process: getpid(), started: $0) } }

        public var isRunning: Bool { Self.started(process) == started }

        private static func started(_ process: pid_t) -> Int? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, process]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == process,
                  info.kp_proc.p_stat != SZOMB else { return nil }
            let start = info.kp_proc.p_un.__p_starttime
            return start.tv_sec * 1_000_000 + Int(start.tv_usec)
        }
    }

    static func send(_ request: WriteRequest, support: URL) async throws -> JSON? {
        let folder = folder(support: support)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staged = folder.appendingPathComponent("\(id).staged", isDirectory: false)
        let waiting = file(id, "request", in: folder), taken = file(id, "taken", in: folder), reply = file(id, "reply", in: folder)
        let withdrawn = folder.appendingPathComponent("\(id).withdrawn", isDirectory: false)
        var request = request
        request.sender = .current
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
                if !open || ContinuousClock.now - start > takeWithin && !isStarting(support: support) && !isAnswering(besides: id, in: folder) {
                    if (try? fm.moveItem(at: waiting, to: withdrawn)) != nil {
                        try? fm.removeItem(at: withdrawn)
                        if !open { return nil }
                        let waited = (ContinuousClock.now - start).components.seconds
                        throw CommandError(.busy, "Cicero is open but didn’t take the change within \(waited) seconds. Nothing changed. Try again in a moment.")
                    }
                }
            } else if !fm.fileExists(atPath: taken.path), !fm.fileExists(atPath: waiting.path) {
                if let answer = readReply(reply) {
                    try? fm.removeItem(at: reply)
                    return answer
                }
                throw CommandError(.busy, "Cicero didn’t take the change in time. Nothing changed. Try again in a moment.")
            } else if !open {
                if let answer = readReply(reply) {
                    try? fm.removeItem(at: reply)
                    try? fm.removeItem(at: taken)
                    return answer
                }
                try? fm.removeItem(at: taken)
                throw CommandError(.failed, "Cicero quit before it said whether it made the change. Check with cicero status.")
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                if (try? fm.moveItem(at: waiting, to: withdrawn)) != nil { try? fm.removeItem(at: withdrawn) }
                throw error
            }
        }
    }

    private static func isAnswering(besides id: String, in folder: URL) -> Bool {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        return names.contains { name in
            name.hasSuffix(".taken.json") && !name.hasPrefix(id + ".") && !names.contains(name.dropLast(".taken.json".count) + ".reply.json")
        }
    }

    private static func readReply(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return JSON(text: text)
    }

    // MARK: Cicero

    public struct Taken: Sendable {
        public var id: String
        public var request: WriteRequest?
    }

    public static func take(support: URL) -> Taken? {
        let folder = folder(support: support)
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let waiting = names.filter { $0.hasSuffix(".request.json") }.map { folder.appendingPathComponent($0, isDirectory: false) }
        let dated = waiting.map { url in
            (url, (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date ?? .distantPast)
        }
        let late = Date.now.addingTimeInterval(-max(Double(takeWithin.components.seconds), whileStarting) - 5)
        for (url, date) in dated.sorted(by: { $0.1 < $1.1 }) {
            let id = String(url.lastPathComponent.dropLast(".request.json".count))
            let sender = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(WriteRequest.self, from: $0) }?.sender
            // A change the user cancelled must never be made: its command has stopped (Ctrl-C, a closed terminal or agent), or would have withdrawn it by now.
            if sender.map({ !$0.isRunning }) == true || date < late {
                try? fm.removeItem(at: url)
                continue
            }
            let taken = file(id, "taken", in: folder)
            // Taking and withdrawing are renames of the same file, so only one happens: a request is never made twice, nor by both Cicero and the command.
            guard (try? fm.moveItem(at: url, to: taken)) != nil else { continue }
            let request = (try? Data(contentsOf: taken)).flatMap { try? JSONDecoder().decode(WriteRequest.self, from: $0) }
            return Taken(id: id, request: request)
        }
        return nil
    }

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

    public static var unreadable: JSON {
        CommandError(.failed, "This version of Cicero can’t read the change. Update Cicero.").json
    }

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
