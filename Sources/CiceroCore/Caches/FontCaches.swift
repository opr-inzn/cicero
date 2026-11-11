import Darwin
import Foundation

public enum SystemFontCaches {
    public enum Scope: Sendable {
        case currentUser
        case allUsers
    }

    public enum Failure: Error, Sendable {
        case cancelled
        case failed(String)
    }

    public static func clear(_ scope: Scope) async throws {
        switch scope {
        case .currentUser:
            let result = try await Process.run("/usr/bin/atsutil", ["databases", "-removeUser"])
            guard result.status == 0 else { throw Failure.failed(result.stderr) }
            _ = try? await Process.run("/usr/bin/killall", ["fontd"])
        case .allUsers:
            // Run in Cicero, not by osascript, so the password dialog names Cicero.
            let script = "do shell script \"/usr/bin/atsutil databases -remove; /usr/bin/killall fontd || true\" with prompt \"Cicero wants to clear the macOS font caches for all users.\" with administrator privileges"
            let error = await MainActor.run { () -> (number: Int?, message: String)? in
                var error: NSDictionary?
                guard let script = NSAppleScript(source: script) else { return (nil, "Couldn’t compile the script") }
                _ = script.executeAndReturnError(&error)
                return error.map { ($0[NSAppleScript.errorNumber] as? Int, $0[NSAppleScript.errorMessage] as? String ?? "") }
            }
            if let error {
                throw error.number == -128 ? Failure.cancelled : Failure.failed(error.message)
            }
        }
    }
}

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

        public var bundleIDs: Set<String> {
            switch self {
            case .adobe: ["com.adobe.InDesign", "com.adobe.illustrator", "com.adobe.Photoshop", "com.adobe.Acrobat.Pro", "com.adobe.Reader"]
            case .office: ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"]
            }
        }
    }

    public struct Found: Sendable {
        public var items: [URL]
        public var size: Int64

        public init(items: [URL], size: Int64) {
            self.items = items
            self.size = size
        }

        public var isEmpty: Bool { items.isEmpty }
    }

    // Only what these patterns match may ever be touched, and only by moving it to the Trash.
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
        // Looking in Office's app containers makes macOS ask whether Cicero may access other apps' data, so the sheet looks only when the user chooses Office.
        case .office: [
            "Library/Group Containers/UBF8T346G9.Office/FontCache",
            "Library/Containers/com.microsoft.{Word,Excel,Powerpoint,Outlook,onenote.mac}/Data/Library/Application Support/Microsoft/{FontCache,FontPreviewCache}",
        ]
        }
    }

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
        return Found(items: items, size: size)
    }

    public static func trash(_ found: Found, using trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Int {
        found.items.count { (try? trash($0)) == nil }
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

    static func run(_ path: String, _ arguments: [String]) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    // Read before waiting: a tool with more to say than a pipe holds waits until it's read.
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: Output(status: process.terminationStatus, stderr: String(decoding: data, as: UTF8.self)))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
