import Accelerate
import Foundation

public enum ClassificationGuesses {
    public static let guessingKey = "classification.guessesFromNames"
    public static let askingKey = "classification.asksAboutGuessing"
    public static let letterLikelihood: Float = 0.7
    public static let namesVersion = 1

    private static let neighborCount = 7
    private static let minimumNeighbors = 3
    private static let minimumSimilarity: Float = 0.7
    private static let neighborAgreement: Float = 0.8
    private static let neighborModelFloor: Float = 0.5
    private static let minimumSerifLength: Float = 0.02
    private static let minimumFlareThickness: Float = 0.08

    public static func namesFile(caches: URL) -> URL {
        caches.appendingPathComponent("classification-guesses.json", isDirectory: false)
    }

    public struct SavedNames: Codable, Sendable {
        public var version: Int
        public var guesses: [String: Classification]

        public init(version: Int = ClassificationGuesses.namesVersion, guesses: [String: Classification]) {
            self.version = version
            self.guesses = guesses
        }
    }

    public static func savedNames(caches: URL) -> [String: Classification] {
        let saved = (try? Data(contentsOf: namesFile(caches: caches))).flatMap { try? JSONDecoder().decode(SavedNames.self, from: $0) }
        return saved.flatMap { $0.version == namesVersion ? $0.guesses : nil } ?? [:]
    }

    public static func isGuessing(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: askingKey) && defaults.object(forKey: guessingKey) as? Bool ?? true
    }

    public static func letters(of families: [Family], measurements: MeasurementIndex) -> [String: Classification] {
        let snapshot = measurements.snapshot()
        var found: [String: Classification] = [:]
        var unsure: [(id: String, design: String, candidate: Classification, embedding: [Float])] = []
        for family in families where family.classification == .unclassified && !family.mixesSerifAndSans {
            guard let seen = averagedClassification(of: family, measurements: snapshot) else { continue }
            let resolved = flaredSerif(of: family, guessed: seen.classification, measurements: snapshot)
            if seen.likelihood >= letterLikelihood {
                if let resolved { found[family.id] = resolved }
            } else if let resolved, seen.likelihood >= neighborModelFloor,
                      let embedding = snapshot.embedding(of: family.regular.face.id),
                      embedding.count == LetterEmbedding.dimensions {
                unsure.append((family.id, SimilarFonts.design(of: family.id), resolved, embedding))
            }
        }
        guard !unsure.isEmpty else { return found }
        var gallery: [(design: String, classification: Classification, embedding: [Float])] = []
        for family in families where family.classification != .unclassified {
            guard let embedding = snapshot.embedding(of: family.regular.face.id),
                  embedding.count == LetterEmbedding.dimensions else { continue }
            gallery.append((SimilarFonts.design(of: family.id), family.classification, embedding))
        }
        guard gallery.count >= minimumNeighbors else { return found }
        let dimensions = LetterEmbedding.dimensions
        let galleryCount = gallery.count
        var transposed = [Float](repeating: 0, count: dimensions * galleryCount)
        for (column, entry) in gallery.enumerated() {
            for row in 0..<dimensions {
                transposed[row * galleryCount + column] = entry.embedding[row]
            }
        }
        let chunk = 64
        for start in stride(from: 0, to: unsure.count, by: chunk) {
            let end = min(start + chunk, unsure.count)
            let count = end - start
            var queries = [Float]()
            queries.reserveCapacity(count * dimensions)
            for index in start..<end { queries.append(contentsOf: unsure[index].embedding) }
            var similarities = [Float](repeating: 0, count: count * galleryCount)
            vDSP_mmul(queries, 1, transposed, 1, &similarities, 1,
                      vDSP_Length(count), vDSP_Length(galleryCount), vDSP_Length(dimensions))
            for offset in 0..<count {
                let query = unsure[start + offset]
                let row = offset * galleryCount
                var close: [(index: Int, similarity: Float)] = []
                for column in 0..<galleryCount {
                    let similarity = similarities[row + column]
                    if similarity >= minimumSimilarity, gallery[column].design != query.design {
                        close.append((column, similarity))
                    }
                }
                guard close.count >= minimumNeighbors else { continue }
                close.sort { $0.similarity != $1.similarity ? $0.similarity > $1.similarity : $0.index < $1.index }
                var seenDesigns = Set<String>()
                var votes: [Classification: Float] = [:]
                var total: Float = 0
                var taken = 0
                for neighbor in close {
                    let entry = gallery[neighbor.index]
                    guard seenDesigns.insert(entry.design).inserted else { continue }
                    let distance = max(sqrt(max(2 - 2 * neighbor.similarity, 0)), 0.05)
                    let weight = 1 / distance
                    votes[entry.classification, default: 0] += weight
                    total += weight
                    taken += 1
                    if taken == neighborCount { break }
                }
                guard taken >= minimumNeighbors, total > 0,
                      let best = votes.max(by: { $0.value < $1.value }),
                      best.key == query.candidate,
                      best.value / total >= neighborAgreement
                else { continue }
                found[query.id] = best.key
            }
        }
        return found
    }

    private static func averagedClassification(of family: Family, measurements: MeasurementIndex.Snapshot)
        -> (classification: Classification, likelihood: Float)? {
        func average(_ faces: [FaceID]) -> (classification: Classification, likelihood: Float)? {
            let count = LetterEmbedding.classifications.count
            var sums = [Float](repeating: 0, count: count)
            var measured = 0
            for id in faces {
                guard let chances = measurements.classifications(of: id), chances.count == count else { continue }
                for index in 0..<count { sums[index] += chances[index] }
                measured += 1
            }
            guard measured > 0, let best = sums.indices.max(by: { sums[$0] < sums[$1] }) else { return nil }
            return (LetterEmbedding.classifications[best], sums[best] / Float(measured))
        }
        let primary = [family.regular.id] + family.weightNeighbors.map(\.id)
        if let result = average(primary) { return result }
        let uprightOnly = !family.regular.face.isItalic
        let fallback = family.kinds.filter { !uprightOnly || !$0.isItalic }.compactMap { family.representative(of: $0)?.id }
        return average(fallback)
    }

    // Google Fonts labels flared serifs as sans serif, so the letter model does too even when H and n have flaring feet.
    private static func flaredSerif(of family: Family, guessed: Classification, measurements: MeasurementIndex.Snapshot) -> Classification? {
        guard guessed == .sansSerif,
              !family.regular.face.isItalic,
              let measured = measurements.measurements(of: family.regular.face.id)
        else { return guessed }
        let length = measured[.serifLength], thickness = measured[.serifThickness], slant = measured[.slant]
        guard !length.isNaN, length >= minimumSerifLength, slant.isNaN || abs(slant) <= SimilarFonts.slanted else { return guessed }
        if !thickness.isNaN, thickness >= minimumFlareThickness, thickness >= length * 2 { return .serif }
        return nil
    }

    public enum Source: Sendable {
        case name
        case letters
    }

    public static func rule(names: [String: Classification], letters: [String: Classification], guessing: Bool)
        -> (Family) -> (classification: Classification, source: Source)? {
        { family in
            guard guessing, family.classification == .unclassified, !family.mixesSerifAndSans else { return nil }
            let name = names[family.id].flatMap { $0 == .unclassified ? nil : $0 }
            if name == .monospaced || name == .symbol, let name { return (name, .name) }
            if let letters = letters[family.id] { return (letters, .letters) }
            return name.map { ($0, .name) }
        }
    }
}
