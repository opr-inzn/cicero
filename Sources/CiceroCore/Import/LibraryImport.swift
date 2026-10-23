import Foundation

/// What to bring in from another font manager, as the Import sheet's checkboxes have it.
public struct ImportChoices: Equatable, Sendable {
    /// List FontExplorer X's Font Library as a folder.
    public var fontFolder = true
    /// List the font files it used from other places, one by one.
    public var otherFiles = true
    /// The sets, application sets and collections to bring in, by `ImportedSet.id`.
    public var sets: Set<String> = []
    /// The smart sets to bring in, by `ImportedSmartSet.id`.
    public var smartSets: Set<String> = []
    public var tags = true
    public var ratings = true
    public var classifications = true
    /// Comments, as notes.
    public var comments = true
    public var history = true
    /// Turn on, in place, the fonts that were on in the other app.
    public var activate = false

    /// Everything but the other app's own sets, which Font Book makes for everyone, and smart sets that can't come over;
    /// the fonts that were on are turned on again, so they stay on once the other app is gone.
    public init(for library: ImportedLibrary) {
        sets = Set(library.sets.filter { !$0.isBuiltIn }.map(\.id))
        smartSets = Set(library.smartSets.filter(\.unsupported.isEmpty).map(\.id))
        activate = !library.active.isEmpty
    }
}

/// What an import did, for the message afterwards.
public struct ImportSummary: Equatable, Sendable {
    /// Font files listed: the Font Library's and the others.
    public var fonts = 0
    /// Sets made, or that had the name of one and got its fonts.
    public var sets = 0
    public var applicationSets = 0
    public var smartSets = 0
    public var tags = 0
    public var ratedFamilies = 0
    /// Families put in a classification, and the user's own classifications made for them.
    public var classifiedFamilies = 0
    public var classifications = 0
    /// Families that got a note from comments.
    public var notedFamilies = 0
    /// Styles to turn on, as they were on in the other app.
    public var activated = 0
    /// Fonts the sets, tags or ratings name that aren't in the library.
    public var notFound = 0
    /// Smart sets with rules Cicero can't take, or naming a set that wasn't brought in.
    public var skippedSmartSets: [String] = []
    /// Apps of application sets that aren't on this Mac.
    public var missingApps: [String] = []

    public init() {}
}

/// Brings what another font manager has into Cicero: first its fonts (`addFonts`, and `placeBundledFonts` for a backup
/// that has them), then, once a scan has listed them, the rest (`apply`). Only ever adds: a set with the name of one
/// that's there already gets its fonts, so importing again changes nothing.
public enum LibraryImport {
    /// Lists the other app's fonts: its Font Library as a folder, and the files it used from elsewhere one by one,
    /// where they are. Returns how many files that is.
    public static func addFonts(_ imported: ImportedLibrary, choices: ImportChoices, to data: inout UserData, locations: Locations) -> Int {
        var count = 0
        var folders = [locations.userFonts.path, locations.allUsersFonts.path, locations.deactivated.path] + data.scannedFolders().map(\.path)
        func isRead(_ path: String) -> Bool { folders.contains { path == $0 || path.hasPrefix($0 + "/") } }
        if choices.fontFolder, let folder = imported.fontFolder {
            // A backup's are those it has, which `placeBundledFonts` put there.
            count += imported.bundledFonts?.files.count ?? imported.fontFolderCount
            if !isRead(folder) {
                // Adobe's folders come with the Proofing switch, as when the user adds one.
                if WatchedFolder.detectAppName(forPath: folder) != nil {
                    data.showAdobeAppFolders = true
                } else {
                    // Called after the app in the sidebar: "Font Library" alone reads like Cicero's own.
                    let added = WatchedFolder(path: folder)
                    data.folders.append(added)
                    data.folderNames[added.id.uuidString] = imported.source.appName
                }
                folders.append(folder)
            }
        }
        if choices.otherFiles {
            let listed = Set(data.fontFiles)
            for path in imported.otherFiles where !listed.contains(path) && !isRead(path) {
                data.fontFiles.append(path)
                count += 1
            }
        }
        return count
    }

    /// Puts a backup's fonts in the Font Library's folder, keeping their folders. A file already there is left alone.
    /// A backup is a file anyone could have made: only font files are copied, and only from inside the unzipped
    /// backup, never through a symbolic link or out of either folder. Returns how many were copied; cancelling stops
    /// between files.
    @concurrent
    public static func placeBundledFonts(_ imported: ImportedLibrary, progress: @escaping @Sendable (Int, Int) -> Void) async -> Int {
        guard let bundled = imported.bundledFonts, let destination = imported.fontFolder else { return 0 }
        let fm = FileManager.default
        let source = bundled.folder.resolvingSymlinksInPath().path
        var copied = 0
        for (index, file) in bundled.files.enumerated() {
            if Task.isCancelled { break }
            progress(index, bundled.files.count)
            let parts = file.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  FontFormat.fileExtensions.contains((file as NSString).pathExtension.lowercased())
            else { continue }
            let from = URL(fileURLWithPath: source).appendingPathComponent(file)
            guard from.resolvingSymlinksInPath().path == from.path,
                  (try? from.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let to = URL(fileURLWithPath: destination).appendingPathComponent(file)
            guard !fm.fileExists(atPath: to.path) else { continue }
            do {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: from, to: to)
                copied += 1
            } catch {
                continue
            }
        }
        progress(bundled.files.count, bundled.files.count)
        return copied
    }

    /// Brings in the sets, smart sets, tags, ratings, classifications and activation history, matched against the library, which has
    /// the other app's fonts by now; and gives the styles to turn on, when chosen. Apps of application sets are looked
    /// for where they were, then by name in `appFolders`.
    public static func apply(_ imported: ImportedLibrary, choices: ImportChoices, to data: inout UserData, library: Library,
                             appFolders: [URL] = AppFinder.defaultFolders) -> (summary: ImportSummary, activate: [LibraryFace]) {
        let matcher = FontMatcher(library)
        var summary = ImportSummary()
        var notFound = Set<ImportedFont>()
        func faces(_ fonts: [ImportedFont], wholeFiles: Bool = false) -> [(family: Family, face: LibraryFace)] {
            fonts.flatMap { font in
                let found = matcher.faces(font, wholeFile: wholeFiles)
                if found.isEmpty { notFound.insert(font) }
                return found
            }
        }
        func families(_ fonts: [ImportedFont]) -> [Family] {
            var seen = Set<String>()
            return faces(fonts).map(\.family).filter { seen.insert($0.id).inserted }
        }

        // Sets: whole families where every style the library has is in it, else the styles. FontExplorer X's sets have
        // files, so every style the library has in one.
        var setIDs: [String: UUID] = [:]
        let apps = AppFinder(folders: appFolders)
        for set in imported.sets where choices.sets.contains(set.id) {
            var whole: [String] = []
            var styles: [String: [String]] = [:]
            var order: [String] = []
            var matched: [String: (family: Family, styles: Set<String>)] = [:]
            for (family, face) in faces(set.fonts, wholeFiles: true) {
                if matched[family.id] == nil { order.append(family.id) }
                matched[family.id, default: (family, [])].styles.insert(face.face.postScriptName)
            }
            for name in set.families {
                guard let family = matcher.family(named: name) else {
                    notFound.insert(ImportedFont(family: name))
                    continue
                }
                if matched[family.id] == nil { order.append(family.id) }
                let kept = family.faces.map(\.face.postScriptName).filter { !set.excluded.contains($0) }
                matched[family.id, default: (family, [])].styles.formUnion(kept)
            }
            for id in order {
                guard let entry = matched[id], !entry.styles.isEmpty else { continue }
                let all = entry.family.faces.map(\.face.postScriptName)
                if all.allSatisfy(entry.styles.contains) {
                    whole.append(id)
                } else {
                    styles[id] = all.filter(entry.styles.contains)
                }
            }
            var linked: [LinkedApp] = []
            for path in set.apps {
                if let app = apps.app(at: path) {
                    if !linked.contains(where: { $0.bundleID == app.bundleID }) { linked.append(app) }
                } else {
                    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                    if !summary.missingApps.contains(name) { summary.missingApps.append(name) }
                }
            }
            if let index = data.sets.firstIndex(where: { $0.name == set.name }) {
                data.sets[index].add(families: whole)
                for (family, names) in styles { for name in names { data.sets[index].add(style: name, of: family) } }
                for app in linked where !data.sets[index].apps.contains(where: { $0.bundleID == app.bundleID }) {
                    data.sets[index].apps.append(app)
                }
                setIDs[set.id] = data.sets[index].id
            } else {
                let new = FontSet(name: set.name, families: whole, styles: styles, apps: linked)
                data.sets.append(new)
                setIDs[set.id] = new.id
            }
            if set.isApplicationSet { summary.applicationSets += 1 } else { summary.sets += 1 }
        }

        // Tags before smart sets, whose rules may name them.
        if choices.tags {
            for tag in imported.tags {
                if !data.tags.contains(tag.name) {
                    data.tags.append(tag.name)
                    data.tagColors[tag.name] = tag.color
                }
                for family in families(tag.fonts) {
                    var names = data.familyTags[family.id] ?? []
                    if !names.contains(tag.name) { names.append(tag.name) }
                    data.familyTags[family.id] = names
                }
                summary.tags += 1
            }
        }

        // Smart sets, only whole: one without a rule would pick other fonts. One with the name of one that's there was
        // brought in before.
        let setNames = Dictionary(imported.sets.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for smart in imported.smartSets where choices.smartSets.contains(smart.id) {
            guard !data.smartSets.contains(where: { $0.name == smart.name }) else { continue }
            var rules = smart.rules
            var complete = smart.unsupported.isEmpty
            for index in rules.indices {
                switch rules[index].field {
                case .set:
                    let id = rules[index].value
                    let existing = setNames[id].flatMap { name in data.sets.first { $0.name == name }?.id }
                    if let uuid = setIDs[id] ?? existing { rules[index].value = uuid.uuidString } else { complete = false }
                case .tag:
                    if !data.tags.contains(rules[index].value) { complete = false }
                default:
                    break
                }
            }
            guard complete else {
                summary.skippedSmartSets.append(smart.name)
                continue
            }
            data.smartSets.append(SmartSet(name: smart.name, matchAll: smart.matchAll, rules: rules))
            summary.smartSets += 1
        }

        // A family's rating is its highest-rated style's, unless it has one already.
        if choices.ratings {
            var stars: [String: Int] = [:]
            for rating in imported.ratings {
                for (family, _) in faces([rating.font]) { stars[family.id] = max(stars[family.id] ?? 0, rating.stars) }
            }
            for (family, value) in stars where data.familyRatings[family] == nil {
                data.familyRatings[family] = value
                summary.ratedFamilies += 1
            }
        }

        // A family goes in the classification most of its styles have, as the user's choice, unless the user chose one
        // already or its fonts say as much; the user's own ones from the other app come along.
        if choices.classifications {
            var votes: [String: [String: Int]] = [:]
            var families: [String: Family] = [:]
            var custom = Set<String>()
            for classification in imported.classifications {
                let name = classification.builtIn.map { data.classificationRenames[$0.rawValue] ?? $0.rawValue } ?? classification.name
                if classification.builtIn == nil { custom.insert(name) }
                for (family, _) in faces([classification.font]) {
                    votes[family.id, default: [:]][name, default: 0] += 1
                    families[family.id] = family
                }
            }
            for (id, counts) in votes.sorted(by: { $0.key < $1.key }) where data.classificationOverrides[id] == nil {
                guard let family = families[id],
                      let name = counts.max(by: { $0.value < $1.value || $0.value == $1.value && $0.key > $1.key })?.key else { continue }
                let suggested = data.classificationRenames[family.classification.rawValue] ?? family.classification.rawValue
                guard name != suggested || custom.contains(name) else { continue }
                if custom.contains(name), !data.classifications.contains(name),
                   !Classification.allCases.contains(where: { (data.classificationRenames[$0.rawValue] ?? $0.rawValue) == name }) {
                    data.classifications.append(name)
                    summary.classifications += 1
                }
                data.classificationOverrides[id] = name
                summary.classifiedFamilies += 1
            }
        }

        // A family's note is its comments, each once, unless it has a note already.
        if choices.comments {
            var notes: [String: [String]] = [:]
            for comment in imported.comments {
                let text = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                for family in families(comment.fonts) where !(notes[family.id] ?? []).contains(text) { notes[family.id, default: []].append(text) }
            }
            for (family, texts) in notes where data.familyNotes[family] == nil {
                data.familyNotes[family] = texts.joined(separator: "\n")
                summary.notedFamilies += 1
            }
        }

        // How often a family was turned on: the most any of its files was, and when last; Cicero's counts if higher.
        if choices.history {
            var histories: [String: ActivationHistory] = [:]
            for entry in imported.history {
                for family in families(entry.fonts) {
                    var history = histories[family.id] ?? ActivationHistory()
                    history.count = max(history.count, entry.count)
                    history.last = [history.last, entry.last].compactMap { $0 }.max()
                    histories[family.id] = history
                }
            }
            for (family, history) in histories {
                var merged = data.activations[family] ?? ActivationHistory()
                merged.count = max(merged.count, history.count)
                merged.last = [merged.last, history.last].compactMap { $0 }.max()
                data.activations[family] = merged
            }
        }

        var activate: [LibraryFace] = []
        if choices.activate {
            var seen = Set<FaceID>()
            activate = faces(imported.active).map(\.face).filter { $0.canActivate && seen.insert($0.face.id).inserted }
        }
        summary.notFound = notFound.count
        return (summary, activate)
    }
}

/// Finds the apps of application sets from another Mac: where they were, else one with the same name in the
/// Applications folders, else the newest one whose name only has another year ("Adobe InDesign 2024" finds
/// "Adobe InDesign 2026").
public struct AppFinder: Sendable {
    public static var defaultFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// The apps in the folders and the folders in them (Adobe's apps are in folders of their own), by name.
    private let installed: [(name: String, url: URL)]

    public init(folders: [URL]) {
        let fm = FileManager.default
        var found: [(String, URL)] = []
        func look(in folder: URL, depth: Int) {
            let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for child in children {
                if child.pathExtension == "app" {
                    found.append((child.deletingPathExtension().lastPathComponent, child))
                } else if depth > 0, (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    look(in: child, depth: depth - 1)
                }
            }
        }
        for folder in folders { look(in: folder, depth: 1) }
        installed = found
    }

    public func app(at path: String) -> LinkedApp? {
        let url = URL(fileURLWithPath: path)
        if let app = Self.linked(url) { return app }
        let name = url.deletingPathExtension().lastPathComponent
        if let same = installed.first(where: { $0.name == name }), let app = Self.linked(same.url) { return app }
        let base = Self.withoutYear(name)
        guard base != name else { return nil }
        let others = installed.filter { Self.withoutYear($0.name) == base }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        return others.lazy.compactMap { Self.linked($0.url) }.first
    }

    private static func linked(_ url: URL) -> LinkedApp? {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return LinkedApp(bundleID: bundleID, name: name, path: url.path)
    }

    /// "Adobe InDesign 2024" → "Adobe InDesign".
    private static func withoutYear(_ name: String) -> String {
        name.replacing(/\s(19|20)\d\d$/, with: "")
    }
}
