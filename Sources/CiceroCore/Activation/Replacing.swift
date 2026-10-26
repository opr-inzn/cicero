import CoreText
import Foundation

extension ActivationEngine {
    /// Replace (see `AddedDuplicate.replacements`): each of the library's files goes to the Trash and a copy of the added
    /// file takes its place, under its name, in its folder, on or off as it was. One that's on goes off for the moment
    /// that takes and on again the way it was: in place, until Cicero quits, or from a Fonts folder. One that's off in a
    /// Fonts folder has its copy go in off (see `moveIntoFontsFolderOff`), as macOS turns on whatever arrives there; see
    /// `replaceOff`. The copy is made in Cicero's staging folder first, so a file whose copy can't be made or go in, or
    /// that can't go to the Trash, stays as it was. Its paths stay, so the records and everything the user put it in do
    /// too, but for an off one that went in under another name (`placed` says where). `moving`, an added file that took
    /// every place it was meant for goes, as activating by moving does.
    @concurrent
    public func replace(_ replacements: [FileReplacement], moving: Bool, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        let olds = replacements.map(\.old)
        let persistent = olds.filter { records.inPlace.contains($0) || isInsideUserFonts($0) && registrar.isActive(Self.url($0)) }
        let session = olds.filter { records.temporary[$0] != nil }
        let off = Set(olds.filter { isInsideFontsFolder($0) && records.temporary[$0] == nil && !registrar.isActive(Self.url($0)) })
        var records = records
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }

        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        var done: [FileReplacement] = []
        var failed: [String] = []
        var placed: [String: String] = [:]
        var renameLater: [String: String] = [:]
        // Staged copy → the replacement it's for, of those that go in off.
        var goingInOff: [String: FileReplacement] = [:]
        for replacement in replacements {
            let old = Self.url(replacement.old)
            let staged = staging.appendingPathComponent(UUID().uuidString + "-" + old.lastPathComponent, isDirectory: false)
            do {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try fm.copyItem(at: Self.url(replacement.added), to: staged)
            } catch {
                try? fm.removeItem(at: staged)
                failed.append(replacement.old)
                continue
            }
            if off.contains(replacement.old) {
                goingInOff[staged.path] = replacement
                continue
            }
            do {
                try trash(old)
            } catch {
                try? fm.removeItem(at: staged)
                failed.append(replacement.old)
                continue
            }
            do {
                try fm.moveItem(at: staged, to: old)
                done.append(replacement)
            } catch {
                // The old file is in the Trash, to put back from there.
                try? fm.removeItem(at: staged)
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

        // On again, as it was: the new file where it went in, the old one where it stayed.
        let back = { (paths: [String]) in paths.filter { fm.fileExists(atPath: $0) } }
        if !back(persistent).isEmpty { _ = await registerAndConfirm(back(persistent), scope: .persistent) }
        if !back(session).isEmpty { _ = await registerAndConfirm(back(session), scope: .session) }

        // Where each new file is.
        func new(_ replacement: FileReplacement) -> String { placed[replacement.old] ?? replacement.old }
        if moving {
            for (added, copies) in Dictionary(grouping: done, by: \.added) where !Self.isProtected(added) {
                let meant = replacements.filter { $0.added == added }.count
                guard copies.count == meant, copies.allSatisfy({ Self.isIdenticalCopy(new($0), of: added) }) else { continue }
                try? fm.removeItem(atPath: added)
            }
        }

        // "Replaced Inter. The old file is in the Trash", and what couldn't be, by name: ". Couldn’t replace Roboto".
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

    /// Replaces files that are off in a Fonts folder with the staged copies (staged path → its replacement). macOS keeps a
    /// font off by its file's path and PostScript name, and lets go of a gone file's entry a moment later: a new file at
    /// that path with those font names would come on with it (tested in a macOS 26 VM). So the new file takes the old
    /// one's path only once macOS has let go of the old one: the old file waits in Cicero's Inactive folder meanwhile, where
    /// it stays in the library, off, should Cicero stop, then goes to the Trash. One macOS hasn't let go of within
    /// `forgetWait` gets "Name 2.otf" instead (`renameLater` says what for), as does an added file of another name its
    /// own. Any that can't go in leave the old one as it was.
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
        // Old path → where the old file waits.
        var waiting: [String: String] = [:]
        var moves: [String: String] = [:]
        for (path, replacement) in staged.sorted(by: { $0.key < $1.key }) {
            let old = Self.url(replacement.old)
            guard sameName(replacement) else {
                // While the old file is still there, so never its path.
                moves[path] = Self.uniqueURL(for: Self.url(replacement.added).lastPathComponent, in: old.deletingLastPathComponent()).path
                continue
            }
            let aside = Self.uniqueURL(for: old.lastPathComponent, in: locations.inactiveFolder)
            do {
                try fm.createDirectory(at: locations.inactiveFolder, withIntermediateDirectories: true)
                try Self.move(old, to: aside)
                waiting[replacement.old] = aside.path
            } catch {
                try? fm.removeItem(atPath: path)
                failed.append(replacement.old)
            }
        }
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
                // Back in the staging folder; the old file goes back as it was.
                try? fm.removeItem(atPath: path)
                if let aside { await putBack(aside, at: replacement.old, remembered: remembered.contains(replacement.old)) }
                failed.append(replacement.old)
                continue
            }
            if (try? trash(Self.url(aside ?? replacement.old))) != nil {
                done.append(replacement)
                if new != replacement.old { placed[replacement.old] = new }
                if aside != nil, new != replacement.old { renameLater[new] = replacement.old }
            } else if aside != nil {
                // In the Inactive folder, the old one stays in the library, off, beside the new one.
                done.append(replacement)
            } else {
                // The old one stays, off; the new one goes again, before macOS has it for long.
                try? fm.removeItem(atPath: new)
                failed.append(replacement.old)
            }
        }
        return (done, failed, placed, renameLater)
    }

    /// Waits, off the operation queue, until macOS no longer names these paths as fonts it has off (see
    /// `FontRegistrar.waitUntilForgotten`). Returns the paths it still names.
    @concurrent
    public func waitUntilForgotten(_ paths: [String], timeout: Duration, every: Duration) async -> Set<String> {
        await registrar.waitUntilForgotten(paths, timeout: timeout, every: every)
    }

    /// Files Replace put in as "Name 2.otf" (`ActivationResult.renameLater`: their path → the one meant for them) take
    /// their name, once macOS has let go of the old file there: renamed, they'd lose being off, so each leaves for the
    /// Inactive folder and goes in again the way `moveIntoFontsFolderOff` does it, on for a few hundredths of a second.
    /// Only while nothing changed: the name is free, macOS no longer names it, and the file is still there in the Fonts
    /// folder, off, and not on for a while; otherwise it stays as it is. One that won't go in stays in the Inactive
    /// folder, off: put back as "Name 2", macOS would turn it on. Returns the files renamed, from → to.
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
        // Where each waits → (its "Name 2" path, the path meant for it).
        var waiting: [String: (interim: String, original: String)] = [:]
        for (interim, original) in ready.sorted(by: { $0.key < $1.key }) where !remembered.contains(original) {
            let aside = Self.uniqueURL(for: Self.url(interim).lastPathComponent, in: locations.inactiveFolder)
            guard (try? fm.createDirectory(at: locations.inactiveFolder, withIntermediateDirectories: true)) != nil,
                  (try? Self.move(Self.url(interim), to: aside)) != nil
            else { continue }
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

    /// An old file that waited in the Inactive folder goes back where it was, off; one macOS still remembers there stays in
    /// the Inactive folder, off, as putting it back would have it come on with the entry going.
    private func putBack(_ aside: String, at old: String, remembered: Bool) async {
        guard !remembered else { return }
        _ = await moveIntoFontsFolderOff([aside: old])
    }
}
