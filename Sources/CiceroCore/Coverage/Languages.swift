import Foundation
import Synchronization

public enum LanguageSupport: Int, Comparable, Sendable {
    case base
    case full

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct Language: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let autonym: String?
    public let scripts: [String]
    public let speakers: Int
    public let isCurrent: Bool
    public let sampleCharacters: String

    public init(id: String, name: String, autonym: String?, scripts: [String], speakers: Int, isCurrent: Bool, sampleCharacters: String) {
        self.id = id
        self.name = name
        self.autonym = autonym
        self.scripts = scripts
        self.speakers = speakers
        self.isCurrent = isCurrent
        self.sampleCharacters = sampleCharacters
    }
}

public final class LanguageCatalog: Sendable {
    private let loaded = DispatchGroup()
    private let storage = Mutex<Storage?>(nil)

    public init(contentsOf url: URL?) {
        loaded.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let storage = Storage(contentsOf: url)
            self.storage.withLock { $0 = storage }
            loaded.leave()
        }
    }

    public var languages: [Language] { store.languages }
    public var version: String? { store.version }

    public func language(_ id: String) -> Language? {
        let store = store
        return store.order.positions[id].map { store.languages[$0] }
    }

    var order: LanguageOrder { store.order }

    var dataVersion: String { "\(store.version ?? "")#\(store.languages.count)" }

    func support(in scalars: ScalarRanges) -> LanguageBits {
        store.requirements.support(in: scalars)
    }

    private var store: Storage {
        loaded.wait()
        return storage.withLock { $0! }
    }

    private struct Storage: Sendable {
        let languages: [Language]
        let version: String?
        let order: LanguageOrder
        let requirements: LanguageRequirements

        init(contentsOf url: URL?) {
            var file: LanguageFile?
            if let url, let data = try? Data(contentsOf: url) {
                file = try? JSONDecoder().decode(LanguageFile.self, from: data)
            }
            let rows = (file?.languages ?? []).sorted { $0.iso < $1.iso }
            languages = rows.map { row in
                var scripts: [String] = []
                for orthography in row.orthographies where !scripts.contains(orthography.script) {
                    scripts.append(orthography.script)
                }
                return Language(
                    id: row.iso, name: row.name, autonym: row.autonym, scripts: scripts, speakers: row.speakers,
                    isCurrent: row.status != "historical",
                    sampleCharacters: (row.orthographies.first?.base ?? "").map(String.init).joined(separator: " ")
                )
            }
            version = file?.version
            order = LanguageOrder(ids: languages.map(\.id))
            requirements = LanguageRequirements(rows: rows)
        }
    }
}

// MARK: - Data

private struct LanguageFile: Decodable {
    struct Row: Decodable {
        var iso: String
        var name: String
        var speakers: Int
        var status: String
        var autonym: String?
        var orthographies: [Orthography]
    }

    struct Orthography: Decodable {
        var script: String
        var base: String
        var marks: String?
        var auxiliary: String?
        var auxiliaryMarks: String?
    }

    var version: String?
    var languages: [Row]
}

final class LanguageOrder: Sendable {
    let ids: [String]
    let positions: [String: Int]

    init(ids: [String]) {
        self.ids = ids
        var positions: [String: Int] = [:]
        for (position, id) in ids.enumerated() { positions[id] = position }
        self.positions = positions
    }
}

struct LanguageBits: Sendable, Equatable {
    var base: [UInt64]
    var full: [UInt64]

    init(count: Int) {
        base = Array(repeating: 0, count: (count + 63) / 64)
        full = base
    }

    init(base: [UInt64], full: [UInt64]) {
        self.base = base
        self.full = full
    }

    static func isSet(_ words: [UInt64], _ position: Int) -> Bool {
        let word = position >> 6
        return word < words.count && words[word] & (1 << UInt64(position & 63)) != 0
    }

    static func set(_ words: inout [UInt64], _ position: Int) {
        words[position >> 6] |= 1 << UInt64(position & 63)
    }
}

struct LanguageRequirements: Sendable {
    struct Orthography: Sendable {
        var base: [Int32]
        var auxiliary: [Int32]
    }

    let universe: [UInt32]
    let orthographies: [[Orthography]]

    fileprivate init(rows: [LanguageFile.Row]) {
        func scalars(_ strings: String?...) -> Set<UInt32> {
            var set: Set<UInt32> = []
            for string in strings {
                for scalar in (string ?? "").unicodeScalars where !scalar.properties.isWhitespace {
                    set.insert(scalar.value)
                }
            }
            return set
        }
        var all: Set<UInt32> = []
        let sets: [[(base: Set<UInt32>, auxiliary: Set<UInt32>)]] = rows.map { row in
            row.orthographies.map { orthography in
                let base = scalars(orthography.base, orthography.marks)
                let auxiliary = scalars(orthography.auxiliary, orthography.auxiliaryMarks).subtracting(base)
                all.formUnion(base)
                all.formUnion(auxiliary)
                return (base, auxiliary)
            }
        }
        let universe = all.sorted()
        var positions: [UInt32: Int32] = [:]
        for (position, scalar) in universe.enumerated() { positions[scalar] = Int32(position) }
        self.universe = universe
        orthographies = sets.map { language in
            language.map { Orthography(base: $0.base.map { positions[$0]! }.sorted(), auxiliary: $0.auxiliary.map { positions[$0]! }.sorted()) }
        }
    }

    func support(in scalars: ScalarRanges) -> LanguageBits {
        let present = scalars.presence(sorted: universe)
        var bits = LanguageBits(count: orthographies.count)
        for (position, language) in orthographies.enumerated() {
            var support: LanguageSupport?
            for orthography in language where orthography.base.allSatisfy({ present[Int($0)] }) {
                if orthography.auxiliary.allSatisfy({ present[Int($0)] }) {
                    support = .full
                    break
                }
                support = .base
            }
            guard let support else { continue }
            LanguageBits.set(&bits.base, position)
            if support == .full { LanguageBits.set(&bits.full, position) }
        }
        return bits
    }
}
