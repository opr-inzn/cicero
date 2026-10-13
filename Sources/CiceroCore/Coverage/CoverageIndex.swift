import CoreText
import Foundation
import Synchronization

/// What one face covers: its scalars and the languages it supports.
public struct FaceCoverage: Sendable {
    public let scalars: ScalarRanges
    /// Language ids (shared with every other face from the same catalog) and one bit per language.
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

    /// nil when the language isn't supported.
    public func support(for languageID: String) -> LanguageSupport? {
        guard let position = order.positions[languageID], LanguageBits.isSet(bits.base, position) else { return nil }
        return LanguageBits.isSet(bits.full, position) ? .full : .base
    }

    /// Supported language ids (base or full).
    public var supportedLanguages: [String] {
        order.ids.indices.filter { LanguageBits.isSet(bits.base, $0) }.map { order.ids[$0] }
    }

    public var supportedLanguageCount: Int {
        bits.base.reduce(0) { $0 + $1.nonzeroBitCount }
    }
}

/// Works out every family's coverage (its regular face) in the background, caches it on disk by file
/// stamp, and answers lookups from any thread.
public final class CoverageIndex: Sendable {
    private let file: URL
    private let languages: LanguageCatalog
    private let state = Mutex(State())
    /// Writes the cache one save at a time, after `update` has returned.
    private let saveQueue = DispatchQueue(label: "Cicero.CoverageIndex.save", qos: .utility)

    private struct Entry: Sendable {
        var stamp: CoverageStamp
        var coverage: FaceCoverage
    }

    private struct State: Sendable {
        var entries: [FaceID: Entry] = [:]
        var loaded = false
        var dirty = false
    }

    public init(caches: URL, languages: LanguageCatalog) {
        file = caches.appendingPathComponent("coverage-v2.plist", isDirectory: false)
        self.languages = languages
    }

    /// Computes what's missing at low priority; cheap when nothing changed. `progress` reports
    /// (done, total) only when there's work. Cancellable. The cache is written afterwards, without
    /// holding up the lists waiting for the results.
    public func update(_ families: [Family], progress: @escaping @Sendable (Int, Int) -> Void) async {
        let signpost = Signposts.library.beginInterval("Coverage")
        defer { Signposts.library.endInterval("Coverage", signpost) }
        loadIfNeeded()
        let stamped = families.map { ($0.regular.face, CoverageStamp.of(path: $0.regular.face.path)) }
        let work = state.withLock { state in
            stamped.filter { face, stamp in state.entries[face.id]?.stamp != stamp }
        }
        if !work.isEmpty, !Task.isCancelled {
            let total = work.count
            progress(0, total)
            var done = 0
            await withTaskGroup(of: (FaceID, CoverageStamp, FaceCoverage).self) { group in
                var pending = work.makeIterator()
                func addNext() {
                    guard !Task.isCancelled, let (face, stamp) = pending.next() else { return }
                    group.addTask(priority: .utility) { (face.id, stamp, self.compute(face)) }
                }
                for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
                for await (id, stamp, coverage) in group {
                    state.withLock {
                        $0.entries[id] = Entry(stamp: stamp, coverage: coverage)
                        $0.dirty = true
                    }
                    done += 1
                    progress(done, total)
                    addNext()
                }
            }
        }
        // What to keep is decided now, against these families; only the writing waits.
        if let entries = entriesToSave(keeping: Set(families.flatMap { $0.faces.map(\.id) })) {
            saveQueue.async { self.write(entries) }
        }
    }

    /// nil until computed.
    public func coverage(of face: FaceID) -> FaceCoverage? {
        state.withLock { $0.entries[face]?.coverage }
    }

    /// Computes now if needed (for the Info panel and glyph grid of any face).
    public func coverage(computing face: FontFace) async -> FaceCoverage {
        loadIfNeeded()
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

    public func clearCache() {
        state.withLock {
            $0.entries = [:]
            $0.dirty = false
        }
        // After any write already queued, so none can put the file back.
        saveQueue.async { try? FileManager.default.removeItem(at: self.file) }
    }

    /// Waits for the cache to be written.
    func waitForSave() {
        saveQueue.sync {}
    }

    // MARK: - Computing

    private func compute(_ face: FontFace) -> FaceCoverage {
        let scalars = Self.scalars(of: face)
        return FaceCoverage(scalars: scalars, order: languages.order, bits: languages.support(in: scalars))
    }

    /// The scalars the face's file says it covers; an installed font of the same name when the
    /// file can't be read, and nothing when neither exists.
    static func scalars(of face: FontFace) -> ScalarRanges {
        let descriptor = FontFiles.descriptor(for: face, in: FontLoader.shared.descriptors(at: face.path))
            ?? FontFiles.installedDescriptor(named: face.postScriptName)
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return .empty }
        return ScalarRanges(characterSet: CTFontCopyCharacterSet(font))
    }

    // MARK: - Disk cache

    private func loadIfNeeded() {
        state.withLock { state in
            guard !state.loaded else { return }
            state.loaded = true
            guard let data = try? Data(contentsOf: file),
                  let cache = try? PropertyListDecoder().decode(CacheFile.self, from: data),
                  cache.language == languages.dataVersion
            else { return }
            let order = languages.order
            for entry in cache.entries {
                let coverage = FaceCoverage(
                    scalars: ScalarRanges(bounds: entry.bounds.array(of: UInt32.self)), order: order,
                    bits: LanguageBits(base: entry.base.array(of: UInt64.self), full: entry.full.array(of: UInt64.self))
                )
                state.entries[FaceID(path: entry.path, index: entry.index)] = Entry(stamp: CoverageStamp(modified: entry.modified, size: entry.size), coverage: coverage)
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
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private struct CacheFile: Codable {
        /// The language data the bits were computed with.
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

/// A file's modification time and size, which is what tells a cached result is still good.
struct CoverageStamp: Hashable, Sendable {
    var modified: Double
    var size: Int64

    /// Stands for a file that isn't there, so its (empty) result isn't recomputed on every update.
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
