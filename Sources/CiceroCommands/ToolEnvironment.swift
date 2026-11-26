import CiceroCore
import CoreText
import Foundation

public struct ToolEnvironment: @unchecked Sendable {
    public var locations: Locations
    public var defaults: UserDefaults
    public var resources: URL?
    public var registrar: any FontRegistrar
    public var now: Date
    public var appBundleID: String
    public var proofingFolders: [WatchedFolder]?

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

    static func bundledResources() -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [Bundle.main.executableURL?.resolvingSymlinksInPath(), executable].compactMap { $0 }
        let fm = FileManager.default
        for binary in candidates {
            let contents = binary.deletingLastPathComponent().deletingLastPathComponent()
            let bundled = contents.appendingPathComponent("Resources", isDirectory: true)
            if fm.fileExists(atPath: bundled.appendingPathComponent("CharacterSets.json").path) { return bundled }
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

    var userDataURL: URL { locations.support.appendingPathComponent("user-data.json", isDirectory: false) }
}

struct ListedRegistrar: FontRegistrar {
    let file: String

    private var paths: Set<String> {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private func write(_ paths: Set<String>) {
        try? Data((paths.sorted().joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: file), options: .atomic)
    }

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
