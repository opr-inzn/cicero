import CoreText
import Foundation
import Synchronization

public struct FaceCoverage: Sendable {
    public let scalars: ScalarRanges
    let order: LanguageOrder
    let bits: LanguageBits

    public init(scalars: ScalarRanges, languageSupport: [String: LanguageSupport]) {
        let order = LanguageOrder(ids: languageSupport.keys.sorted())
        var bits = LanguageBits(count: order.ids.count)
        for (position, id) in order.ids.enumerated() {
            LanguageBits.set(&bits.base, position)
            if languageSupport[id] == .full { LanguageBits.set(&bits.full, position) }
        }
        self.init(scalars: scalars, order: order, bits: bits)
    }

    init(scalars: ScalarRanges, order: LanguageOrder, bits: LanguageBits) {
        self.scalars = scalars
        self.order = order
        self.bits = bits
    }

    public func support(for languageID: String) -> LanguageSupport? {
        guard let position = order.positions[languageID], LanguageBits.isSet(bits.base, position) else { return nil }
        return LanguageBits.isSet(bits.full, position) ? .full : .base
    }

    public var supportedLanguages: [String] {
        order.ids.indices.filter { LanguageBits.isSet(bits.base, $0) }.map { order.ids[$0] }
    }

    public var supportedLanguageCount: Int {
        bits.base.reduce(0) { $0 + $1.nonzeroBitCount }
    }
}

public final class CoverageIndex: Sendable {
    private let file: URL
    private let oldFile: URL
    private let languages: LanguageCatalog
    private let state = Mutex(State())
    private let loadLock = Mutex(())
    private let saveQueue = DispatchQueue(label: "Cicero.CoverageIndex.save", qos: .utility)

    public struct Snapshot: Sendable {
        fileprivate let entries: [FaceID: Entry]

        public func coverage(of face: FaceID) -> FaceCoverage? {
            entries[face]?.coverage
        }
    }

    fileprivate struct Entry: Sendable {
        var stamp: CoverageStamp
        var coverage: FaceCoverage
    }

    private struct State: Sendable {
        var entries: [FaceID: Entry] = [:]
        var loaded = false
        var dirty = false
        var saveScheduled = false
        var generation = 0
    }

    public init(caches: URL, languages: LanguageCatalog) {
        file = caches.appendingPathComponent("coverage-v4.plist", isDirectory: false)
        oldFile = caches.appendingPathComponent("coverage-v3.plist", isDirectory: false)
        self.languages = languages
    }

    public func update(_ families: [Family], saves: Bool = true, progress: @escaping @Sendable (Int, Int) -> Void) async {
        let signpost = Signposts.library.beginInterval("Coverage")
        defer { Signposts.library.endInterval("Coverage", signpost) }
        _ = loadIfNeeded(removingOldFile: saves)
        let run = state.withLock { state -> Int in
            state.generation += 1
            return state.generation
        }
        let stamped = families.map { ($0.regular.face, CoverageStamp.of(path: $0.regular.face.path)) }
        let work = state.withLock { state in
            stamped.filter { face, stamp in state.entries[face.id]?.stamp != stamp }
        }
        if !work.isEmpty, !Task.isCancelled {
            let total = work.count
            progress(0, total)
            var done = 0
            var lastSave = ContinuousClock.now
            await withTaskGroup(of: (FaceID, CoverageStamp, FaceCoverage).self) { group in
                var pending = work.makeIterator()
                func addNext() {
                    guard !Task.isCancelled, let (face, stamp) = pending.next() else { return }
                    group.addTask(priority: .utility) { (face.id, stamp, self.compute(face)) }
                }
                for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
                for await (id, stamp, coverage) in group {
                    let updated = state.withLock { state -> Bool in
                        guard state.generation == run else { return false }
                        state.entries[id] = Entry(stamp: stamp, coverage: coverage)
                        state.dirty = true
                        done += 1
                        return true
                    }
                    if updated, saves, done % 200 == 0, ContinuousClock.now - lastSave >= .seconds(5) {
                        lastSave = .now
                        scheduleSave()
                    }
                    progress(done, total)
                    addNext()
                }
            }
        }
        if saves, !Task.isCancelled, pruneEntries(keeping: Set(families.flatMap { $0.faces.map(\.id) }), generation: run) {
            scheduleSave()
        }
    }

    public func coverage(of face: FaceID) -> FaceCoverage? {
        state.withLock { $0.entries[face]?.coverage }
    }

    public func snapshot() -> Snapshot {
        state.withLock { Snapshot(entries: $0.entries) }
    }

    public func coverage(computing face: FontFace) async -> FaceCoverage {
        _ = loadIfNeeded()
        let stamp = CoverageStamp.of(path: face.path)
        if let entry = state.withLock({ $0.entries[face.id] }), entry.stamp == stamp {
            return entry.coverage
        }
        let coverage = await Task.detached(priority: .userInitiated) { self.compute(face) }.value
        state.withLock {
            $0.entries[face.id] = Entry(stamp: stamp, coverage: coverage)
            $0.dirty = true
        }
        return coverage
    }

    @discardableResult
    public func loadSaved(removingOldFile: Bool = false) -> Bool {
        loadIfNeeded(removingOldFile: removingOldFile)
    }

    public func clearCache() {
        state.withLock {
            $0.generation += 1
            $0.entries = [:]
            $0.dirty = false
            $0.saveScheduled = false
            $0.loaded = true
        }
        saveQueue.async { try? FileManager.default.removeItem(at: self.file) }
    }

    public func flush() {
        saveQueue.sync { self.saveIfNeeded() }
    }

    public func waitForSave() {
        saveQueue.sync {}
    }

    // MARK: - Computing

    private func compute(_ face: FontFace) -> FaceCoverage {
        let scalars = Self.scalars(of: face)
        return FaceCoverage(scalars: scalars, order: languages.order, bits: languages.support(in: scalars))
    }

    static func scalars(of face: FontFace) -> ScalarRanges {
        // From the file's own descriptors, never those kept for drawing: the outline of every glyph asked for its bounds stays as long as the font does.
        let descriptor = FontFiles.descriptor(for: face, in: FontFiles.descriptors(at: face.path))
            ?? FontFiles.installedDescriptor(named: face.postScriptName)
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return .empty }
        return EmptyGlyphs(font: font).drawn(CharacterMap.characters(of: font))
    }

    // MARK: - Disk cache

    @discardableResult
    private func loadIfNeeded(removingOldFile: Bool = true) -> Bool {
        if state.withLock({ $0.loaded }) { return false }
        return loadLock.withLock { _ in
            guard let startGeneration = state.withLock({ $0.loaded ? nil : $0.generation }) else { return false }
            if removingOldFile { try? FileManager.default.removeItem(at: oldFile) }
            var decoded: [FaceID: Entry] = [:]
            if let data = try? Data(contentsOf: file),
               let cache = try? PropertyListDecoder().decode(CacheFile.self, from: data),
               cache.language == languages.dataVersion {
                let order = languages.order
                decoded.reserveCapacity(cache.entries.count)
                for entry in cache.entries {
                    let bounds = entry.bounds.array(of: UInt32.self)
                    guard ScalarRanges.isValid(bounds: bounds) else { continue }
                    let coverage = FaceCoverage(
                        scalars: ScalarRanges(bounds: bounds), order: order,
                        bits: LanguageBits(base: entry.base.array(of: UInt64.self), full: entry.full.array(of: UInt64.self))
                    )
                    decoded[FaceID(path: entry.path, index: entry.index)] = Entry(stamp: CoverageStamp(modified: entry.modified, size: entry.size), coverage: coverage)
                }
            }
            return state.withLock { state in
                guard !state.loaded, state.generation == startGeneration else { return false }
                for (id, entry) in decoded where state.entries[id] == nil { state.entries[id] = entry }
                state.loaded = true
                return !decoded.isEmpty
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
        let snapshot: (entries: [FaceID: Entry], generation: Int)? = state.withLock { state in
            state.saveScheduled = false
            guard state.dirty else { return nil }
            state.dirty = false
            return (state.entries, state.generation)
        }
        guard let snapshot else { return }
        if !write(snapshot.entries) {
            state.withLock { state in
                if state.generation == snapshot.generation { state.dirty = true }
            }
        }
    }

    @discardableResult
    private func write(_ entries: [FaceID: Entry]) -> Bool {
        let signpost = Signposts.library.beginInterval("Save coverage")
        defer { Signposts.library.endInterval("Save coverage", signpost) }
        let cache = CacheFile(language: languages.dataVersion, entries: entries.map { id, entry in
            CacheEntry(
                path: id.path, index: id.index, modified: entry.stamp.modified, size: entry.stamp.size,
                bounds: Data(array: entry.coverage.scalars.bounds),
                base: Data(array: entry.coverage.bits.base), full: Data(array: entry.coverage.bits.full)
            )
        })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(cache) else { return false }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    private struct CacheFile: Codable {
        var language: String
        var entries: [CacheEntry]
    }

    private struct CacheEntry: Codable {
        var path: String
        var index: Int
        var modified: Double
        var size: Int64
        var bounds: Data
        var base: Data
        var full: Data
    }
}

struct CoverageStamp: Hashable, Sendable {
    var modified: Double
    var size: Int64

    static let missing = CoverageStamp(modified: 0, size: -1)

    static func of(path: String) -> CoverageStamp {
        var info = stat()
        guard stat(path, &info) == 0 else { return .missing }
        return CoverageStamp(modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9, size: Int64(info.st_size))
    }
}

extension Data {
    init<T>(array: [T]) {
        self = array.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func array<T>(of type: T.Type) -> [T] {
        let count = self.count / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            _ = copyBytes(to: buffer)
            initialized = count
        }
    }
}
