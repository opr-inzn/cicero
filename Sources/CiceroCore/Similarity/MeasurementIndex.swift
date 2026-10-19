import CoreText
import Foundation
import Synchronization

/// Measures every family's letters (its regular face's, see `LetterMeasurements`) in the background, caches them on
/// disk by file stamp, as `CoverageIndex` does coverage, and answers lookups from any thread.
public final class MeasurementIndex: Sendable {
    private let file: URL
    private let state = Mutex(State())
    /// Writes the cache one save at a time, after `update` has returned.
    private let saveQueue = DispatchQueue(label: "Cicero.MeasurementIndex.save", qos: .utility)

    /// Raised whenever measuring changes, so measurements from before are made again.
    static let version = 1

    private struct Entry: Sendable {
        var stamp: CoverageStamp
        /// nil for a face that hasn't the letters to measure.
        var measurements: LetterMeasurements?
    }

    private struct State: Sendable {
        var entries: [FaceID: Entry] = [:]
        var loaded = false
        var dirty = false
    }

    public init(caches: URL) {
        file = caches.appendingPathComponent("letters.plist", isDirectory: false)
    }

    /// Measures what's missing at low priority; cheap when nothing changed. `progress` reports (done, total) only
    /// when there's work. Cancellable. The cache is written afterwards.
    public func update(_ families: [Family], progress: @escaping @Sendable (Int, Int) -> Void) async {
        let signpost = Signposts.library.beginInterval("Letters")
        defer { Signposts.library.endInterval("Letters", signpost) }
        loadIfNeeded()
        let stamped = families.map { ($0.regular.face, CoverageStamp.of(path: $0.regular.face.path)) }
        let work = state.withLock { state in
            stamped.filter { face, stamp in state.entries[face.id]?.stamp != stamp }
        }
        if !work.isEmpty, !Task.isCancelled {
            let total = work.count
            progress(0, total)
            var done = 0
            await withTaskGroup(of: (FaceID, CoverageStamp, LetterMeasurements?).self) { group in
                var pending = work.makeIterator()
                func addNext() {
                    guard !Task.isCancelled, let (face, stamp) = pending.next() else { return }
                    group.addTask(priority: .utility) { (face.id, stamp, Self.measure(face)) }
                }
                for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
                for await (id, stamp, measurements) in group {
                    state.withLock {
                        $0.entries[id] = Entry(stamp: stamp, measurements: measurements)
                        $0.dirty = true
                    }
                    done += 1
                    progress(done, total)
                    addNext()
                }
            }
        }
        if let entries = entriesToSave(keeping: Set(families.map(\.regular.face.id))) {
            saveQueue.async { self.write(entries) }
        }
    }

    /// nil until measured, and for a face that hasn't the letters to measure.
    public func measurements(of face: FaceID) -> LetterMeasurements? {
        state.withLock { $0.entries[face]?.measurements }
    }

    /// Whether every one of these faces has been measured, letters or not.
    public func hasMeasured(_ faces: [FaceID]) -> Bool {
        state.withLock { state in faces.allSatisfy { state.entries[$0] != nil } }
    }

    public func clearCache() {
        state.withLock {
            $0.entries = [:]
            $0.dirty = false
        }
        saveQueue.async { try? FileManager.default.removeItem(at: self.file) }
    }

    /// Waits for the cache to be written.
    func waitForSave() {
        saveQueue.sync {}
    }

    /// The face as its file has it, a variable one at the regular weight, as previews show it; an installed font of
    /// the same name when the file can't be read, and nothing when neither exists.
    static func measure(_ face: FontFace) -> LetterMeasurements? {
        var descriptor = FontFiles.descriptor(for: face, in: FontLoader.shared.descriptors(at: face.path))
            ?? FontFiles.installedDescriptor(named: face.postScriptName)
        guard CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 0, nil)) as String == face.postScriptName else { return nil }
        if let axis = face.weightAxis {
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: Self.weightAxisID), min(max(400, axis.minimum), axis.maximum))
        }
        return LetterMeasurements.measure(CTFontCreateWithFontDescriptor(descriptor, 0, nil))
    }

    /// The 'wght' axis.
    private static let weightAxisID = 0x7767_6874

    // MARK: - Disk cache

    private func loadIfNeeded() {
        state.withLock { state in
            guard !state.loaded else { return }
            state.loaded = true
            guard let data = try? Data(contentsOf: file),
                  let cache = try? PropertyListDecoder().decode(CacheFile.self, from: data),
                  cache.version == Self.version
            else { return }
            let count = LetterMeasurements.Measure.allCases.count
            for entry in cache.entries {
                let values = entry.values.array(of: Float.self)
                guard values.isEmpty || values.count == count else { continue }
                state.entries[FaceID(path: entry.path, index: entry.index)] = Entry(
                    stamp: CoverageStamp(modified: entry.modified, size: entry.size),
                    measurements: values.isEmpty ? nil : LetterMeasurements(values: values)
                )
            }
        }
    }

    /// Drops faces that are no longer in the library, and returns the entries to write when something changed.
    private func entriesToSave(keeping known: Set<FaceID>) -> [FaceID: Entry]? {
        state.withLock { state in
            let kept = state.entries.filter { known.contains($0.key) }
            guard state.dirty || kept.count != state.entries.count else { return nil }
            state.entries = kept
            state.dirty = false
            return kept
        }
    }

    private func write(_ entries: [FaceID: Entry]) {
        let signpost = Signposts.library.beginInterval("Save letters")
        defer { Signposts.library.endInterval("Save letters", signpost) }
        let cache = CacheFile(version: Self.version, entries: entries.map { id, entry in
            CacheEntry(path: id.path, index: id.index, modified: entry.stamp.modified, size: entry.stamp.size,
                       values: Data(array: entry.measurements?.values ?? []))
        })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private struct CacheFile: Codable {
        var version: Int
        var entries: [CacheEntry]
    }

    private struct CacheEntry: Codable {
        var path: String
        var index: Int
        var modified: Double
        var size: Int64
        /// Empty for a face that hasn't the letters to measure.
        var values: Data
    }
}
