import Foundation

public struct SimilarFonts: Sendable {
    private let ids: [String]
    private let positions: [String: Int]
    private let values: [Float]
    private let embeddings: [Float]
    private let classifications: [String?]
    private let sizes: [OpticalSize?]
    private let designs: [String]
    private let scales: [Float]
    private let weights: [Float]
    private let embeddingWeight: Float
    private let otherClassification: Float

    private static let measures = LetterMeasurements.Measure.allCases.count

    public static let weights: [LetterMeasurements.Measure: Float] = [
        .xHeight: 1.5, .ascender: 0.5, .descender: 0.5, .weight: 2.5, .contrast: 2, .stress: 1, .width: 6, .capitalWidth: 3,
        .roundWidth: 3, .spacing: 0.5, .slant: 1.5, .serifLength: 2.5, .serifThickness: 1, .aperture: 1,
        .squareness: 0.75, .doubleStoryA: 1, .doubleStoryG: 0.75, .monospaced: 2,
    ]

    public static let steps: [LetterMeasurements.Measure: Float] = [
        .xHeight: 0.04, .ascender: 0.03, .descender: 0.04, .weight: 0.025, .contrast: 0.1, .stress: 0.15, .width: 0.08,
        .capitalWidth: 0.07, .roundWidth: 0.07, .spacing: 0.05, .slant: 0.07, .serifLength: 0.03, .serifThickness: 0.03,
        .aperture: 0.04, .squareness: 0.02, .doubleStoryA: 0.5, .doubleStoryG: 0.5, .monospaced: 0.5,
    ]

    public static let embeddingWeight: Float = 1.5
    public static let embeddingStep: Float = 0.1

    public static let otherClassification: Float = 1

    public enum OpticalSize: Sendable {
        case text
        case display

        public init?(name: String) {
            let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))
            if !words.isDisjoint(with: ["display", "headline", "poster", "deck", "banner", "titling", "fine"]) {
                self = .display
            } else if !words.isDisjoint(with: ["text", "caption", "micro", "agate"]) {
                self = .text
            } else {
                return nil
            }
        }
    }

    static let copyWords: Set<String> = [
        "trial", "unlicensed", "test", "demo", "beta", "variable", "var", "vf", "pro", "std", "plus", "pron", "stdn",
        "sc", "tc", "hk", "mo",
    ]
    static let weightWords: Set<String> = [
        "hairline", "thin", "extralight", "ultralight", "light", "book", "regular", "medium", "semibold", "demibold", "bold",
        "extrabold", "ultrabold", "heavy", "black", "extrablack",
    ]

    static func design(of name: String) -> String {
        var words = name.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
        if words.count > 1, words[0] == "test" { words.removeFirst() }
        func stripCopies() {
            while words.count > 1, let last = words.last, copyWords.contains(last) || weightWords.contains(last) || isVersion(last) {
                words.removeLast()
                if weightWords.contains(last), words.count > 1, ["semi", "demi", "extra", "ultra"].contains(words.last!) { words.removeLast() }
            }
        }
        stripCopies()
        guard words.count > 1, ["italic", "italics", "oblique"].contains(words.last!) else { return words.joined(separator: " ") }
        let slope = words.removeLast()
        stripCopies()
        return (words + [slope]).joined(separator: " ")
    }

    private static func isVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        guard digits.first?.isWholeNumber == true, digits.allSatisfy({ $0.isWholeNumber || $0 == "." }) else { return false }
        return word.hasPrefix("v") || digits.contains(".") || digits.count >= 4
    }

    public static let longestList = 12

    public init(families: [Family], measurements: (Family) -> LetterMeasurements?, embeddings: ((Family) -> [Float]?)? = nil,
                classification: (Family) -> String?,
                weights: [LetterMeasurements.Measure: Float] = SimilarFonts.weights,
                embeddingWeight: Float = SimilarFonts.embeddingWeight, otherClassification: Float = SimilarFonts.otherClassification) {
        let measuring = weights.values.contains { $0 > 0 }, embedding = embeddings != nil && embeddingWeight > 0
        var ids: [String] = [], values: [Float] = [], vectors: [Float] = [], classifications: [String?] = [], sizes: [OpticalSize?] = []
        var designs: [String] = []
        for family in families {
            let measured = measurements(family), embedded = embedding ? embeddings?(family) : nil
            guard measured != nil || !measuring, embedded != nil || !embedding, measured != nil || embedded != nil else { continue }
            ids.append(family.id)
            values += measured?.values ?? Array(repeating: .nan, count: Self.measures)
            vectors += embedded ?? []
            classifications.append(classification(family))
            sizes.append(OpticalSize(name: family.id))
            designs.append(Self.design(of: family.id))
        }
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        self.values = values
        self.embeddings = vectors
        self.classifications = classifications
        self.sizes = sizes
        self.designs = designs
        scales = LetterMeasurements.Measure.allCases.map { Self.steps[$0] ?? 1 }
        self.weights = LetterMeasurements.Measure.allCases.map { weights[$0] ?? 0 }
        self.embeddingWeight = embedding ? embeddingWeight : 0
        self.otherClassification = otherClassification
    }

    public var count: Int { ids.count }

    public func contains(_ id: String) -> Bool { positions[id] != nil }

    public func nearest(to id: String, limit: Int) -> [String] {
        nearestWithDistances(to: id, limit: limit).map(\.id)
    }

    public func nearestWithDistances(to id: String, limit: Int) -> [(id: String, distance: Float)] {
        guard let reference = positions[id] else { return [] }
        var found: [(index: Int, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices where other != reference {
            found.append((other, distance(reference, other)))
        }
        found.sort { $0.distance < $1.distance }
        var listed: Set = [designs[reference]], nearest: [(index: Int, distance: Float)] = []
        for entry in found where listed.insert(designs[entry.index]).inserted {
            nearest.append(entry)
            if nearest.count == max(limit, Self.longestList) { break }
        }
        if let own = sizes[reference] {
            let slots = nearest.indices.filter { sizes[nearest[$0].index] != nil }
            let named = slots.map { nearest[$0] }
            let ordered = named.filter { sizes[$0.index] == own } + named.filter { sizes[$0.index] != own }
            for (slot, entry) in zip(slots, ordered) { nearest[slot] = entry }
        }
        return nearest.prefix(limit).map { (ids[$0.index], $0.distance) }
    }

    static let oneMissing: Float = 1.5

    private func distance(_ a: Int, _ b: Int) -> Float {
        var sum: Float = 0
        let base = a * Self.measures, other = b * Self.measures
        for measure in 0..<Self.measures where weights[measure] > 0 {
            let x = values[base + measure], y = values[other + measure]
            let steps: Float = switch (x.isNaN, y.isNaN) {
            case (false, false): min(abs(x - y) / scales[measure], 4)
            case (true, true): 0
            default: Self.oneMissing
            }
            sum += weights[measure] * steps * steps
        }
        if embeddingWeight > 0 {
            var squares: Float = 0
            let dimensions = LetterEmbedding.dimensions
            for index in 0..<dimensions {
                let difference = embeddings[a * dimensions + index] - embeddings[b * dimensions + index]
                squares += difference * difference
            }
            sum += embeddingWeight * squares / (Self.embeddingStep * Self.embeddingStep)
        }
        if let first = classifications[a], let second = classifications[b], first != second { return sum.squareRoot() + otherClassification }
        return sum.squareRoot()
    }
}
