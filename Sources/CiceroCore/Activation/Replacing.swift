import CoreText
import Foundation

extension ActivationEngine {
    /// Replace (see `AddedDuplicate.replacements`): each of the library's files goes to the Trash and a copy of the added
    /// file takes its place, under its name, in its folder, on or off as it was. One that's on goes off for the moment
    /// that takes and on again the way it was: in place, until Cicero quits, or from a Fonts folder. One that's off in a
    /// Fonts folder has its copy go in off first (see `moveIntoFontsFolderOff`), as macOS turns on whatever arrives there,
    /// beside it under the added file's name, or "Name 2.otf" (`placed` says where): macOS letting go of the old file a
    /// moment later would turn on a new one of that path and font names. The old one goes to the Trash after that. The copy
    /// is made in Cicero's staging folder first, so a file whose copy can't be made or go in, or that can't go to the
    /// Trash, stays as it was. Other paths stay, so the records and everything the user put it in do too. `moving`, an
    /// added file that took every place it was meant for goes, as activating by moving does.
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
            // The old file is still there, so the new one never takes its path.
            let moves = goingInOff.mapValues { replacement in
                Self.uniqueURL(for: Self.url(replacement.added).lastPathComponent, in: Self.url(replacement.old).deletingLastPathComponent()).path
            }
            let moved = await moveIntoFontsFolderOff(moves)
            for (staged, replacement) in goingInOff.sorted(by: { $0.key < $1.key }) {
                guard let path = moved.placed[staged] else {
                    // Back in the staging folder; the old file is as it was.
                    try? fm.removeItem(atPath: staged)
                    failed.append(replacement.old)
                    continue
                }
                do {
                    try trash(Self.url(replacement.old))
                    done.append(replacement)
                    placed[replacement.old] = path
                    records.installedCopies[replacement.old] = nil
                } catch {
                    // The old one stays, off; the new one goes again, before macOS has it for long.
                    try? fm.removeItem(atPath: path)
                    failed.append(replacement.old)
                }
            }
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
        return result
    }
}
