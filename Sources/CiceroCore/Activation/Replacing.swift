import CoreText
import Foundation

extension ActivationEngine {
    /// Replace (see `AddedDuplicate.replacements`): each of the library's files goes to the Trash and a copy of the added
    /// file takes its place, under its name, in its folder, on or off as it was. One that's on goes off for the moment
    /// that takes and on again the way it was: in place, until Cicero quits, or from a Fonts folder. The copy is made in
    /// Cicero's staging folder first, so a file whose copy can't be made, or that can't go to the Trash, stays as it
    /// was. Its paths stay, so the records and everything the user put it in do too. `moving`, an added file that took
    /// every place it was meant for goes, as activating by moving does.
    @concurrent
    public func replace(_ replacements: [FileReplacement], moving: Bool, records: ActivationRecords) async -> ActivationResult {
        let fm = FileManager.default
        let olds = replacements.map(\.old)
        let persistent = olds.filter { records.inPlace.contains($0) || isInsideUserFonts($0) && registrar.isActive(Self.url($0)) }
        let session = olds.filter { records.temporary[$0] != nil }
        if !persistent.isEmpty { _ = await registrar.unregister(persistent.map(Self.url), scope: .persistent) }
        if !session.isEmpty { _ = await registrar.unregister(session.map(Self.url), scope: .session) }

        let staging = locations.support.appendingPathComponent("Staging", isDirectory: true)
        var done: [FileReplacement] = []
        var failed: [String] = []
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

        // On again, as it was: the new file where it went in, the old one where it stayed.
        let back = { (paths: [String]) in paths.filter { fm.fileExists(atPath: $0) } }
        if !back(persistent).isEmpty { _ = await registerAndConfirm(back(persistent), scope: .persistent) }
        if !back(session).isEmpty { _ = await registerAndConfirm(back(session), scope: .session) }

        if moving {
            let placed = Dictionary(grouping: done, by: \.added)
            for (added, copies) in placed where !Self.isProtected(added) {
                let meant = replacements.filter { $0.added == added }.count
                guard copies.count == meant, copies.allSatisfy({ Self.isIdenticalCopy($0.old, of: added) }) else { continue }
                try? fm.removeItem(atPath: added)
            }
        }

        // "Replaced Inter. The old file is in the Trash", and what couldn't be, by name: ". Couldn’t replace Roboto".
        var message: String
        if done.isEmpty {
            message = Self.message("Replaced", "replace", succeeded: 0, failed: failed.count,
                                   undone: FontNames.describe(FontNames.fonts(inFiles: failed)))
        } else {
            let names = FontNames.describe(FontNames.fonts(inFiles: done.map(\.old))) ?? (done.count == 1 ? "1 file" : "\(done.count) files")
            message = "Replaced \(names). " + (done.count == 1 ? "The old file is in the Trash" : "The old files are in the Trash")
            if !failed.isEmpty {
                let undone = FontNames.describe(FontNames.fonts(inFiles: failed.filter { fm.fileExists(atPath: $0) }))
                message += ". Couldn’t replace " + (undone ?? (failed.count == 1 ? "1 file" : "\(failed.count) files"))
            }
        }
        return ActivationResult(records: records, succeeded: done.count, failed: failed, message: message)
    }
}
