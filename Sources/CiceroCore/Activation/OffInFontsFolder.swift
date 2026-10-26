import CoreText
import Foundation

extension ActivationEngine {
    /// How many files `moveIntoFontsFolderOff` registers at once.
    static let offBatchSize = 20

    /// Where `moveIntoFontsFolderOff` writes the files on their way in, until they're off.
    var turningOffList: URL { locations.support.appendingPathComponent("turning-off.json", isDirectory: false) }

    /// Moves files into a Fonts folder, off. macOS turns on whatever arrives in one, a second or so later, so each batch is
    /// registered at once and turned off right after: its fonts are on for a few hundredths of a second (about 20 ms for 1
    /// file or 20, in a macOS 26 VM), and macOS keeps them off from then on. Turning a file off before macOS has it doesn't
    /// stick. `moves` is each file → where it goes; one whose place is taken goes beside it, as "Name 2.otf". The files on
    /// their way in are written down first (see `finishTurningOff`), so stopping halfway leaves none on. One macOS won't
    /// take or won't turn off goes back where it was. Returns where each file went, and the files that stayed.
    public func moveIntoFontsFolderOff(_ moves: [String: String]) async -> (placed: [String: String], failed: [String]) {
        let fm = FileManager.default
        var placed: [String: String] = [:]
        var failed: [String] = []
        let all = moves.sorted { $0.key < $1.key }
        for start in stride(from: 0, to: all.count, by: Self.offBatchSize) {
            var moved: [(from: String, to: String)] = []
            for (from, to) in all[start..<min(start + Self.offBatchSize, all.count)] {
                let target = Self.url(to)
                let destination = Self.uniqueURL(for: target.lastPathComponent, in: target.deletingLastPathComponent())
                do {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try noteTurningOff(moved.map(\.to) + [destination.path])
                    try Self.move(Self.url(from), to: destination)
                    moved.append((from, destination.path))
                } catch {
                    failed.append(from)
                }
            }
            guard !moved.isEmpty else { continue }
            let paths = moved.map(\.to)
            let untaken = await registrar.register(paths.map(Self.url), scope: .persistent)
            let stillOn = await registrar.setEnabled(paths.filter { !untaken.contains($0) }.map(Self.url), false)
            for (from, to) in moved {
                guard untaken.contains(to) || stillOn.contains(to) else {
                    placed[from] = to
                    continue
                }
                // macOS would turn on one it didn't take as soon as it noticed it, and one that won't go off is on.
                if stillOn.contains(to) { _ = await registrar.unregister([Self.url(to)], scope: .persistent) }
                try? Self.move(Self.url(to), to: Self.url(from))
                failed.append(from)
            }
            try? fm.removeItem(at: turningOffList)
        }
        return (placed, failed)
    }

    private func noteTurningOff(_ paths: [String]) throws {
        try FileManager.default.createDirectory(at: locations.support, withIntermediateDirectories: true)
        try JSONEncoder().encode(paths).write(to: turningOffList, options: .atomic)
    }

    /// At launch: files `moveIntoFontsFolderOff` was moving when Cicero stopped are turned off where they are, those that
    /// went on.
    public func finishTurningOff() async {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: turningOffList) else { return }
        let paths = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        let on = paths.filter { isInsideFontsFolder($0) && fm.fileExists(atPath: $0) && registrar.isActive(Self.url($0)) }
        if !on.isEmpty { _ = await registrar.setEnabled(on.map(Self.url), false) }
        try? fm.removeItem(at: turningOffList)
    }

    /// At launch: fonts earlier versions turned off by moving them out of ~/Library/Fonts into the Deactivated folder go
    /// where turning them on would put them, and stay off: into their family's folder in Cicero's Library when fonts are
    /// installed there, else back into ~/Library/Fonts (see `moveIntoFontsFolderOff`). Not one from an app's own folder,
    /// which goes back there when it's turned on, nor one that's on for now. Records naming a moved file as the original
    /// of a copy follow it. Returns how many files moved.
    public func emptyDeactivatedFolder(_ records: ActivationRecords) async -> (records: ActivationRecords, moved: Int) {
        let fm = FileManager.default
        let folder = locations.deactivated
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let files = names.sorted().map { folder.appendingPathComponent($0, isDirectory: false).path }.filter { path in
            var info = stat()
            return !(path as NSString).lastPathComponent.hasPrefix(".")
                && FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased())
                && lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
                && records.appFolderOrigins[path] == nil && records.temporary[path] == nil
                && !registrar.isActive(Self.url(path))
        }
        guard !files.isEmpty else { return (records, 0) }
        var placed: [String: String] = [:]
        var intoFontsFolder: [String: String] = [:]
        for path in files {
            let destination = installFolder(for: path, family: nil)
            if destination == locations.userFonts {
                intoFontsFolder[path] = destination.appendingPathComponent((path as NSString).lastPathComponent, isDirectory: false).path
                continue
            }
            // Fonts in Cicero's Library are on only while it has them registered: one put there is off.
            let target = Self.uniqueURL(for: (path as NSString).lastPathComponent, in: destination)
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                try Self.move(Self.url(path), to: target)
                placed[path] = target.path
            } catch {
                continue
            }
        }
        placed.merge(await moveIntoFontsFolderOff(intoFontsFolder).placed) { first, _ in first }
        var records = records
        for (copy, original) in records.installedCopies {
            if let moved = placed[original] { records.installedCopies[copy] = moved }
        }
        return (records, placed.count)
    }
}
