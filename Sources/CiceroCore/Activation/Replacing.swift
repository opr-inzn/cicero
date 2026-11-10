import CoreText
import Foundation

extension ActivationEngine {
    @concurrent
    public func replace(_ replacements: [FileReplacement], moving: Bool, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        let olds = replacements.map(\.old)
        let persistent = olds.filter { records.inPlace.contains($0) || isInsideUserFonts($0) && registrar.isActive(Self.url($0)) }
        let session = olds.filter { records.temporary[$0] != nil }
        let off = Set(olds.filter { isInsideFontsFolder($0) && records.temporary[$0] == nil && !registrar.isActive(Self.url($0)) })
        let spareCopies = spareCopies(among: replacements, records: records)
        var records = records
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }

        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        var done: [FileReplacement] = []
        var failed: [String] = []
        var placed: [String: String] = [:]
        var renameLater: [String: String] = [:]
        var goingInOff: [String: FileReplacement] = [:]
        var intoLibrary: [String: FileReplacement] = [:]
        var spare: [(replacement: FileReplacement, original: String)] = []
        for replacement in replacements {
            if let original = spareCopies[replacement.old] {
                spare.append((replacement, original))
                continue
            }
            let old = Self.url(replacement.old)
            if off.contains(replacement.old) {
                let staged = staging.appendingPathComponent(UUID().uuidString + "-" + old.lastPathComponent, isDirectory: false)
                do {
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    try fm.copyItem(at: Self.url(replacement.added), to: staged)
                } catch {
                    try? fm.removeItem(at: staged)
                    failed.append(replacement.old)
                    continue
                }
                if installsIntoFontLibrary, fontLibrary != nil { intoLibrary[staged.path] = replacement } else { goingInOff[staged.path] = replacement }
                continue
            }
            if replaceInPlace(old, with: Self.url(replacement.added)) {
                done.append(replacement)
            } else {
                failed.append(replacement.old)
            }
        }

        if !goingInOff.isEmpty {
            let off = await replaceOff(goingInOff)
            done += off.done
            failed += off.failed
            placed.merge(off.placed) { first, _ in first }
            renameLater = off.renameLater
            for old in off.placed.keys { records.installedCopies[old] = nil }
        }
        if !intoLibrary.isEmpty {
            let library = replaceIntoLibrary(intoLibrary)
            done += library.done
            failed += library.failed
            placed.merge(library.placed) { first, _ in first }
            for old in library.placed.keys { records.installedCopies[old] = nil }
        }
        for (replacement, original) in spare {
            guard done.contains(where: { $0.old == original }), didTrash(Self.url(replacement.old)) else {
                failed.append(replacement.old)
                continue
            }
            done.append(replacement)
            placed[replacement.old] = original
            records.installedCopies[replacement.old] = nil
        }

        let back = { (paths: [String]) in paths.filter { fm.fileExists(atPath: $0) } }
        if !back(persistent).isEmpty { _ = await registerAndConfirm(back(persistent), scope: .persistent) }
        if !back(session).isEmpty { _ = await registerAndConfirm(back(session), scope: .session) }

        func new(_ replacement: FileReplacement) -> String { placed[replacement.old] ?? replacement.old }
        if moving {
            for (added, copies) in Dictionary(grouping: done, by: \.added) where !Self.isProtected(added) {
                let meant = replacements.filter { $0.added == added }.count
                guard copies.count == meant, copies.allSatisfy({ Self.isIdenticalCopy(new($0), of: added) }) else { continue }
                try? fm.removeItem(atPath: added)
            }
        }

        var message: String
        if done.isEmpty {
            message = Self.message("Replaced", "replace", succeeded: 0, failed: failed.count,
                                   undone: FontNames.describe(FontNames.fonts(inFiles: failed)))
        } else {
            let names = FontNames.describe(FontNames.fonts(inFiles: done.map(new))) ?? (done.count == 1 ? "1 file" : "\(done.count) files")
            message = "Replaced \(names). " + (done.count == 1 ? "The old file is in the Trash" : "The old files are in the Trash")
            if !failed.isEmpty {
                let undone = FontNames.describe(FontNames.fonts(inFiles: failed.filter { fm.fileExists(atPath: $0) }))
                message += ". Couldn’t replace " + (undone ?? (failed.count == 1 ? "1 file" : "\(failed.count) files"))
            }
        }
        var result = ActivationResult(records: records, succeeded: done.count, failed: failed, message: message)
        result.placed = placed
        result.renameLater = renameLater
        return result
    }

    public func spareCopies(among replacements: [FileReplacement], records: ActivationRecords) -> [String: String] {
        guard installsIntoFontLibrary else { return [:] }
        let olds = Set(replacements.map(\.old))
        var spare: [String: String] = [:]
        for old in olds where isInsideFontsFolder(old) && records.temporary[old] == nil && !registrar.isActive(Self.url(old)) {
            guard let original = records.installedCopies[old], isInFontLibrary(original), olds.contains(original) else { continue }
            spare[old] = original
        }
        return spare
    }

    private struct Replacing: Codable {
        var staged: String
        var old: String
    }

    private var replacingNotes: URL { locations.support.appendingPathComponent("Replacing", isDirectory: true) }

    func replaceInPlace(_ old: URL, with added: URL) -> Bool {
        let fm = FileManager.default
        // The old file goes to the Trash only once its replacement is whole beside it, and comes back should the last step fail: a font must never be left gone from its place.
        let staged = old.deletingLastPathComponent().appendingPathComponent(Self.movingPrefix + UUID().uuidString, isDirectory: false)
        // Noted first, so a Cicero that stops partway finishes the replacement at its next launch, or takes the copy away.
        let note = replacingNotes.appendingPathComponent(UUID().uuidString + ".json", isDirectory: false)
        do {
            try fm.createDirectory(at: replacingNotes, withIntermediateDirectories: true)
            try JSONEncoder().encode(Replacing(staged: staged.path, old: old.path)).write(to: note, options: .atomic)
            guard UserDataStore.syncToDisk(note) else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? fm.removeItem(at: note)
            return false
        }
        defer { try? fm.removeItem(at: note) }
        do {
            try fm.copyItem(at: added, to: staged)
            Self.unlock(staged)
        } catch {
            try? fm.removeItem(at: staged)
            return false
        }
        let trashed: URL?
        do {
            trashed = try trash(old)
        } catch {
            try? fm.removeItem(at: staged)
            return false
        }
        if Self.renameExclusively(staged.path, to: old.path) { return true }
        try? fm.removeItem(at: staged)
        if let trashed, (try? Self.moveItem(trashed, to: old)) == nil { try? fm.moveItem(at: trashed, to: old) }
        return false
    }

    func finishReplacing() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: replacingNotes.path)) ?? [] where name.hasSuffix(".json") {
            let note = replacingNotes.appendingPathComponent(name, isDirectory: false)
            if let replacing = (try? Data(contentsOf: note)).flatMap({ try? JSONDecoder().decode(Replacing.self, from: $0) }),
               (replacing.staged as NSString).lastPathComponent.hasPrefix(Self.movingPrefix), Self.exists(replacing.staged) {
                if Self.exists(replacing.old) || !Self.renameExclusively(replacing.staged, to: replacing.old) {
                    try? fm.removeItem(atPath: replacing.staged)
                }
            }
            try? fm.removeItem(at: note)
        }
    }

    func replaceOff(_ staged: [String: FileReplacement]) async
        -> (done: [FileReplacement], failed: [String], placed: [String: String], renameLater: [String: String]) {
        let fm = FileManager.default
        var done: [FileReplacement] = []
        var failed: [String] = []
        var placed: [String: String] = [:]
        var renameLater: [String: String] = [:]
        func sameName(_ replacement: FileReplacement) -> Bool {
            Self.url(replacement.added).lastPathComponent.compare(Self.url(replacement.old).lastPathComponent, options: .caseInsensitive) == .orderedSame
        }
        var waiting: [String: String] = [:]
        var moves: [String: String] = [:]
        for (path, replacement) in staged.sorted(by: { $0.key < $1.key }) {
            let old = Self.url(replacement.old)
            guard sameName(replacement) else {
                moves[path] = Self.uniqueURL(for: Self.url(replacement.added).lastPathComponent, in: old.deletingLastPathComponent()).path
                continue
            }
            do {
                // The old file waits in the Inactive folder, where it stays in the library, off, should Cicero stop.
                let aside = Self.uniqueURL(for: old.lastPathComponent, in: try locations.inactiveFolderForNewFiles())
                try Self.moveItem(old, to: aside)
                waiting[replacement.old] = aside.path
            } catch {
                try? fm.removeItem(atPath: path)
                failed.append(replacement.old)
            }
        }
        // macOS keeps a font off by its file's path and PostScript name, and lets go of a gone file's entry a moment later: a new file at that path would come on as it does.
        let remembered = await registrar.waitUntilForgotten(waiting.keys.sorted(), timeout: forgetWait, every: .milliseconds(100))
        for (path, replacement) in staged where waiting[replacement.old] != nil {
            let old = Self.url(replacement.old)
            if remembered.contains(replacement.old) {
                let name = old.deletingPathExtension().lastPathComponent + " 2" + (old.pathExtension.isEmpty ? "" : "." + old.pathExtension)
                moves[path] = Self.uniqueURL(for: name, in: old.deletingLastPathComponent()).path
            } else {
                moves[path] = old.path
            }
        }
        let moved = await moveIntoFontsFolderOff(moves)
        for (path, replacement) in staged.sorted(by: { $0.key < $1.key }) where moves[path] != nil {
            let aside = waiting[replacement.old]
            guard let new = moved.placed[path] else {
                try? fm.removeItem(atPath: path)
                if let aside { await putBack(aside, at: replacement.old, remembered: remembered.contains(replacement.old)) }
                failed.append(replacement.old)
                continue
            }
            if didTrash(Self.url(aside ?? replacement.old)) {
                done.append(replacement)
                if new != replacement.old { placed[replacement.old] = new }
                if aside != nil, new != replacement.old { renameLater[new] = replacement.old }
            } else if aside != nil {
                done.append(replacement)
            } else {
                try? fm.removeItem(atPath: new)
                failed.append(replacement.old)
            }
        }
        return (done, failed, placed, renameLater)
    }

    func replaceIntoLibrary(_ staged: [String: FileReplacement]) -> (done: [FileReplacement], failed: [String], placed: [String: String]) {
        let fm = FileManager.default
        var done: [FileReplacement] = []
        var failed: [String] = []
        var placed: [String: String] = [:]
        for (path, replacement) in staged.sorted(by: { $0.key < $1.key }) {
            let old = Self.url(replacement.old)
            let folder = installFolder(for: replacement.added, family: nil)
            let new = Self.uniqueURL(for: old.lastPathComponent, in: folder)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.moveItem(at: Self.url(path), to: new)
            } catch {
                try? fm.removeItem(atPath: path)
                removeEmptyFolders(around: new.path)
                failed.append(replacement.old)
                continue
            }
            do {
                _ = try trash(old)
                done.append(replacement)
                placed[replacement.old] = new.path
            } catch {
                try? fm.removeItem(at: new)
                removeEmptyFolders(around: new.path)
                failed.append(replacement.old)
            }
        }
        return (done, failed, placed)
    }

    @concurrent
    public func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String> {
        await registrar.waitUntilForgotten(paths, timeout: timeout, every: every)
    }

    @concurrent
    public func renameBack(_ pending: [String: String], records: ActivationRecords) async -> [String: String] {
        let fm = FileManager.default
        let ready = pending.filter { interim, original in
            !fm.fileExists(atPath: original) && fm.fileExists(atPath: interim) && isInsideFontsFolder(interim)
                && Self.url(interim).deletingLastPathComponent() == Self.url(original).deletingLastPathComponent()
                && records.temporary[interim] == nil && !registrar.isActive(Self.url(interim))
        }
        guard !ready.isEmpty else { return [:] }
        let remembered = await registrar.waitUntilForgotten(ready.values.sorted(), timeout: .zero, every: .zero)
        var waiting: [String: (interim: String, original: String)] = [:]
        for (interim, original) in ready.sorted(by: { $0.key < $1.key }) where !remembered.contains(original) {
            // Renamed where it is, a file would lose being off, so it leaves for the Inactive folder and goes in again.
            guard let folder = try? locations.inactiveFolderForNewFiles() else { continue }
            let aside = Self.uniqueURL(for: Self.url(interim).lastPathComponent, in: folder)
            guard (try? Self.moveItem(Self.url(interim), to: aside)) != nil else { continue }
            waiting[aside.path] = (interim, original)
        }
        guard !waiting.isEmpty else { return [:] }
        let moved = await moveIntoFontsFolderOff(waiting.mapValues(\.original), exactly: true)
        var renamed: [String: String] = [:]
        for (aside, file) in waiting {
            if let path = moved.placed[aside] { renamed[file.interim] = path }
        }
        return renamed
    }

    private func putBack(_ aside: String, at old: String, remembered: Bool) async {
        // One macOS still remembers stays in the Inactive folder: put back, it would come on as macOS lets go of the entry.
        guard !remembered else { return }
        _ = await moveIntoFontsFolderOff([aside: old])
    }
}
