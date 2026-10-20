import Foundation

/// The families of a library side by side by their letter measurements (see `LetterMeasurements`) and their
/// letters' embedding (see `LetterEmbedding`), to find those that look most like one. Each measure counts in steps
/// of about as much as it takes to see a difference, so none counts for more by being a bigger number, and then by
/// how much it shows: weight and serifs more than spacing, and the widths more still, as the embedding hardly tells
/// them. The embedding counts like one more measure, in steps of `embeddingStep`. Families of different
/// classifications are farther apart. Of families whose names say what size they're for, a text cut's text cuts come
/// before display ones, its own display sibling among them, and the other way round. Copies of one design, as their
/// names say (a trial, a variable font, a family for each weight), are listed once. Families the user said don't look
/// alike are left out of each other's lists. Made once for a library, then asked as often as needed.
public struct SimilarFonts: Sendable {
    private let ids: [String]
    private let positions: [String: Int]
    /// The measurements of the families in `ids`, one after the other.
    private let values: [Float]
    /// Their embeddings, one after the other; empty when they don't count.
    private let embeddings: [Float]
    private let classifications: [String?]
    private let sizes: [OpticalSize?]
    /// `design(of:)` each family's name.
    private let designs: [String]
    /// A design → the designs the user said don't look like it, either way round.
    private let unlike: [String: Set<String>]
    /// `steps`, in the order of the measures.
    private let scales: [Float]
    private let weights: [Float]
    private let embeddingWeight: Float
    private let otherClassification: Float

    private static let measures = LetterMeasurements.Measure.allCases.count

    /// How much each measure counts.
    public static let weights: [LetterMeasurements.Measure: Float] = [
        .xHeight: 1.5, .ascender: 0.5, .descender: 0.5, .weight: 2.5, .contrast: 2, .stress: 1, .width: 6, .capitalWidth: 3,
        .roundWidth: 3, .spacing: 0.5, .slant: 1.5, .serifLength: 2.5, .serifThickness: 1, .aperture: 1,
        .squareness: 0.75, .doubleStoryA: 1, .doubleStoryG: 0.75, .monospaced: 2,
    ]

    /// One step of each measure: about as much as it takes to see a difference. Not the library's spread of it,
    /// which for contrast is mostly the gap between sans serif and serif faces, and for slant next to nothing, as
    /// most faces don't lean.
    public static let steps: [LetterMeasurements.Measure: Float] = [
        .xHeight: 0.04, .ascender: 0.03, .descender: 0.04, .weight: 0.025, .contrast: 0.1, .stress: 0.15, .width: 0.08,
        .capitalWidth: 0.07, .roundWidth: 0.07, .spacing: 0.05, .slant: 0.07, .serifLength: 0.03, .serifThickness: 0.03,
        .aperture: 0.04, .squareness: 0.02, .doubleStoryA: 0.5, .doubleStoryG: 0.5, .monospaced: 0.5,
    ]

    /// How much the embedding counts, and one step of it: the distance between two embeddings, 0 to 2, it takes to
    /// see a difference.
    public static let embeddingWeight: Float = 1.5
    public static let embeddingStep: Float = 0.1

    /// Added to the distance between families whose classifications differ, when both have one: enough to take such a
    /// family a few places down a list, where the sixth nearest and the twelfth are often less than one apart, but not
    /// out of it.
    public static let otherClassification: Float = 1

    /// The sizes a family's name says it's drawn for, as its siblings' names differ: a family's Text and Display.
    public enum OpticalSize: Sendable {
        /// Text, Caption, Micro, Agate.
        case text
        /// Display, Headline, Poster, Deck, Banner, Titling, and Fine.
        case display

        /// nil for a name that doesn't say, as most don't.
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

    /// The words at the end of a name that make another copy of a design rather than another design: a trial's, a
    /// variable font's, an OpenType one's or one for another region's characters (PingFang SC and HK, Hiragino's ProN).
    static let copyWords: Set<String> = [
        "trial", "unlicensed", "test", "demo", "beta", "variable", "var", "vf", "pro", "std", "plus", "pron", "stdn",
        "sc", "tc", "hk", "mo",
    ]
    /// The weights at the end of a name, for a family cut into one for each weight.
    static let weightWords: Set<String> = [
        "hairline", "thin", "extralight", "ultralight", "light", "book", "regular", "medium", "semibold", "demibold", "bold",
        "extrabold", "ultrabold", "heavy", "black", "extrablack",
    ]

    /// The design a family's name says: the name without the words at its end that make another copy of it
    /// (`copyWords`, `weightWords` with the Semi of a Semi Bold, also before an Italic), a version or a date (v0.2,
    /// 2.001, 260417), and without the Test some foundries start a trial's name with, so that Inter Variable, Inter Light
    /// and Test Inter are Inter's, and Inter Bold Italic Inter Italic's, while Roboto Mono and DM Serif Display are
    /// designs of their own.
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

    /// v0.2, v12, 2.001 or 260417, not a number a name has, like Bodoni 72's.
    private static func isVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        guard digits.first?.isWholeNumber == true, digits.allSatisfy({ $0.isWholeNumber || $0 == "." }) else { return false }
        return word.hasPrefix("v") || digits.contains(".") || digits.count >= 4
    }

    /// The longest list asked for, Show Similar Fonts'. Families are put in order of size (see `nearestWithDistances`)
    /// over at least as many, whatever the limit, so that a shorter list, as a font page's, is the start of it.
    public static let longestList = 12

    /// - Parameters:
    ///   - measurements: a family's regular style's, nil when it couldn't be measured; such families are left out,
    ///     unless no measure counts.
    ///   - embeddings: a family's regular style's (see `LetterEmbedding`); when given and weighted, families without
    ///     one are left out.
    ///   - classification: nil for one without.
    ///   - notSimilar: family name → the families the user said don't look like it (`UserData.notSimilar`): left out of
    ///     its list, it out of theirs, and every copy of either (`design(of:)`) too, so that another doesn't take one's place.
    public init(families: [Family], measurements: (Family) -> LetterMeasurements?, embeddings: ((Family) -> [Float]?)? = nil,
                classification: (Family) -> String?, notSimilar: [String: [String]] = [:],
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
        var unlike: [String: Set<String>] = [:]
        for (family, others) in notSimilar {
            let design = Self.design(of: family)
            for other in others.map(Self.design(of:)) where other != design {
                unlike[design, default: []].insert(other)
                unlike[other, default: []].insert(design)
            }
        }
        self.unlike = unlike
        scales = LetterMeasurements.Measure.allCases.map { Self.steps[$0] ?? 1 }
        self.weights = LetterMeasurements.Measure.allCases.map { weights[$0] ?? 0 }
        self.embeddingWeight = embedding ? embeddingWeight : 0
        self.otherClassification = otherClassification
    }

    /// How many families were measured.
    public var count: Int { ids.count }

    public func contains(_ id: String) -> Bool { positions[id] != nil }

    /// The families that look most like this one, the nearest first, without it and its copies, and each design once,
    /// but none the user said doesn't look like it; empty when it wasn't measured.
    public func nearest(to id: String, limit: Int) -> [String] {
        nearestWithDistances(to: id, limit: limit).map(\.id)
    }

    /// The nearest first, but for families whose names say what size they're for (see `OpticalSize`): when the
    /// family's does too, those of its size come first among them, in their order, then the others, its sibling for
    /// another size among them, so a family's Text lists other Text faces, like STIX Two Text, before its own
    /// Display. Families whose names don't say keep their places.
    public func nearestWithDistances(to id: String, limit: Int) -> [(id: String, distance: Float)] {
        guard let reference = positions[id] else { return [] }
        var found: [(index: Int, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices where other != reference {
            found.append((other, distance(reference, other)))
        }
        found.sort { $0.distance < $1.distance }
        // The nearest copy of each design, none of the family's own, and none the user said doesn't look like it.
        var listed = unlike[designs[reference], default: []].union([designs[reference]]), nearest: [(index: Int, distance: Float)] = []
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

    /// How many steps apart a measure one family has and the other hasn't counts as.
    static let oneMissing: Float = 1.5

    /// The weighted distance between two families' measurements and their embeddings, plus `otherClassification`
    /// when they're classified differently. A measure neither has (two scripts without a straight stem, say) is as
    /// alike as can be.
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
