import CoreText
import Foundation
import Synchronization

public final class MeasurementIndex: Sendable {
    private let file: URL
    private let embedder: LetterEmbedding?
    private let weights: Bool
    private let state = Mutex(State())
    private let loadLock = Mutex(())
    private let saveQueue = DispatchQueue(label: "Cicero.MeasurementIndex.save", qos: .utility)

    public static let version = 11

    public struct Snapshot: Sendable {
        fileprivate let entries: [FaceID: Entry]

        public func measurements(of face: FaceID) -> LetterMeasurements? {
            entries[face]?.measurements
        }

        public func embedding(of face: FaceID) -> [Float]? {
            entries[face]?.embedding
        }

        public func tags(of face: FaceID) -> [Float]? {
            entries[face]?.tags
        }

        public func classifications(of face: FaceID) -> [Float]? {
            entries[face]?.classification
        }

        public func classification(of face: FaceID) -> (classification: Classification, likelihood: Float)? {
            guard let chances = entries[face]?.classification,
                  let best = chances.indices.max(by: { chances[$0] < chances[$1] }) else { return nil }
            return (LetterEmbedding.classifications[best], chances[best])
        }
    }

    fileprivate struct Entry: Sendable {
        var stamp: CoverageStamp
        var measurements: LetterMeasurements?
        var embedding: [Float]?
        var classification: [Float]?
        var tags: [Float]?
        var undrawable = false
    }

    private struct State: Sendable {
        var entries: [FaceID: Entry] = [:]
        var loaded = false
        var dirty = false
        var saveScheduled = false
        var generation = 0
        var active = 0
        var tagNames: [String]?
    }

    public init(caches: URL, embedder: LetterEmbedding? = nil, weights: Bool = false) {
        self.weights = weights
        file = caches.appendingPathComponent("letters.plist", isDirectory: false)
        self.embedder = embedder
    }

    public func update(_ families: [Family], progress: @escaping @Sendable (Int, Int) -> Void) async {
        let signpost = Signposts.library.beginInterval("Letters")
        defer { Signposts.library.endInterval("Letters", signpost) }
        loadIfNeeded()
        let run = state.withLock { state -> Int in
            state.generation += 1
            return state.generation
        }
        let faces = Self.measuredFaces(of: families, weights: weights)
        let stamped = faces.map { ($0, CoverageStamp.of(path: $0.path)) }
        let retries = embedder.map { !$0.hasFailed } ?? false
        let work = state.withLock { state in
            stamped.filter { face, stamp in
                guard let entry = state.entries[face.id], entry.stamp == stamp else { return true }
                return retries && entry.embedding == nil && entry.measurements != nil && !entry.undrawable
            }
        }
        let needsTagNames = retries && state.withLock { $0.tagNames == nil }
        if !work.isEmpty || needsTagNames, !Task.isCancelled {
            beginEmbedderUse()
            defer { endEmbedderUse() }
            await embedder?.prepare()
            guard !Task.isCancelled else { return }
            if let names = embedder?.tagNames {
                state.withLock { state in
                    guard state.generation == run, state.tagNames != names else { return }
                    state.tagNames = names
                    state.dirty = true
                }
            }
            if !work.isEmpty {
                let total = work.count
                let byFile = Dictionary(grouping: work, by: { $0.0.path }).values.map { $0 }
                progress(0, total)
                var done = 0
                var lastSave = ContinuousClock.now
                let embedder = embedder
                await withTaskGroup(of: [(FaceID, CoverageStamp, LetterMeasurements?, LetterEmbedding.Outcome?)].self) { group in
                    var pending = byFile.makeIterator()
                    func addNext() {
                        guard !Task.isCancelled, let fileWork = pending.next() else { return }
                        group.addTask(priority: .utility) {
                            let descriptors = FontFiles.descriptors(at: fileWork[0].0.path)
                            return fileWork.map { face, stamp in
                                let font = Self.font(face, in: descriptors)
                                return (face.id, stamp, font.flatMap { LetterMeasurements.measure($0) }, font.flatMap { embedder?.outcome($0) })
                            }
                        }
                    }
                    for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
                    for await results in group {
                        let shouldCheckpoint = state.withLock { state -> Bool in
                            guard state.generation == run else { return false }
                            var hit = false
                            for (id, stamp, measurements, outcome) in results {
                                let reading: LetterEmbedding.Reading? = if case .read(let reading) = outcome { reading } else { nil }
                                let undrawable = if case .undrawable = outcome { true } else { false }
                                state.entries[id] = Entry(stamp: stamp, measurements: measurements, embedding: reading?.embedding,
                                                          classification: reading?.classification, tags: reading?.tags, undrawable: undrawable)
                                state.dirty = true
                                done += 1
                                if done % 200 == 0 { hit = true }
                            }
                            return hit
                        }
                        if shouldCheckpoint, ContinuousClock.now - lastSave >= .seconds(5) {
                            lastSave = .now
                            scheduleSave()
                        }
                        progress(done, total)
                        addNext()
                    }
                }
            }
        }
        if !Task.isCancelled, pruneEntries(keeping: Set(faces.map(\.id)), generation: run) {
            scheduleSave()
        }
    }

    public func measuredFaceIDs(of families: [Family]) -> [FaceID] {
        Self.measuredFaces(of: families, weights: weights).map(\.id)
    }

    static func measuredFaces(of families: [Family], weights: Bool = false) -> [FontFace] {
        families.flatMap { family in
            var faces = [family.regular.face]
            let extraWeights = weights || (family.classification == .unclassified && !family.mixesSerifAndSans)
            for face in family.kinds.compactMap(family.representative(of:)) + (extraWeights ? family.weightNeighbors : [])
            where !faces.contains(where: { $0.id == face.id }) {
                faces.append(face.face)
            }
            return faces
        }
    }

    public func snapshot() -> Snapshot {
        state.withLock { Snapshot(entries: $0.entries) }
    }

    public func measurements(of face: FaceID) -> LetterMeasurements? {
        state.withLock { $0.entries[face]?.measurements }
    }

    public func embedding(of face: FaceID) -> [Float]? {
        state.withLock { $0.entries[face]?.embedding }
    }

    public func tags(of face: FaceID) -> [Float]? {
        state.withLock { $0.entries[face]?.tags }
    }

    public var tagNames: [String] {
        state.withLock { $0.tagNames } ?? []
    }

    public func inspect(_ font: CTFont, glyphMap: ((Character) -> CGGlyph?)? = nil) -> (measurements: LetterMeasurements?, reading: LetterEmbedding.Reading?) {
        beginEmbedderUse()
        defer { endEmbedderUse() }
        return (LetterMeasurements.measure(font, glyphMap: glyphMap), embedder?.read(font, glyphMap: glyphMap))
    }

    private func beginEmbedderUse() {
        state.withLock { $0.active += 1 }
    }

    private func endEmbedderUse() {
        let done = state.withLock { state -> Bool in
            state.active -= 1
            return state.active == 0
        }
        if done { embedder?.unload { self.state.withLock { $0.active == 0 } } }
    }

    public func classifications(of face: FaceID) -> [Float]? {
        state.withLock { $0.entries[face]?.classification }
    }

    public func classification(of face: FaceID) -> (classification: Classification, likelihood: Float)? {
        guard let chances = classifications(of: face),
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
            $0.generation += 1
            $0.entries = [:]
            $0.tagNames = nil
            $0.dirty = false
            $0.saveScheduled = false
            $0.loaded = true
        }
        saveQueue.async { try? FileManager.default.removeItem(at: self.file) }
    }

    public func flush() {
        saveQueue.sync { self.saveIfNeeded() }
    }

    func waitForSave() {
        saveQueue.sync {}
    }

    static func measure(_ face: FontFace) -> LetterMeasurements? {
        font(face).flatMap { LetterMeasurements.measure($0) }
    }

    static func font(_ face: FontFace, in descriptors: [CTFontDescriptor]? = nil) -> CTFont? {
        // From the file's own descriptors, never those kept for drawing, so what CoreText works out for measuring goes with the font.
        let descriptor = FontFiles.descriptor(for: face, in: descriptors ?? FontFiles.descriptors(at: face.path))
            ?? FontFiles.installedDescriptor(named: face.postScriptName)
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return nil }
        guard let axis = face.weightAxis else { return font }
        let weighted = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: AxisTag.weight), min(max(400, axis.minimum), axis.maximum))
        return CTFontCreateWithFontDescriptor(weighted, 0, nil)
    }

    // MARK: - Disk cache

    private func loadIfNeeded() {
        if state.withLock({ $0.loaded }) { return }
        loadLock.withLock { _ in
            guard let startGeneration = state.withLock({ $0.loaded ? nil : $0.generation }) else { return }
            var decoded: [FaceID: Entry] = [:]
            var tagNames: [String]?
            if let data = try? Data(contentsOf: file),
               let cache = try? PropertyListDecoder().decode(CacheFile.self, from: data),
               cache.version == Self.version {
                let count = LetterMeasurements.Measure.allCases.count
                decoded.reserveCapacity(cache.entries.count)
                tagNames = cache.tagNames
                for entry in cache.entries {
                    let values = entry.values.array(of: Float.self), embedding = entry.embedding.array(of: Float.self)
                    let classification = entry.classification.array(of: Float.self)
                    let tags = (entry.tags ?? Data()).array(of: Float.self)
                    guard values.isEmpty || values.count == count, embedding.isEmpty || embedding.count == LetterEmbedding.dimensions,
                          classification.isEmpty || classification.count == LetterEmbedding.classifications.count else { continue }
                    decoded[FaceID(path: entry.path, index: entry.index)] = Entry(
                        stamp: CoverageStamp(modified: entry.modified, size: entry.size),
                        measurements: values.isEmpty ? nil : LetterMeasurements(values: values),
                        embedding: embedding.isEmpty ? nil : embedding,
                        classification: classification.isEmpty ? nil : classification,
                        tags: tags.isEmpty ? nil : tags,
                        undrawable: entry.undrawable ?? false
                    )
                }
            }
            state.withLock { state in
                guard !state.loaded, state.generation == startGeneration else { return }
                for (id, entry) in decoded where state.entries[id] == nil { state.entries[id] = entry }
                if state.tagNames == nil { state.tagNames = tagNames }
                state.loaded = true
            }
        }
    }

    private func pruneEntries(keeping known: Set<FaceID>, generation: Int) -> Bool {
        state.withLock { state in
            guard state.generation == generation else { return false }
            let kept = state.entries.filter { known.contains($0.key) }
            guard state.dirty || kept.count != state.entries.count else { return false }
            state.entries = kept
            state.dirty = true
            return true
        }
    }

    private func scheduleSave() {
        let shouldEnqueue = state.withLock { state -> Bool in
            guard state.dirty, !state.saveScheduled else { return false }
            state.saveScheduled = true
            return true
        }
        guard shouldEnqueue else { return }
        saveQueue.async { self.saveIfNeeded() }
    }

    private func saveIfNeeded() {
        let snapshot: (entries: [FaceID: Entry], tagNames: [String]?, generation: Int)? = state.withLock { state in
            state.saveScheduled = false
            guard state.dirty else { return nil }
            state.dirty = false
            return (state.entries, state.tagNames, state.generation)
        }
        guard let snapshot else { return }
        if !write(snapshot.entries, tagNames: snapshot.tagNames) {
            state.withLock { state in
                if state.generation == snapshot.generation { state.dirty = true }
            }
        }
    }

    @discardableResult
    private func write(_ entries: [FaceID: Entry], tagNames: [String]?) -> Bool {
        let signpost = Signposts.library.beginInterval("Save letters")
        defer { Signposts.library.endInterval("Save letters", signpost) }
        let cache = CacheFile(version: Self.version, entries: entries.map { id, entry in
            CacheEntry(path: id.path, index: id.index, modified: entry.stamp.modified, size: entry.stamp.size,
                       values: Data(array: entry.measurements?.values ?? []), embedding: Data(array: entry.embedding ?? []),
                       classification: Data(array: entry.classification ?? []), tags: entry.tags.map { Data(array: $0) },
                       undrawable: entry.undrawable ? true : nil)
        }, tagNames: tagNames)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(cache) else { return false }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    private struct CacheFile: Codable {
        var version: Int
        var entries: [CacheEntry]
        var tagNames: [String]?
    }

    private struct CacheEntry: Codable {
        var path: String
        var index: Int
        var modified: Double
        var size: Int64
        var values: Data
        var embedding: Data
        var classification: Data
        var tags: Data?
        var undrawable: Bool?
    }
}
