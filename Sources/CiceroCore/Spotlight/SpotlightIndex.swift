import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// One item as Spotlight gets it.
public struct SpotlightItem: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var description: String
    public var keywords: [String]
    /// A PNG; nil for none, when Spotlight shows Cicero's icon.
    public var thumbnail: Data?
}

/// Where Spotlight items go: Core Spotlight's index for Cicero, or one in memory for tests.
public protocol SearchableIndex: Sendable {
    /// What the last `index` call left as its client state; empty for an index that has none, as when it's new or
    /// macOS rebuilt it.
    func clientState() async throws -> Data
    /// Adds or replaces these items and deletes those, as one batch that leaves `clientState` behind.
    func index(_ items: [SpotlightItem], deleting identifiers: [String], clientState: Data) async throws
    func deleteAll() async throws
}

/// Cicero's own index in Core Spotlight. Items never expire: by default they would a month after they're indexed.
public final class CoreSpotlightIndex: SearchableIndex, @unchecked Sendable {
    // Used by one `SpotlightIndexer` at a time, which keeps batches from overlapping, as Core Spotlight asks.
    private let index = CSSearchableIndex(name: "Cicero")

    public init() {}

    public static var isAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }

    public func clientState() async throws -> Data {
        try await index.fetchLastClientState()
    }

    public func index(_ items: [SpotlightItem], deleting identifiers: [String], clientState: Data) async throws {
        begin(items, deleting: identifiers)
        try await index.endBatch(withClientState: clientState)
    }

    /// In a batch, calls only queue their changes, which `endBatch` hands over and waits for.
    private func begin(_ items: [SpotlightItem], deleting identifiers: [String]) {
        index.beginBatch()
        if !items.isEmpty { index.indexSearchableItems(items.map(Self.searchable), completionHandler: nil) }
        if !identifiers.isEmpty { index.deleteSearchableItems(withIdentifiers: identifiers, completionHandler: nil) }
    }

    public func deleteAll() async throws {
        try await index.deleteAllSearchableItems()
    }

    private static func searchable(_ item: SpotlightItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = item.title
        attributes.displayName = item.title
        attributes.contentDescription = item.description
        attributes.keywords = item.keywords
        attributes.thumbnailData = item.thumbnail
        let searchable = CSSearchableItem(uniqueIdentifier: item.identifier, domainIdentifier: "families", attributeSet: attributes)
        searchable.expirationDate = .distantFuture
        return searchable
    }
}

/// Keeps Spotlight's items in line with the library: indexes the families whose items changed, a hundred at a time,
/// and deletes those that went, remembering in the caches what each item was made from (`SpotlightEntry.digest`), so
/// a launch with nothing changed indexes nothing.
///
/// Every batch leaves a number in the index (its client state) that the caches remember too. When they differ, as when
/// macOS rebuilt its index or the caches were cleared, the index is emptied and filled again.
public actor SpotlightIndexer {
    private let index: any SearchableIndex
    private let file: URL
    private let thumbnail: @Sendable (FontFace) -> Data?
    private var saved: Saved?

    private struct Saved: Codable {
        var generation: UUID
        /// Item identifier → the digest of what it was made from.
        var digests: [String: String] = [:]

        var clientState: Data { withUnsafeBytes(of: generation.uuid) { Data($0) } }
    }

    static let batchSize = 100

    /// `thumbnail` draws a family's sample; by default `SpotlightThumbnail`.
    public init(index: any SearchableIndex = CoreSpotlightIndex(), caches: URL, thumbnail: (@Sendable (FontFace) -> Data?)? = nil) {
        self.index = index
        file = caches.appendingPathComponent("spotlight.json", isDirectory: false)
        self.thumbnail = thumbnail ?? { SpotlightThumbnail.png(for: $0) }
    }

    /// Indexes the entries whose items changed and deletes the items of families not among them. Cancelling stops it
    /// between batches; what it indexed so far is remembered.
    public func update(_ entries: [SpotlightEntry]) async throws {
        let signpost = Signposts.library.beginInterval("Spotlight")
        defer { Signposts.library.endInterval("Spotlight", signpost) }
        var saved = try await current()
        // Stamped off the caller's thread: a file exported again under the same names needs a new thumbnail.
        let digests = entries.map { entry in
            let stamp = CoverageStamp.of(path: entry.sample.path)
            return (entry, entry.digest(sampleStamp: "\(stamp.modified)|\(stamp.size)"))
        }
        let wanted = Set(entries.map(\.identifier))
        var gone = saved.digests.keys.filter { !wanted.contains($0) }.sorted()
        let changed = digests.filter { saved.digests[$0.0.identifier] != $0.1 }
        var start = 0
        while start < changed.count || !gone.isEmpty {
            try Task.checkCancellation()
            let batch = changed[start..<min(start + Self.batchSize, changed.count)]
            let items = batch.map { entry, _ in
                SpotlightItem(
                    identifier: entry.identifier, title: entry.family, description: entry.description,
                    keywords: entry.keywords, thumbnail: thumbnail(entry.sample)
                )
            }
            try await index.index(items, deleting: gone, clientState: saved.clientState)
            for (entry, digest) in batch { saved.digests[entry.identifier] = digest }
            for identifier in gone { saved.digests[identifier] = nil }
            gone = []
            start += Self.batchSize
            save(saved)
        }
    }

    /// Deletes every item, as when the setting is turned off.
    public func removeAll() async throws {
        saved = nil
        try? FileManager.default.removeItem(at: file)
        try await index.deleteAll()
    }

    /// What the index has, as the caches remember it; when the index doesn't agree, an empty one.
    private func current() async throws -> Saved {
        if saved == nil, let data = try? Data(contentsOf: file) { saved = try? JSONDecoder().decode(Saved.self, from: data) }
        if let saved, try await index.clientState() == saved.clientState { return saved }
        try await index.deleteAll()
        let fresh = Saved(generation: UUID())
        try await index.index([], deleting: [], clientState: fresh.clientState)
        save(fresh)
        return fresh
    }

    private func save(_ state: Saved) {
        saved = state
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
