import AppKit

/// Font caches other apps keep and rebuild the next time they open. Only the files and folders
/// matched below are ever touched, and they only ever go to the Trash.
enum AppFontCaches {
    enum App: String, CaseIterable, Identifiable, Sendable {
        case adobe, office

        var id: String { rawValue }

        var title: String {
            switch self {
            case .adobe: "Adobe apps"
            case .office: "Microsoft Office"
            }
        }

        /// The apps that read these caches; they have to be quit before clearing.
        var bundleIDs: Set<String> {
            switch self {
            case .adobe:
                ["com.adobe.InDesign", "com.adobe.illustrator", "com.adobe.Photoshop", "com.adobe.Acrobat.Pro", "com.adobe.Reader"]
            case .office:
                ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"]
            }
        }

        /// Glob patterns, relative to the home folder, of the caches each app family keeps. Adobe's
        /// AdobeFnt*.lst font lists are rebuilt by the app that owns them the next time it starts.
        var patterns: [String] {
            switch self {
            case .adobe:
                [
                    "Library/Caches/Adobe/TypeSupport/AdobeFnt*.lst",
                    "Library/Caches/Adobe/Fonts/AdobeFnt*.lst",
                    "Library/Caches/Adobe InDesign/Version */*/TypeSupport/AdobeFnt*.lst",
                    "Library/Caches/Adobe InDesign/Version */*/FontMaskCache",
                    // Illustrator's settings folder is named AIRobin in its beta builds.
                    "Library/Preferences/Adobe Illustrator * Settings/*/AdobeFnt*.lst",
                    "Library/Preferences/AIRobin * Settings/*/AdobeFnt*.lst",
                    "Library/Preferences/AIRobin * Settings/*/AIRobin/AdobeFnt*.lst",
                    "Library/Application Support/Adobe/Adobe Photoshop */CT Font Cache",
                    "Library/Application Support/Adobe/Acrobat/DC/Adobe{Sys,Com,CMap}Fnt*.lst",
                    "Library/Application Support/Adobe/Acrobat/DC/ProtectedView\\\\Adobe{Sys,Com,CMap}Fnt*.lst",
                ]
            case .office:
                [
                    "Library/Group Containers/UBF8T346G9.Office/FontCache",
                    "Library/Containers/com.microsoft.{Word,Excel,Powerpoint,Outlook,onenote.mac}/Data/Library/Application Support/Microsoft/FontCache",
                    "Library/Containers/com.microsoft.{Word,Excel,Powerpoint,Outlook,onenote.mac}/Data/Library/Application Support/Microsoft/FontPreviewCache",
                ]
            }
        }
    }

    struct Found: Sendable {
        var app: App
        var items: [URL] = []
        var size: Int64 = 0

        var isEmpty: Bool { items.isEmpty }

        var summary: String {
            if isEmpty { return "Nothing to clear" }
            let count = items.count == 1 ? "1 item" : "\(items.count) items"
            return "\(ByteCountFormatStyle(style: .file).format(size)), \(count)"
        }
    }

    /// What exists on this Mac for `app`, with its size. Walks folders, so call it off the main thread.
    static func find(_ app: App) -> Found {
        let home = NSHomeDirectory()
        var found = Found(app: app)
        var seen = Set<String>()
        for pattern in app.patterns {
            for path in glob(home + "/" + pattern) where seen.insert(path).inserted {
                found.items.append(URL(fileURLWithPath: path))
                found.size += size(of: path)
            }
        }
        found.items.sort { $0.path < $1.path }
        return found
    }

    /// Names of the running apps that read `app`'s caches.
    @MainActor static func runningApps(for app: App) -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { app.bundleIDs.contains($0.bundleIdentifier ?? "") }
            .compactMap(\.localizedName)
            .sorted()
    }

    /// Moves every found item to the Trash. Returns how many couldn't be moved.
    static func trash(_ found: Found) -> Int {
        var failures = 0
        for url in found.items {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                NSLog("Point: trash \(url.path) failed: \(error)")
                failures += 1
            }
        }
        return failures
    }

    private static func glob(_ pattern: String) -> [String] {
        var results = glob_t()
        defer { globfree(&results) }
        guard Darwin.glob(pattern, GLOB_BRACE | GLOB_NOSORT, nil, &results) == 0 else { return [] }
        return (0..<Int(results.gl_matchc)).compactMap { index in
            results.gl_pathv[index].map { String(cString: $0) }
        }
    }

    /// Bytes used by a file, or by everything inside a folder (symbolic links aren't followed).
    private static func size(of path: String) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        func fileSize(_ url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory != true, values?.isSymbolicLink != true else { return 0 }
            return Int64(values?.totalFileAllocatedSize ?? 0)
        }
        let root = URL(fileURLWithPath: path)
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return fileSize(root) }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in enumerator { total += fileSize(url) }
        }
        return total
    }
}
