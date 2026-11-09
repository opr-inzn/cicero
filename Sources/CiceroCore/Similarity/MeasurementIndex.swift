import CoreText
import Foundation
import Synchronization

public final class MeasurementIndex: Sendable {
    private let file: URL
    private let embedder: LetterEmbedding?
    private let state = Mutex(State())
    private let saveQueue = DispatchQueue(label: "Cicero.MeasurementIndex.save", qos: .utility)

    public static let version = 9

    private struct Entry: Sendable {
        var stamp: CoverageStamp
        var measurements: LetterMeasurements?
        var embedding: [Float]?
        var classification: [Float]?
    }

    private struct State: Sendable {
        var entries: [FaceID: Entry] = [:]
        var loaded = false
        var dirty = false
    }

    public init(caches: URL, embedder: LetterEmbedding? = nil) {
        file = caches.appendingPathComponent("letters.plist", isDirectory: false)
        self.embedder = embedder
    }

    public func update(_ families: [Family], progress: @escaping @Sendable (Int, Int) -> Void) async {
        let signpost = Signposts.library.beginInterval("Letters")
        defer { Signposts.library.endInterval("Letters", signpost) }
        loadIfNeeded()
        let faces = Self.measuredFaces(of: families)
        let stamped = faces.map { ($0, CoverageStamp.of(path: $0.path)) }
        let work = state.withLock { state in
            stamped.filter { face, stamp in state.entries[face.id]?.stamp != stamp }
        }
        if !work.isEmpty, !Task.isCancelled {
            let total = work.count
            progress(0, total)
            var done = 0
            let embedder = embedder
            await withTaskGroup(of: (FaceID, CoverageStamp, LetterMeasurements?, LetterEmbedding.Reading?).self) { group in
                var pending = work.makeIterator()
                func addNext() {
                    guard !Task.isCancelled, let (face, stamp) = pending.next() else { return }
                    group.addTask(priority: .utility) {
                        let font = Self.font(face)
                        return (face.id, stamp, font.flatMap(LetterMeasurements.measure), font.flatMap { embedder?.read($0) })
                    }
                }
                for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
                for await (id, stamp, measurements, reading) in group {
                    state.withLock {
                        $0.entries[id] = Entry(stamp: stamp, measurements: measurements, embedding: reading?.embedding,
                                               classification: reading?.classification)
                        $0.dirty = true
                    }
                    done += 1
                    progress(done, total)
                    addNext()
                }
            }
        }
        if let entries = entriesToSave(keeping: Set(faces.map(\.id))) {
            saveQueue.async { self.write(entries) }
        }
    }

    static func measuredFaces(of families: [Family]) -> [FontFace] {
        families.flatMap { family in
            var faces = [family.regular.face]
            for kind in family.kinds {
                if let face = family.representative(of: kind)?.face, !faces.contains(where: { $0.id == face.id }) { faces.append(face) }
            }
            return faces
        }
    }

    public func measurements(of face: FaceID) -> LetterMeasurements? {
        state.withLock { $0.entries[face]?.measurements }
    }

    public func embedding(of face: FaceID) -> [Float]? {
        state.withLock { $0.entries[face]?.embedding }
    }

    public func classification(of face: FaceID) -> (classification: Classification, likelihood: Float)? {
        guard let chances = state.withLock({ $0.entries[face]?.classification }),
              let best = chances.indices.max(by: { chances[$0] < chances[$1] }) else { return nil }
        return (LetterEmbedding.classifications[best], chances[best])
    }

    public func hasMeasured(_ faces: [FaceID]) -> Bool {
        state.withLock { state in faces.allSatisfy { state.entries[$0] != nil } }
    }

    public func loadSaved() {
        loadIfNeeded()
    }

    public func clearCache() {
        state.withLock {
            $0.entries = [:]
            $0.dirty = false
        }
        saveQueue.async { try? FileManager.default.removeItem(at: self.file) }
    }

    func waitForSave() {
        saveQueue.sync {}
    }

    static func measure(_ face: FontFace) -> LetterMeasurements? {
        font(face).flatMap(LetterMeasurements.measure)
    }

    static func font(_ face: FontFace) -> CTFont? {
        // From the file's own descriptors, never those kept for drawing, so what CoreText works out for measuring goes with the font.
        var descriptor = FontFiles.descriptor(for: face, in: FontFiles.descriptors(at: face.path))
            ?? FontFiles.installedDescriptor(named: face.postScriptName)
        guard CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 0, nil)) as String == face.postScriptName else { return nil }
        if let axis = face.weightAxis {
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: AxisTag.weight), min(max(400, axis.minimum), axis.maximum))
        }
        return CTFontCreateWithFontDescriptor(descriptor, 0, nil)
    }

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
                let values = entry.values.array(of: Float.self), embedding = entry.embedding.array(of: Float.self)
                let classification = entry.classification.array(of: Float.self)
                guard values.isEmpty || values.count == count, embedding.isEmpty || embedding.count == LetterEmbedding.dimensions,
                      classification.isEmpty || classification.count == LetterEmbedding.classifications.count else { continue }
                state.entries[FaceID(path: entry.path, index: entry.index)] = Entry(
                    stamp: CoverageStamp(modified: entry.modified, size: entry.size),
                    measurements: values.isEmpty ? nil : LetterMeasurements(values: values),
                    embedding: embedding.isEmpty ? nil : embedding,
                    classification: classification.isEmpty ? nil : classification
                )
            }
        }
    }

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
                       values: Data(array: entry.measurements?.values ?? []), embedding: Data(array: entry.embedding ?? []),
                       classification: Data(array: entry.classification ?? []))
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
        var values: Data
        var embedding: Data
        var classification: Data
    }
}
