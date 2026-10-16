import Foundation

/// Moves files the user may not change to the Trash, once macOS has asked for an administrator's password, as the
/// Finder does: for a file in a folder an installer made, like Adobe's Fonts folder, FileManager's `trashItem` only
/// reports that permission was denied.
enum AdministratorTrash {
    /// Returns the paths that went: none when the password was cancelled or wrong.
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
        // The file stays the user's in the Trash, so they can open it or put it back without a password.
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

    /// The file's name in the Trash, numbered when the Trash already has one by that name: "Telegraf-Bold 2.otf".
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

    /// A path as one shell word.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Text as an AppleScript string.
    private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
