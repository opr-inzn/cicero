import CoreText
import Foundation
import Observation

/// Which Unicode scalars each face covers, and from that which languages it supports according to
/// Hyperglot's data. One face stands for a family: its regular upright. Results are cached in
/// ~/Library/Caches/Point and worked out for the whole library in the background after every scan.
///
/// Only character coverage is checked. Hyperglot itself also shapes text with HarfBuzz to confirm
/// mark attachment, Arabic joining and Indic conjuncts; Point has no shaper, so a font can count as
/// supporting a language here that Hyperglot's command line would still reject.
@Observable @MainActor
final class CharacterCoverage {
    static let shared = CharacterCoverage()

    private(set) var isIndexing = false
    private(set) var indexedCount = 0
    private(set) var totalCount = 0
    /// Bumped as faces finish indexing; views that read coverage should depend on it.
    private(set) var generation = 0

    @ObservationIgnored nonisolated private let store = Store()
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    // MARK: Queries (any thread)

    nonisolated static func representative(of family: FontFamily) -> FontFace {
        family.face(nearestWeight: 400).face
    }

    nonisolated var languages: [Language] { Languages.all }

    /// nil until the family's representative face has been indexed.
    nonisolated func coverage(of family: FontFamily) -> FaceCoverage? {
        store.coverage(forFaceID: Self.representative(of: family).id)
    }

    nonisolated func coverage(of face: FontFace) -> FaceCoverage? {
        store.coverage(forFaceID: face.id)
    }

    /// The face's coverage, computed now (off the main thread) if it isn't known yet.
    nonisolated func coverage(computingFor face: FontFace) async -> FaceCoverage {
        let store = store
        return await Task.detached(priority: .userInitiated) { store.coverage(validatedFor: face) }.value
    }

    /// Whether the family supports a language (Hyperglot ISO 639-3 code) at the given level;
    /// nil while the family isn't indexed yet.
    nonisolated func supports(_ family: FontFamily, language iso: String, level: LanguageSupport = .base) -> Bool? {
        guard let coverage = coverage(of: family) else { return nil }
        guard let support = coverage.support(for: iso) else { return false }
        return support >= level
    }

    /// Families that have every character of the text, or miss at most `maxMissing` of them.
    nonisolated func matches(for text: String, in families: [FontFamily], maxMissing: Int = 0) -> TextMatches {
        let scalars = Self.scalars(in: text)
        var matches: [TextMatch] = []
        var unindexed = 0
        for family in families {
            guard let coverage = coverage(of: family) else {
                unindexed += 1
                continue
            }
            let missing = coverage.scalars.missing(from: scalars)
            if missing.count <= maxMissing {
                matches.append(TextMatch(family: family, missing: missing))
            }
        }
        // Families arrive in name order; keep that within each number of missing characters.
        let sorted = matches.enumerated().sorted { ($0.element.missing.count, $0.offset) < ($1.element.missing.count, $1.offset) }
        return TextMatches(matches: sorted.map(\.element), scalarCount: scalars.count, unindexed: unindexed)
    }

    nonisolated func families(supporting language: Language, in families: [FontFamily]) -> LanguageMatches {
        var result = LanguageMatches()
        for family in families {
            guard let coverage = coverage(of: family) else {
                result.unindexed += 1
                continue
            }
            switch coverage.support(for: language) {
            case .full: result.full.append(family)
            case .base: result.base.append(family)
            case nil: break
            }
        }
        return result
    }

    /// Unique scalars worth checking: whitespace and invisible controls aren't a font's job.
    nonisolated static func scalars(in text: String) -> [UInt32] {
        var seen = Set<UInt32>()
        return text.precomposedStringWithCanonicalMapping.unicodeScalars.compactMap { scalar in
            guard !scalar.properties.isWhitespace else { return nil }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned: return nil
            default: return seen.insert(scalar.value).inserted ? scalar.value : nil
            }
        }
    }

    // MARK: Indexing

    /// Indexes the representative face of every family at low priority. Cheap when nothing changed.
    func index(_ families: [FontFamily]) {
        let faces = families.map(Self.representative(of:))
        let presentPaths = Set(families.lazy.flatMap { $0.faces.map(\.face.path) })
        indexTask?.cancel()
        let store = store
        indexTask = Task.detached(priority: .utility) {
            store.index(faces, keepingPaths: presentPaths) { done, total in
                // Reported once before any work, so a pass with nothing to do never shows as indexing.
                Task { @MainActor in
                    self.indexedCount = done
                    self.totalCount = total
                    self.isIndexing = done < total
                    self.generation += 1
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.isIndexing = false
                self.generation += 1
            }
        }
    }

    // MARK: Store

    /// Lock-protected coverage per face id, mirrored to a cache file.
    private final class Store: @unchecked Sendable {
        private struct Entry {
            var stamp: FaceCache.Stamp
            var coverage: FaceCoverage
        }

        private let lock = NSLock()
        private let loadLock = NSLock()
        private var entries: [String: Entry] = [:]
        private var loaded = false
        private var dirty = false

        func coverage(forFaceID id: String) -> FaceCoverage? {
            lock.lock()
            defer { lock.unlock() }
            return entries[id]?.coverage
        }

        /// The cached coverage if the file hasn't changed, else a fresh one.
        func coverage(validatedFor face: FontFace) -> FaceCoverage {
            loadIfNeeded()
            let stamp = FaceCache.stamp(of: face.path)
            lock.lock()
            let entry = entries[face.id]
            lock.unlock()
            if let entry, entry.stamp == stamp { return entry.coverage }
            return compute(face)
        }

        func index(_ faces: [FontFace], keepingPaths present: Set<String>, progress: @Sendable (Int, Int) -> Void) {
            loadIfNeeded()
            let stamps = faces.map { FaceCache.stamp(of: $0.path) }
            lock.lock()
            let pending = zip(faces, stamps).compactMap { face, stamp in
                entries[face.id]?.stamp == stamp ? nil : face
            }
            lock.unlock()

            var done = faces.count - pending.count
            progress(done, faces.count)
            let chunkSize = 64
            for start in stride(from: 0, to: pending.count, by: chunkSize) {
                guard !Task.isCancelled else { return }
                let chunk = Array(pending[start..<min(start + chunkSize, pending.count)])
                DispatchQueue.concurrentPerform(iterations: chunk.count) { i in
                    self.compute(chunk[i])
                }
                done += chunk.count
                progress(done, faces.count)
            }
            save(keepingPaths: present)
        }

        @discardableResult
        func compute(_ face: FontFace) -> FaceCoverage {
            let stamp = FaceCache.stamp(of: face.path)
            let font = FontCache.shared.font(face, size: 12)
            let coverage = FaceCoverage(scalars: ScalarRanges(characterSet: CTFontCopyCharacterSet(font)))
            // No stamp means the file is gone, and the font we got was a fallback.
            if let stamp {
                lock.lock()
                entries[face.id] = Entry(stamp: stamp, coverage: coverage)
                dirty = true
                lock.unlock()
            }
            return coverage
        }

        private func loadIfNeeded() {
            loadLock.lock()
            defer { loadLock.unlock() }
            guard !loaded else { return }
            let cache = CoverageCache.load()
            let sameLanguages = cache.languagesVersion == CoverageCache.currentLanguagesVersion
            var restored: [String: Entry] = [:]
            restored.reserveCapacity(cache.faces.count)
            for (id, entry) in cache.faces {
                let scalars = ScalarRanges(data: entry.ranges)
                let coverage = sameLanguages
                    ? FaceCoverage(scalars: scalars, supported: LanguageSet(data: entry.supported), full: LanguageSet(data: entry.full))
                    : FaceCoverage(scalars: scalars)
                restored[id] = Entry(stamp: entry.stamp, coverage: coverage)
            }
            lock.lock()
            entries.merge(restored) { fresh, _ in fresh }
            loaded = true
            if !sameLanguages { dirty = true }
            lock.unlock()
        }

        private func save(keepingPaths present: Set<String>) {
            lock.lock()
            guard dirty else {
                lock.unlock()
                return
            }
            dirty = false
            var cache = CoverageCache()
            for (id, entry) in entries where present.contains(entry.coverage.path(fromFaceID: id)) {
                cache.faces[id] = .init(
                    stamp: entry.stamp, ranges: entry.coverage.scalars.data,
                    supported: entry.coverage.supported.data, full: entry.coverage.full.data
                )
            }
            lock.unlock()
            cache.save()
        }
    }
}

struct TextMatch: Identifiable, Sendable {
    var family: FontFamily
    /// Scalars of the text the family lacks; empty for a complete match.
    var missing: [UInt32]

    var id: String { family.id }
}

struct TextMatches: Sendable {
    var matches: [TextMatch] = []
    var scalarCount = 0
    var unindexed = 0
}

struct LanguageMatches: Sendable {
    var full: [FontFamily] = []
    /// Base support only.
    var base: [FontFamily] = []
    var unindexed = 0
}

// MARK: - Coverage of one face

struct FaceCoverage: Sendable {
    var scalars: ScalarRanges
    /// Languages with base support, as indices into `Languages.all`.
    var supported: LanguageSet
    var full: LanguageSet

    init(scalars: ScalarRanges, supported: LanguageSet, full: LanguageSet) {
        self.scalars = scalars
        self.supported = supported
        self.full = full
    }

    /// Hyperglot's default check: supported when any of the checked orthographies has every base
    /// character and required mark; fully supported when its auxiliary characters are there too.
    init(scalars: ScalarRanges) {
        self.scalars = scalars
        supported = LanguageSet()
        full = LanguageSet()
        for (index, language) in Languages.all.enumerated() {
            var level: LanguageSupport?
            for orthography in language.orthographies where scalars.containsAll(orthography.baseScalars) {
                level = .base
                if scalars.containsAll(orthography.auxiliaryScalars) {
                    level = .full
                    break
                }
            }
            if let level {
                supported.insert(index)
                if level == .full { full.insert(index) }
            }
        }
    }

    func support(for language: Language) -> LanguageSupport? {
        support(for: language.iso)
    }

    func support(for iso: String) -> LanguageSupport? {
        guard let index = Languages.index(of: iso), supported.contains(index) else { return nil }
        return full.contains(index) ? .full : .base
    }

    var supportedLanguages: [Language] { supported.languages }

    fileprivate func path(fromFaceID id: String) -> String {
        id.lastIndex(of: "#").map { String(id[..<$0]) } ?? id
    }
}

/// A set of languages as a bitset over `Languages.all`.
struct LanguageSet: Sendable, Equatable {
    private var words: [UInt64]

    init() {
        words = [UInt64](repeating: 0, count: (Languages.all.count + 63) / 64)
    }

    init(data: Data) {
        words = data.toArray(of: UInt64.self)
    }

    var data: Data { words.asData }
    var count: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }

    func contains(_ index: Int) -> Bool {
        let word = index >> 6
        return word < words.count && words[word] & (1 << UInt64(index & 63)) != 0
    }

    mutating func insert(_ index: Int) {
        let word = index >> 6
        guard word < words.count else { return }
        words[word] |= 1 << UInt64(index & 63)
    }

    var languages: [Language] {
        let all = Languages.all
        return all.indices.filter(contains).map { all[$0] }
    }
}

/// The scalars a face covers, as sorted closed ranges stored flat: lower, upper, lower, upper, …
struct ScalarRanges: Sendable, Equatable {
    private(set) var bounds: [UInt32]

    /// Reads CoreText's bitmap: 8192 bytes for the BMP, then a plane number byte plus 8192 bytes
    /// for every other plane that has members.
    init(characterSet: CFCharacterSet) {
        let data = CFCharacterSetCreateBitmapRepresentation(nil, characterSet) as Data? ?? Data()
        var bounds: [UInt32] = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            var plane: UInt32 = 0
            while offset + 8192 <= buffer.count {
                var start: UInt32?
                for byteIndex in 0..<8192 {
                    let byte = buffer[offset + byteIndex]
                    let base = plane << 16 | UInt32(byteIndex << 3)
                    if byte == 0xFF {
                        if start == nil { start = base }
                    } else if byte == 0 {
                        if let s = start {
                            bounds.append(contentsOf: [s, base - 1])
                            start = nil
                        }
                    } else {
                        for bit in 0..<8 {
                            let value = base + UInt32(bit)
                            if byte & (1 << bit) != 0 {
                                if start == nil { start = value }
                            } else if let s = start {
                                bounds.append(contentsOf: [s, value - 1])
                                start = nil
                            }
                        }
                    }
                }
                if let s = start { bounds.append(contentsOf: [s, plane << 16 | 0xFFFF]) }
                offset += 8192
                if offset < buffer.count {
                    plane = UInt32(buffer[offset])
                    offset += 1
                }
            }
        }
        self.bounds = bounds
    }

    init(data: Data) {
        bounds = data.toArray(of: UInt32.self)
    }

    var data: Data { bounds.asData }

    var count: Int {
        var total = 0
        for i in stride(from: 0, to: bounds.count - 1, by: 2) { total += Int(bounds[i + 1] - bounds[i]) + 1 }
        return total
    }

    func contains(_ scalar: UInt32) -> Bool {
        var low = 0
        var high = bounds.count / 2
        while low < high {
            let mid = (low + high) / 2
            if bounds[mid * 2 + 1] < scalar { low = mid + 1 } else { high = mid }
        }
        return low < bounds.count / 2 && bounds[low * 2] <= scalar
    }

    func containsAll(_ scalars: [UInt32]) -> Bool {
        scalars.allSatisfy(contains)
    }

    func missing(from scalars: [UInt32]) -> [UInt32] {
        scalars.filter { !contains($0) }
    }
}

// MARK: - Cache file

/// Coverage per face id, invalidated per file by modification date and size like `FaceCache`.
struct CoverageCache: Codable {
    struct Entry: Codable {
        var stamp: FaceCache.Stamp
        var ranges: Data
        var supported: Data
        var full: Data
    }

    var version = 1
    /// Language bits are only reused when the bundled data they were computed from is the same.
    var languagesVersion = currentLanguagesVersion
    var faces: [String: Entry] = [:]

    static var currentLanguagesVersion: String { "\(Languages.version ?? "")#\(Languages.all.count)" }

    private static var url: URL { Persistence.cacheDirectory.appendingPathComponent("coverage-v1.plist") }

    static func load() -> CoverageCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? PropertyListDecoder().decode(CoverageCache.self, from: data),
              cache.version == 1 else { return CoverageCache() }
        return cache
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Persistence.cacheDirectory, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(self).write(to: Self.url, options: .atomic)
        } catch {
            NSLog("Point: failed to save coverage cache: \(error)")
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension Array where Element: FixedWidthInteger {
    var asData: Data { withUnsafeBufferPointer { Data(buffer: $0) } }
}

private extension Data {
    func toArray<T: FixedWidthInteger>(of type: T.Type) -> [T] {
        let count = self.count / MemoryLayout<T>.size
        var result = [T](repeating: 0, count: count)
        _ = result.withUnsafeMutableBytes { copyBytes(to: $0, count: count * MemoryLayout<T>.size) }
        return result
    }
}
