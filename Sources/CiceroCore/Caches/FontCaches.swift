import Darwin
import Foundation

/// The font caches macOS keeps.
public enum SystemFontCaches {
    public enum Scope: Sendable {
        case currentUser
        /// Needs an administrator; macOS asks for the password itself.
        case allUsers
    }

    public enum Failure: Error, Sendable {
        case cancelled
        case failed(String)
    }

    /// Removes the caches and restarts the font service, which rebuilds them on demand.
    public static func clear(_ scope: Scope) async throws {
        switch scope {
        case .currentUser:
            let result = try await Process.run("/usr/bin/atsutil", ["databases", "-removeUser"])
            guard result.status == 0 else { throw Failure.failed(result.stderr) }
            // fontd may not be running; it starts again on demand either way.
            _ = try? await Process.run("/usr/bin/killall", ["fontd"])
        case .allUsers:
            let script = "do shell script \"/usr/bin/atsutil databases -remove; /usr/bin/killall fontd || true\" with administrator privileges"
            let result = try await Process.run("/usr/bin/osascript", ["-e", script])
            guard result.status == 0 else {
                throw result.stderr.contains("-128") ? Failure.cancelled : Failure.failed(result.stderr)
            }
        }
    }
}

/// Font caches other apps keep and rebuild the next time they open. Only the files and folders
/// matched here are ever touched, and only ever moved to the Trash.
public enum AppFontCaches {
    public enum App: String, CaseIterable, Identifiable, Sendable {
        case adobe, office

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .adobe: "Adobe apps"
            case .office: "Microsoft Office"
            }
        }

        /// Apps that read these caches and must be quit first.
        public var bundleIDs: Set<String> {
            switch self {
            case .adobe: ["com.adobe.InDesign", "com.adobe.illustrator", "com.adobe.Photoshop", "com.adobe.Acrobat.Pro", "com.adobe.Reader"]
            case .office: ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"]
            }
        }

        /// Office keeps its caches inside its app containers. Looking there makes macOS ask whether
        /// Cicero may access other apps' data, so only look when the user chooses to clear them.
        public var isGuardedByMacOS: Bool { self == .office }
    }

    public struct Found: Sendable {
        public var app: App
        public var items: [URL]
        public var size: Int64

        public init(app: App, items: [URL], size: Int64) {
            self.app = app
            self.items = items
            self.size = size
        }

        public var isEmpty: Bool { items.isEmpty }
    }

    /// Where each app keeps its caches, relative to the home folder (glob patterns, braces allowed).
    static func patterns(for app: App) -> [String] {
        switch app {
        case .adobe: [
            "Library/Caches/Adobe/TypeSupport/AdobeFnt*.lst",
            "Library/Caches/Adobe/Fonts/AdobeFnt*.lst",
            "Library/Caches/Adobe InDesign/Version */*/TypeSupport/AdobeFnt*.lst",
            "Library/Caches/Adobe InDesign/Version */*/FontMaskCache",
            "Library/Preferences/Adobe Illustrator * Settings/*/AdobeFnt*.lst",
            "Library/Preferences/AIRobin * Settings/*/AdobeFnt*.lst",
            "Library/Preferences/AIRobin * Settings/*/AIRobin/AdobeFnt*.lst",
            "Library/Application Support/Adobe/Adobe Photoshop */CT Font Cache",
            "Library/Application Support/Adobe/Acrobat/DC/Adobe{Sys,Com,CMap}Fnt*.lst",
            // Acrobat names these with a literal backslash.
            "Library/Application Support/Adobe/Acrobat/DC/ProtectedView\\\\Adobe{Sys,Com,CMap}Fnt*.lst",
        ]
        case .office: [
            "Library/Group Containers/UBF8T346G9.Office/FontCache",
            "Library/Containers/com.microsoft.{Word,Excel,Powerpoint,Outlook,onenote.mac}/Data/Library/Application Support/Microsoft/{FontCache,FontPreviewCache}",
        ]
        }
    }

    /// What exists for `app`, with its size. Walks folders; call off the main thread.
    public static func find(_ app: App) -> Found {
        find(app, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func find(_ app: App, home: URL) -> Found {
        var items: [URL] = []
        for pattern in patterns(for: app) {
            for path in glob(escapingGlobCharacters(home.path) + "/" + pattern) {
                items.append(URL(fileURLWithPath: path))
            }
        }
        let size = items.reduce(Int64(0)) { $0 + allocatedSize(of: $1) }
        return Found(app: app, items: items, size: size)
    }

    /// Moves every found item to the Trash; returns how many couldn't be moved.
    public static func trash(_ found: Found) -> Int {
        found.items.count { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) == nil }
    }

    private static func glob(_ pattern: String) -> [String] {
        var results = glob_t()
        defer { globfree(&results) }
        guard Darwin.glob(pattern, GLOB_BRACE | GLOB_NOSORT, nil, &results) == 0 else { return [] }
        return (0..<Int(results.gl_matchc)).compactMap { index in
            results.gl_pathv[index].map { String(cString: $0) }
        }
    }

    private static func escapingGlobCharacters(_ path: String) -> String {
        var escaped = ""
        for character in path {
            if "*?[]{}\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// Bytes on disk of a file, or of everything inside a folder. Symbolic links count as themselves.
    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func size(_ url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true, values.isSymbolicLink != true else { return size(url) }
        var total = size(url)
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let child as URL in enumerator { total += size(child) }
        }
        return total
    }
}

extension Process {
    struct Output: Sendable {
        var status: Int32
        var stderr: String
    }

    /// Runs a tool to completion without blocking the caller.
    static func run(_ path: String, _ arguments: [String]) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Output(status: process.terminationStatus, stderr: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
