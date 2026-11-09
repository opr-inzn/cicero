import Foundation

nonisolated enum TabCompletion {
    static let line = "autoload -Uz compinit && compinit -i"
    static let comment = "# Tab completion in Terminal, turned on by Cicero"

    struct State: Equatable {
        var isOn: Bool
        var file: URL
    }

    static let timeout: Duration = .seconds(10)

    @concurrent
    static func state() async -> State? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        let shellPath = String(cString: shell)
        guard URL(fileURLWithPath: shellPath).lastPathComponent == "zsh" else { return nil }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cicero-zsh-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-i", "-c", #"print -r -- "@@cicero-zdotdir ${ZDOTDIR:-$HOME}"; print -r -- "@@cicero-compdef $(whence -w compdef)""#]
        // The home folder Cicero has (a test copy's fake one too), never another; ZDOTDIR as the user's files set it.
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        environment["ZDOTDIR"] = nil
        environment["TERM"] = "dumb"
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now > deadline {
                process.terminate()
                return nil
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? handle.close()
        let lines = (try? String(contentsOf: output, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        guard let folder = lines.last(where: { $0.hasPrefix("@@cicero-zdotdir ") })?.dropFirst("@@cicero-zdotdir ".count),
              let compdef = lines.last(where: { $0.hasPrefix("@@cicero-compdef ") }) else { return nil }
        return State(isOn: compdef.hasSuffix(": function"),
                     file: URL(fileURLWithPath: String(folder), isDirectory: true).appendingPathComponent(".zshrc"))
    }

    static func hasLine(_ file: URL) -> Bool {
        (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").contains { $0 == line } ?? false
    }

    @concurrent
    static func turnOn(_ file: URL) async -> Bool {
        let fm = FileManager.default
        let existing = (try? Data(contentsOf: file)) ?? Data()
        var text = existing.isEmpty ? "" : (existing.last == UInt8(ascii: "\n") ? "\n" : "\n\n")
        text += comment + "\n" + line + "\n"
        if fm.fileExists(atPath: file.path) {
            // Appended in place, never written anew, which would put a file in place of a .zshrc that links into the user's dotfiles.
            guard let handle = try? FileHandle(forWritingTo: file) else { return false }
            defer { try? handle.close() }
            guard (try? handle.seekToEnd()) != nil, (try? handle.write(contentsOf: Data(text.utf8))) != nil else { return false }
        } else {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o644]) else { return false }
        }
        return await state()?.isOn == true
    }
}
