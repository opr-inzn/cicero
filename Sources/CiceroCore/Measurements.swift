// Only in the app performance runs' builds (Tests/E2E/app-perf/build-perf-app.sh, `-D CICERO_MEASURE`): a release
// has none of this, and scripts/build-app.sh refuses a binary that does.
#if CICERO_MEASURE
import Foundation
import os
import Synchronization

public enum Measurements {
    public static let signposter = OSSignposter(subsystem: "com.maximilianinzinger.Cicero", category: "App")

    public static var isRecording: Bool { sink != nil }

    public static func record(_ name: String, ms: Double, detail: String = "") {
        sink?.write(name: name, ms: ms, detail: detail)
    }

    public static func count(_ name: String, detail: String = "") {
        sink?.write(name: name, ms: nil, detail: detail)
    }

    @discardableResult
    public static func time<T>(_ name: StaticString, detail: @autoclosure () -> String = "", _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        guard isRecording else { return try body() }
        let start = ContinuousClock.now
        let result = try body()
        record("\(name)", ms: (ContinuousClock.now - start).milliseconds, detail: detail())
        return result
    }

    public struct Interval {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant

        public func end(detail: @autoclosure () -> String = "") {
            signposter.endInterval(name, state)
            if isRecording { record("\(name)", ms: (ContinuousClock.now - start).milliseconds, detail: detail()) }
        }
    }

    public static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name), start: .now)
    }

    public static var sinceProcessStart: Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        return Double(now.tv_sec - start.tv_sec) * 1000 + Double(now.tv_usec - start.tv_usec) / 1000
    }

    public static func flush() { sink?.flush() }

    public static func watchMainThread() {
        guard isRecording, !watching.exchange(true, ordering: .relaxed) else { return }
        let thread = Thread {
            while true {
                let answered = DispatchSemaphore(value: 0)
                let sent = ContinuousClock.now
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 0.25) == .timedOut {
                    answered.wait()
                    record("hang", ms: (ContinuousClock.now - sent).milliseconds)
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "Cicero main-thread watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static let watching = Atomic<Bool>(false)
    private static let sink: Sink? = ProcessInfo.processInfo.environment["CICERO_MEASURE"].flatMap { $0.isEmpty ? nil : Sink(path: $0) }

    private final class Sink: Sendable {
        private let handle: FileHandle
        private let pending = Mutex<[String]>([])

        init?(path: String) {
            // Appended to: the run's script writes its first line before the app starts.
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
            handle.seekToEndOfFile()
            self.handle = handle
        }

        func write(name: String, ms: Double?, detail: String) {
            var object: [String: Any] = ["t": (Measurements.sinceProcessStart * 1000).rounded() / 1000, "name": name]
            if let ms { object["ms"] = (ms * 1000).rounded() / 1000 }
            if !detail.isEmpty { object["detail"] = detail }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else { return }
            let count = pending.withLock { lines in
                lines.append(line)
                return lines.count
            }
            if count >= 64 { flush() }
        }

        func flush() {
            pending.withLock { lines in
                guard !lines.isEmpty else { return }
                handle.write(Data((lines.joined(separator: "\n") + "\n").utf8))
                lines.removeAll()
            }
        }
    }
}

extension Duration {
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
#endif
