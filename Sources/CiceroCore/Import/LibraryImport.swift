import Foundation

/// What to bring in from another font manager, as the Import sheet's checkboxes have it.
public struct ImportChoices: Equatable, Sendable {
    /// Copy in the fonts in FontExplorer X's Font Library or FontBase's folder.
    public var fontFolder = true
    /// Copy in the font files it used from other places.
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
    /// Turn on again the fonts that were on in the other app, once they're copied in.
    public var activate = false
    /// Move the other app's `leftoverCopies` to the Trash.
    public var removeCopies = true

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
    /// Font files copied in: the Font Library's and the others. Not those already there with the same name and contents.
    public var fonts = 0
    /// Font files that didn't go in, as when macOS was too busy to take them: importing again tries them again.
    public var notCopied = 0
    /// Sets made, or that had the name of one and got fonts or apps from it. What a set had already isn't counted, so
    /// importing again counts nothing.
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
    /// The other app's copies moved to the Trash.
    public var removedCopies = 0
    /// Fonts the sets, tags or ratings name that aren't in the library.
    public var notFound = 0
    /// Sets left out as none of their fonts are in the library: they would be empty.
    public var emptySets: [String] = []
    /// Smart sets with rules Cicero can't take, or naming a set that wasn't brought in.
    public var skippedSmartSets: [String] = []
    /// Apps of application sets that aren't on this Mac.
    public var missingApps: [String] = []

    public init() {}
}

/// Brings what another font manager has into Cicero: first its fonts, copied in off (`fontFiles`,
/// `ActivationEngine.installOff`), then, once a scan has listed them, the rest (`apply`). Only ever adds: a set with the
/// name of one that's there already gets its fonts, so importing again changes nothing.
public enum LibraryImport {
    /// The font files to copy in, each as the other app names it (`path`, what its sets and tags go by) and where to
    /// copy it from (`source`): the Font Library's, from a backup when it has them, and those it used from elsewhere. Not
    /// one Cicero reads already, in a Fonts folder, one of the user's locations or among the files they added, which stays
    /// as it is; nor those in an Adobe app's folder, which comes with the Proofing switch instead, as when the user adds
    /// one (`data`). A backup is a file anyone could have made: only font files are taken, and only from inside the
    /// unzipped backup, never through a symbolic link or out of it.
    public static func fontFiles(_ imported: ImportedLibrary, choices: ImportChoices, data: inout UserData,
                                 locations: Locations) -> [(path: String, source: String)] {
        let folders = [locations.userFonts.path, locations.allUsersFonts.path] + locations.inactiveFolders.map(\.path) + data.scannedFolders().map(\.path)
        let listed = Set(data.fontFiles)
        func isRead(_ path: String) -> Bool { listed.contains(path) || folders.contains { path == $0 || path.hasPrefix($0 + "/") } }
        func isFont(_ path: String) -> Bool { FontFormat.fileExtensions.contains((path as NSString).pathExtension.lowercased()) }
        var files: [(path: String, source: String)] = []
        if choices.fontFolder, let folder = imported.fontFolder {
            if WatchedFolder.detectAppName(forPath: folder) != nil {
                data.showAdobeAppFolders = true
            } else if let bundled = imported.bundledFonts {
                let source = URL(fileURLWithPath: bundled.folder.resolvingSymlinksInPath().path)
                for file in bundled.files where isFont(file) {
                    let parts = file.split(separator: "/", omittingEmptySubsequences: false)
                    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { continue }
                    let from = source.appendingPathComponent(file)
                    guard from.resolvingSymlinksInPath().path == from.path,
                          (try? from.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                          !isRead(folder + "/" + file)
                    else { continue }
                    files.append((folder + "/" + file, from.path))
                }
            } else {
                files += imported.fontFolderFiles.filter { isFont($0) && !isRead($0) }.map { ($0, $0) }
            }
        }
        if choices.otherFiles {
            files += imported.otherFiles.filter { isFont($0) && !isRead($0) }.map { ($0, $0) }
        }
        return files
    }

    /// Moves the other app's copies of its fonts out of the Fonts folder, to the Trash: only the ones it read, and
    /// only font files. Returns how many were moved.
    public static func removeCopies(_ imported: ImportedLibrary) -> Int {
        imported.leftoverCopies.count { path in
            FontFormat.fileExtensions.contains((path as NSString).pathExtension.lowercased())
                && (try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)) != nil
        }
    }

    /// Brings in the sets, smart sets, tags, ratings, classifications and activation history, matched against the
    /// library, which has the other app's fonts by now, at the paths their copies have (`paths`, the other app's → the
    /// copy's); and gives the styles to turn on, when chosen. Apps of application sets are looked for where they were,
    /// then by name in `appFolders`.
    public static func apply(_ imported: ImportedLibrary, choices: ImportChoices, to data: inout UserData, library: Library,
                             paths: [String: String] = [:], appFolders: [URL] = AppFinder.defaultFolders)
        -> (summary: ImportSummary, activate: [LibraryFace]) {
        let matcher = FontMatcher(library)
        var summary = ImportSummary()
        var notFound = Set<ImportedFont>()
        func faces(_ fonts: [ImportedFont], wholeFiles: Bool = false) -> [(family: Family, face: LibraryFace)] {
            fonts.flatMap { font in
                var copied = font
                if let path = font.path, let copy = paths[path] { copied.path = copy }
                let found = matcher.faces(copied, wholeFile: wholeFiles)
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
            let changed: Bool
            if let index = data.sets.firstIndex(where: { $0.name == set.name }) {
                let before = data.sets[index]
                data.sets[index].add(families: whole)
                for (family, names) in styles { for name in names { data.sets[index].add(style: name, of: family) } }
                for app in linked where !data.sets[index].apps.contains(where: { $0.bundleID == app.bundleID }) {
                    data.sets[index].apps.append(app)
                }
                setIDs[set.id] = data.sets[index].id
                changed = data.sets[index] != before
            } else if whole.isEmpty, styles.isEmpty, set.count > 0 {
                // None of its fonts are here: it would come over empty.
                summary.emptySets.append(set.name)
                continue
            } else {
                let new = FontSet(name: set.name, families: whole, styles: styles, apps: linked)
                data.sets.append(new)
                setIDs[set.id] = new.id
                changed = true
            }
            guard changed else { continue }
            if set.isApplicationSet { summary.applicationSets += 1 } else { summary.sets += 1 }
        }

        // Tags before smart sets, whose rules may name them.
        if choices.tags {
            for tag in imported.tags {
                var changed = false
                if !data.tags.contains(tag.name) {
                    data.tags.append(tag.name)
                    data.tagColors[tag.name] = tag.color
                    changed = true
                }
                for family in families(tag.fonts) {
                    var names = data.familyTags[family.id] ?? []
                    guard !names.contains(tag.name) else { continue }
                    names.append(tag.name)
                    data.familyTags[family.id] = names
                    changed = true
                }
                if changed { summary.tags += 1 }
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
