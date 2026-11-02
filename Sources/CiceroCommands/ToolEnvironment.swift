import CiceroCore
import CoreText
import Foundation

/// Where the tool finds Cicero's files, and what it asks macOS. Environment variables move it to other folders for the
/// end-to-end tests (Tests/E2E/cli); they only ever change where it reads and writes.
///
/// - `CICERO_SUPPORT_DIR`: in place of ~/Library/Application Support/Cicero.
/// - `CICERO_CACHES_DIR`: in place of ~/Library/Caches/Cicero.
/// - `CICERO_FONTS_DIR`, `CICERO_ALL_USERS_FONTS_DIR`, `CICERO_SYSTEM_FONTS_DIR`: in place of ~/Library/Fonts,
///   /Library/Fonts and /System/Library/Fonts.
/// - `CICERO_DEFAULTS_DOMAIN`: the app's settings, in place of com.maximilianinzinger.Cicero.
/// - `CICERO_RESOURCES`: the folder with CharacterSets.json and Languages.json, in place of the app bundle's.
/// - `CICERO_FAKE_REGISTRAR`: a file listing the font files macOS has active, one path a line, in place of asking
///   macOS; the tool then never changes the Mac's fonts.
/// - `CICERO_NOW`: what "now" is (ISO 8601), for Recents.
/// - `CICERO_PROOFING_DIRS`: the folders Adobe apps load fonts from by themselves (the proofing fonts), separated by
///   colons, in place of those on the Mac.
public struct ToolEnvironment: @unchecked Sendable {
    public var locations: Locations
    /// The app's settings (`UserDefaults` is thread-safe).
    public var defaults: UserDefaults
    /// The folder with CharacterSets.json and Languages.json; nil when it can't be found.
    public var resources: URL?
    public var registrar: any FontRegistrar
    public var now: Date
    /// The app's bundle ID, to tell whether it's open.
    public var appBundleID: String
    /// The folders Adobe apps load fonts from by themselves; nil for those on the Mac (`WatchedFolder.appFontFolders`).
    public var proofingFolders: [WatchedFolder]?

    /// The folders Adobe apps load fonts from by themselves.
    public var appFontFolders: [WatchedFolder] { proofingFolders ?? WatchedFolder.appFontFolders() }

    public init(locations: Locations, defaults: UserDefaults, resources: URL?, registrar: any FontRegistrar, now: Date = .now,
                appBundleID: String = ToolEnvironment.bundleID) {
        self.locations = locations
        self.defaults = defaults
        self.resources = resources
        self.registrar = registrar
        self.now = now
        self.appBundleID = appBundleID
    }

    public static let bundleID = "com.maximilianinzinger.Cicero"

    /// The environment of this process, as the variables above change it.
    public static func current(_ variables: [String: String] = ProcessInfo.processInfo.environment) -> ToolEnvironment {
        func folder(_ name: String) -> URL? {
            variables[name].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        }
        var locations = Locations.standard
        if let support = folder("CICERO_SUPPORT_DIR") { locations.support = support }
        if let caches = folder("CICERO_CACHES_DIR") { locations.caches = caches }
        if let fonts = folder("CICERO_FONTS_DIR") { locations.userFonts = fonts }
        if let fonts = folder("CICERO_ALL_USERS_FONTS_DIR") { locations.allUsersFonts = fonts }
        if let fonts = folder("CICERO_SYSTEM_FONTS_DIR") { locations.systemFonts = [fonts] }
        let domain = variables["CICERO_DEFAULTS_DOMAIN"].flatMap { $0.isEmpty ? nil : $0 } ?? bundleID
        let registrar: any FontRegistrar = variables["CICERO_FAKE_REGISTRAR"].flatMap { $0.isEmpty ? nil : ListedRegistrar(file: $0) }
            ?? CoreTextRegistrar()
        let now = variables["CICERO_NOW"].flatMap { try? Date($0, strategy: .iso8601) } ?? .now
        var environment = ToolEnvironment(
            locations: locations, defaults: UserDefaults(suiteName: domain) ?? .standard,
            resources: folder("CICERO_RESOURCES") ?? bundledResources(), registrar: registrar, now: now, appBundleID: domain
        )
        environment.proofingFolders = variables["CICERO_PROOFING_DIRS"].map { list in
            list.split(separator: ":").map { WatchedFolder(id: WatchedFolder.adobeAppsID, path: String($0), appName: "Adobe") }
        }
        return environment
    }

    /// Cicero.app/Contents/Resources, from the tool in Cicero.app/Contents/Helpers, also through a link to it (as in
    /// /usr/local/bin); else, for a build in the package's .build folder, the package's Resources.
    static func bundledResources() -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [Bundle.main.executableURL?.resolvingSymlinksInPath(), executable].compactMap { $0 }
        let fm = FileManager.default
        for binary in candidates {
            let contents = binary.deletingLastPathComponent().deletingLastPathComponent()
            let bundled = contents.appendingPathComponent("Resources", isDirectory: true)
            if fm.fileExists(atPath: bundled.appendingPathComponent("CharacterSets.json").path) { return bundled }
            // .build/<triple>/<configuration>/cicero-tool → the package.
            var folder = binary.deletingLastPathComponent()
            for _ in 0..<5 {
                folder = folder.deletingLastPathComponent()
                let resources = folder.appendingPathComponent("Resources", isDirectory: true)
                if fm.fileExists(atPath: resources.appendingPathComponent("CharacterSets.json").path),
                   fm.fileExists(atPath: folder.appendingPathComponent("Package.swift").path) {
                    return resources
                }
            }
        }
        return nil
    }

    public var userDataURL: URL { locations.support.appendingPathComponent("user-data.json", isDirectory: false) }
}

/// macOS's active font files as a list in a file, for tests: turning a font on or off adds its path to the list or takes
/// it out, and nothing reaches macOS.
struct ListedRegistrar: FontRegistrar {
    let file: String

    init?(file: String) {
        self.file = file
    }

    private var paths: Set<String> {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private func write(_ paths: Set<String>) {
        try? Data((paths.sorted().joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: file), options: .atomic)
    }

    /// Nothing fails.
    private func change(_ urls: [URL], on: Bool) -> Set<String> {
        let changed = Set(urls.map { $0.path(percentEncoded: false) })
        write(on ? paths.union(changed) : paths.subtracting(changed))
        return []
    }

    func register(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> { change(urls, on: true) }
    func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> { change(urls, on: false) }
    func unregisterNow(_ urls: [URL], scope: CTFontManagerScope) { _ = change(urls, on: false) }
    func setEnabled(_ urls: [URL], _ enabled: Bool) async -> Set<String> { change(urls, on: enabled) }
    func disableNow(_ urls: [URL]) { _ = change(urls, on: false) }
    func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String> { [] }
    func activeFontURLs() -> [URL] { paths.sorted().map { URL(fileURLWithPath: $0, isDirectory: false) } }
    func isActive(_ url: URL) -> Bool { paths.contains(url.path(percentEncoded: false)) }
    func offFontPaths() -> Set<String> { [] }
}
