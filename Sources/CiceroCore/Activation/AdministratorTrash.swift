import Foundation

enum AdministratorTrash {
    @concurrent
    static func move(_ urls: [URL]) async -> Set<String> {
        let fm = FileManager.default
        var taken = Set<String>()
        var moves: [(source: String, destination: String)] = []
        for url in urls {
            guard let trash = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false) else { continue }
            moves.append((url.path, destination(for: url, in: trash, taken: &taken)))
        }
        guard !moves.isEmpty else { return [] }
        let user = getuid()
        let script = moves.map { "/bin/mv -n \(quoted($0.source)) \(quoted($0.destination)) && /usr/sbin/chown \(user) \(quoted($0.destination))" }
            .joined(separator: "; ")
        let prompt = moves.count == 1
            ? "Cicero wants to move “\((moves[0].source as NSString).lastPathComponent)” to the Trash."
            : "Cicero wants to move \(moves.count) files to the Trash."
        let source = "do shell script \(literal(script)) with prompt \(literal(prompt)) with administrator privileges"
        await MainActor.run {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
        return Set(moves.filter { !fm.fileExists(atPath: $0.source) && fm.fileExists(atPath: $0.destination) }.map(\.source))
    }

    private static func destination(for url: URL, in trash: URL, taken: inout Set<String>) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        var candidate = trash.appendingPathComponent(url.lastPathComponent).path
        var number = 2
        while taken.contains(candidate) || FileManager.default.fileExists(atPath: candidate) {
            candidate = trash.appendingPathComponent("\(name) \(number)\(suffix)").path
            number += 1
        }
        taken.insert(candidate)
        return candidate
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
