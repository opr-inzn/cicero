import Foundation

public struct SimilarFonts: Sendable {
    private let ids: [String]
    private let positions: [String: Int]
    private let values: [Float]
    private let embeddings: [Float]
    private let dimensions: Int
    private let classifications: [String?]
    private let sizes: [OpticalSize?]
    private let designs: [String]
    private let styleDesigns: [String]
    private let styleRows: [[SearchQuery.Style: Int]]
    private let regularKinds: [SearchQuery.Style]
    private let neighborRows: [[Int]]
    private let italicOnly: [Bool]
    private let rounded: [Bool]
    private let plainDesigns: [String]
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
    public static let notRounded: Float = 10
    static let nearerWeightSteps: Float = 2

    static let slanted: Float = 0.1
    static let roundedWords: Set<String> = ["rounded", "round", "rnd"]

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
        "trial", "unlicensed", "test", "demo", "beta", "variable", "var", "vf", "pro", "std", "plus", "pron", "stdn", "ot",
        "sc", "tc", "hk", "mo", "cyr", "cyrillic", "grk", "greek", "ce", "w1g", "c", "arabic", "hebrew", "armenian", "georgian",
        "thai", "devanagari",
        "lf", "tf", "osf", "scosf", "caps", "smallcaps", "expert", "exp", "alt", "alts", "alternate", "alternates", "swash",
        "swashes", "lig", "ligatures", "fractions", "pi", "ornaments", "initials",
    ]
    static let weightWords: Set<String> = [
        "hairline", "thin", "extralight", "ultralight", "light", "book", "regular", "medium", "semibold", "demibold", "bold",
        "extrabold", "ultrabold", "heavy", "black", "extrablack",
    ]

    static func design(of name: String) -> String {
        var words = StyleName.spaced(name).lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
        if words.count > 1, words[0] == "test" { words.removeFirst() }
        func stripCopies() {
            while words.count > 1, let last = words.last, copyWords.contains(last) || weightWords.contains(last) || isVersion(last) {
                words.removeLast()
                if weightWords.contains(last), words.count > 1, ["semi", "demi", "extra", "ultra"].contains(words.last!) { words.removeLast() }
                if last == "caps", words.count > 1, ["small", "petite", "all"].contains(words.last!) { words.removeLast() }
            }
        }
        stripCopies()
        guard words.count > 1, slopeWords.contains(words.last!) else { return words.joined(separator: " ") }
        let slope = words.removeLast()
        stripCopies()
        return (words + [slope]).joined(separator: " ")
    }

    static let slopeWords: Set<String> = ["italic", "italics", "oblique"]

    static func styleDesign(of name: String) -> String {
        var words = design(of: name).split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, slopeWords.contains(last) || StyleName.widths[last] != nil {
            words.removeLast()
            if words.count > 1, ["extra", "ultra", "semi", "x", "xx"].contains(words.last!) { words.removeLast() }
        }
        return words.joined(separator: " ")
    }

    private static func isVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        guard digits.first?.isWholeNumber == true, digits.allSatisfy({ $0.isWholeNumber || $0 == "." }) else { return false }
        return word.hasPrefix("v") || digits.contains(".") || digits.count >= 4
    }

    public static let longestList = 12

    public init(families: [Family], measurements: (Family) -> LetterMeasurements?, embeddings: ((Family) -> [Float]?)? = nil,
                styleMeasurements: ((LibraryFace) -> LetterMeasurements?)? = nil, styleEmbeddings: ((LibraryFace) -> [Float]?)? = nil,
                otherWeights: Bool = false,
                classification: (Family) -> String?,
                weights: [LetterMeasurements.Measure: Float] = SimilarFonts.weights,
                embeddingWeight: Float = SimilarFonts.embeddingWeight, otherClassification: Float = SimilarFonts.otherClassification) {
        let measuring = weights.values.contains { $0 > 0 }, embedding = embeddings != nil && embeddingWeight > 0
        var ids: [String] = [], values: [Float] = [], vectors: [Float] = [], classifications: [String?] = [], sizes: [OpticalSize?] = []
        var designs: [String] = [], styleDesigns: [String] = [], italicOnly: [Bool] = [], rounded: [Bool] = []
        var plainDesigns: [String] = [], regularKinds: [SearchQuery.Style] = [], styleRows: [[SearchQuery.Style: Int]] = []
        var styles: [(family: Int, kind: SearchQuery.Style, values: [Float], embedding: [Float])] = []
        var neighbors: [(family: Int, values: [Float], embedding: [Float])] = []
        func usable(_ measured: LetterMeasurements?, _ embedded: [Float]?) -> Bool {
            (measured != nil || !measuring) && (embedded != nil || !embedding) && (measured != nil || embedded != nil)
        }
        for family in families {
            let measured = measurements(family), embedded = embedding ? embeddings?(family) : nil
            guard usable(measured, embedded) else { continue }
            let regularKind = family.kind(of: family.regular)
            var rows = [regularKind: ids.count]
            for kind in styleMeasurements == nil ? [] : family.kinds where kind != regularKind {
                guard let face = family.representative(of: kind) else { continue }
                if face.id == family.regular.id {
                    rows[kind] = ids.count
                    continue
                }
                let styleMeasured = styleMeasurements?(face), styleEmbedded = embedding ? styleEmbeddings?(face) : nil
                if usable(styleMeasured, styleEmbedded) {
                    styles.append((ids.count, kind, styleMeasured?.values ?? Array(repeating: .nan, count: Self.measures), styleEmbedded ?? []))
                }
            }
            for face in otherWeights ? family.weightNeighbors : [] {
                let styleMeasured = styleMeasurements?(face), styleEmbedded = embedding ? styleEmbeddings?(face) : nil
                if usable(styleMeasured, styleEmbedded) {
                    neighbors.append((ids.count, styleMeasured?.values ?? Array(repeating: .nan, count: Self.measures), styleEmbedded ?? []))
                }
            }
            styleRows.append(rows)
            regularKinds.append(regularKind)
            ids.append(family.id)
            values += measured?.values ?? Array(repeating: .nan, count: Self.measures)
            vectors += embedded ?? []
            classifications.append(classification(family))
            sizes.append(OpticalSize(name: family.id))
            designs.append(Self.design(of: family.id))
            styleDesigns.append(Self.styleDesign(of: family.id))
            italicOnly.append(family.regular.face.isItalic)
            let words = family.id.split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
            let plain = words.filter { !Self.roundedWords.contains($0.lowercased()) }
            rounded.append(measured?[.rounded] == 1 || plain.count < words.count)
            plainDesigns.append(Self.design(of: plain.joined(separator: " ")))
        }
        for (offset, style) in styles.enumerated() {
            styleRows[style.family][style.kind] = ids.count + offset
            values += style.values
            vectors += style.embedding
        }
        var neighborRows = [[Int]](repeating: [], count: ids.count)
        for (offset, neighbor) in neighbors.enumerated() {
            neighborRows[neighbor.family].append(ids.count + styles.count + offset)
            values += neighbor.values
            vectors += neighbor.embedding
        }
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        self.values = values
        self.embeddings = vectors
        dimensions = values.isEmpty || vectors.isEmpty ? LetterEmbedding.dimensions : vectors.count / (values.count / Self.measures)
        self.classifications = classifications
        self.sizes = sizes
        self.designs = designs
        self.styleDesigns = styleDesigns
        self.styleRows = styleRows
        self.regularKinds = regularKinds
        self.neighborRows = neighborRows
        self.italicOnly = italicOnly
        self.rounded = rounded
        self.plainDesigns = plainDesigns
        scales = LetterMeasurements.Measure.allCases.map { Self.steps[$0] ?? 1 }
        self.weights = LetterMeasurements.Measure.allCases.map { weights[$0] ?? 0 }
        self.embeddingWeight = embedding ? embeddingWeight : 0
        self.otherClassification = otherClassification
    }

    public var count: Int { ids.count }

    public func contains(_ id: String, kind: SearchQuery.Style? = nil) -> Bool {
        guard let reference = positions[id] else { return false }
        return kind.map { styleRows[reference][$0] != nil } ?? true
    }

    public func nearest(to id: String, kind: SearchQuery.Style? = nil, limit: Int) -> [String] {
        nearestWithDistances(to: id, kind: kind, limit: limit).map(\.id)
    }

    public func nearestWithDistances(to id: String, kind: SearchQuery.Style? = nil, limit: Int) -> [(id: String, distance: Float)] {
        guard let reference = positions[id] else { return [] }
        let kind = kind ?? (italicOnly[reference] ? regularKinds[reference] : nil)
        guard let start = kind.map({ styleRows[reference][$0] }) ?? reference else { return [] }
        var found: [(index: Int, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices where other != reference {
            guard let row = kind.map({ self.row(of: other, for: $0) }) ?? other else { continue }
            var apart = distance(reference, start, other, row: row)
            if kind == nil {
                for neighbor in nearerWeights(of: other, than: row, to: start) { apart = min(apart, distance(reference, start, other, row: neighbor)) }
            }
            found.append((other, apart))
        }
        found.sort { $0.distance < $1.distance }
        let keys = kind == nil ? designs : styleDesigns
        var listed: Set = [keys[reference]], nearest: [(index: Int, distance: Float)] = []
        for entry in found where listed.insert(keys[entry.index]).inserted {
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

    private func nearerWeights(of family: Int, than row: Int, to start: Int) -> [Int] {
        let weight = LetterMeasurements.Measure.weight.rawValue
        let wanted = values[start * Self.measures + weight], own = values[row * Self.measures + weight]
        guard !wanted.isNaN, !neighborRows[family].isEmpty else { return [] }
        let limit = Self.nearerWeightSteps * (Self.steps[.weight] ?? 1)
        return neighborRows[family].filter { neighbor in
            let other = values[neighbor * Self.measures + weight]
            return !other.isNaN && abs(other - wanted) <= limit && (own.isNaN || abs(other - wanted) < abs(own - wanted))
        }
    }

    private func row(of family: Int, for kind: SearchQuery.Style) -> Int? {
        if let row = styleRows[family][kind] { return row }
        let near = styleRows[family].filter { $0.key.isItalic == kind.isItalic && $0.key.side == kind.side }
            .min { abs(($0.key.width ?? 5) - (kind.width ?? 5)) < abs(($1.key.width ?? 5) - (kind.width ?? 5)) }
        if let near { return near.value }
        let slant = values[family * Self.measures + LetterMeasurements.Measure.slant.rawValue]
        return kind.isItalic && !regularKinds[family].isItalic && regularKinds[family].side == kind.side && abs(slant) > Self.slanted ? family : nil
    }

    static let oneMissing: Float = 1.5

    private func distance(_ a: Int, _ start: Int, _ b: Int, row: Int) -> Float {
        var sum: Float = 0
        let base = start * Self.measures, other = row * Self.measures
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
            for index in 0..<dimensions {
                let difference = embeddings[start * dimensions + index] - embeddings[row * dimensions + index]
                squares += difference * difference
            }
            sum += embeddingWeight * squares / (Self.embeddingStep * Self.embeddingStep)
        }
        var apart = sum.squareRoot()
        if let first = classifications[a], let second = classifications[b], first != second { apart += otherClassification }
        if rounded[a], !rounded[b], designs[b] != plainDesigns[a] { apart += Self.notRounded }
        return apart
    }
}
