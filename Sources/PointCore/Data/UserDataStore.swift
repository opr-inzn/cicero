import Foundation
import Synchronization

/// Loads and saves `UserData` (`user-data.json` in `Locations.support`). The first load imports the
/// version 1 file (`library.json`) when there's no version 2 file yet, and never modifies it. Saves
/// are coalesced and written off the main thread, atomically, in order.
public final class UserDataStore: Sendable {
    private let fileURL: URL
    private let legacyURL: URL
    private let queue = DispatchQueue(label: "Point.UserDataStore", qos: .utility)
    private let pending = Mutex<Pending>(Pending())

    private struct Pending {
        var data: UserData?
        /// Counts saves, so a scheduled write knows when a later save has superseded it.
        var generation = 0
    }

    /// How long changes are collected before one write.
    static let coalescingDelay: TimeInterval = 0.25

    public init(locations: Locations) {
        fileURL = locations.support.appendingPathComponent("user-data.json", isDirectory: false)
        legacyURL = locations.support.appendingPathComponent("library.json", isDirectory: false)
    }

    public func load() -> UserData {
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(UserData.self, from: data) { return decoded }
            // Keep a damaged file for the user instead of silently writing over it.
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.deletingPathExtension().appendingPathExtension("unreadable.json"))
            return UserData()
        }
        if let legacy = try? Data(contentsOf: legacyURL),
           let object = (try? JSONSerialization.jsonObject(with: legacy)) as? [String: Any] {
            let imported = LegacyImport.userData(from: object)
            queue.sync { write(imported) }
            return imported
        }
        return UserData()
    }

    /// Schedules a save of this value (the latest one wins).
    public func save(_ data: UserData) {
        let generation = pending.withLock { pending in
            pending.data = data
            pending.generation += 1
            return pending.generation
        }
        queue.asyncAfter(deadline: .now() + Self.coalescingDelay) { [self] in writePending(for: generation) }
    }

    /// Writes any pending save now; call when the app quits.
    public func flush() {
        queue.sync { writePending(for: nil) }
    }

    /// Writes what's pending unless a later save has already been scheduled (nil: write regardless).
    private func writePending(for generation: Int?) {
        let data = pending.withLock { pending -> UserData? in
            if let generation, generation != pending.generation { return nil }
            defer { pending.data = nil }
            return pending.data
        }
        if let data { write(data) }
    }

    private func write(_ data: UserData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let encoded = try? encoder.encode(data) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: fileURL, options: .atomic)
    }
}

/// Reads the version 1 file (`library.json`). Any key may be missing.
enum LegacyImport {
    static func userData(from object: [String: Any]) -> UserData {
        var data = UserData()
        data.folders = list(object["watchedFolders"]).compactMap { folder in
            guard let path = folder["path"] as? String else { return nil }
            return WatchedFolder(id: uuid(folder["id"]) ?? UUID(), path: path, appName: nonEmpty(folder["appOnlyName"]))
        }
        data.sets = (list(object["sets"]) + list(object["collections"])).compactMap { set in
            guard let name = set["name"] as? String else { return nil }
            return FontSet(id: uuid(set["id"]) ?? UUID(), name: name, families: strings(set["familyNames"]))
        }
        data.smartSets = list(object["smartSets"]).compactMap { set in
            guard let name = set["name"] as? String else { return nil }
            let rules = list(set["rules"]).compactMap { rule -> SmartRule? in
                guard let field = (rule["field"] as? String).flatMap(SmartRule.Field.init(rawValue:)) else { return nil }
                let comparison = (rule["comparison"] as? String).flatMap(SmartRule.Comparison.init(rawValue:))
                return SmartRule(id: uuid(rule["id"]) ?? UUID(), field: field, comparison: comparison, value: rule["value"] as? String ?? "")
            }
            return SmartSet(id: uuid(set["id"]) ?? UUID(), name: name, matchAll: set["matchAll"] as? Bool ?? true, rules: rules)
        }
        data.customCharacterSets = list(object["customCharacterSets"]).compactMap { set in
            guard let name = set["name"] as? String else { return nil }
            return CustomCharacterSet(id: uuid(set["id"]) ?? UUID(), name: name, characters: set["characters"] as? String ?? "")
        }
        data.tags = strings(object["tags"])
        for (family, tags) in object["familyTags"] as? [String: Any] ?? [:] {
            let names = strings(tags)
            if !names.isEmpty { data.familyTags[family] = names }
        }
        // Very old files had one "style" per family instead of tags.
        let styles = list(object["styles"]).reduce(into: [String: String]()) { names, style in
            if let id = style["id"] as? String, let name = style["name"] as? String { names[id] = name }
        }
        for (family, styleID) in object["styleAssignments"] as? [String: String] ?? [:] {
            guard let name = styles[styleID] else { continue }
            if !data.tags.contains(name) { data.tags.append(name) }
            if !(data.familyTags[family] ?? []).contains(name) { data.familyTags[family, default: []].append(name) }
        }
        data.foundryOverrides = object["foundryOverrides"] as? [String: String] ?? [:]
        data.foundryRenames = object["foundryRenames"] as? [String: String] ?? [:]
        data.sidebar.hidden = Set(strings(object["hiddenSidebarItems"]).filter { !$0.hasPrefix("charset.") })
        // Version 1 had no character set groups; the big ones start collapsed, as for a new user.
        data.sidebar.collapsed = Set(strings(object["collapsedSections"])).union(["charsetgroup.unicode", "charsetgroup.google"])
        switch object["installMethod"] as? String {
        case "copy": data.installMethod = .copy
        case "register": data.installMethod = .inPlace
        default: data.installMethod = .ask
        }
        data.showSystemFonts = object["showSystemFonts"] as? Bool ?? true
        data.records.installedCopies = object["installedCopies"] as? [String: String] ?? [:]
        data.records.inPlace = Set(strings(object["registeredPaths"]))
        for (path, record) in object["temporaryActivations"] as? [String: [String: Any]] ?? [:] {
            guard let scope = (record["scope"] as? String).flatMap(TemporaryScope.init(rawValue:)) else { continue }
            data.records.temporary[path] = TemporaryRecord(scope: scope, session: record["session"] as? String ?? "")
        }
        return data
    }

    private static func list(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func strings(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
