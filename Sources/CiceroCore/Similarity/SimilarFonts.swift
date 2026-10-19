import Foundation

/// The families of a library side by side by their letter measurements (see `LetterMeasurements`), to find those
/// that look most like one. Each measure counts in the library's own spread of it, so none counts for more by being
/// a bigger number, and then by how much it shows: weight and serifs more than spacing. Families of different
/// classifications are farther apart. Made once for a library, then asked as often as needed.
public struct SimilarFonts: Sendable {
    private let ids: [String]
    private let positions: [String: Int]
    /// The measurements of the families in `ids`, one after the other.
    private let values: [Float]
    private let classifications: [String?]
    /// How far apart one step of each measure is: about the spread of the middle two thirds of the library.
    private let scales: [Float]
    private let weights: [Float]

    private static let measures = LetterMeasurements.Measure.allCases.count

    /// How much each measure counts.
    public static let weights: [LetterMeasurements.Measure: Float] = [
        .xHeight: 1.5, .ascender: 0.5, .descender: 0.5, .weight: 2.5, .contrast: 2, .stress: 1, .width: 1.5, .capitalWidth: 0.75,
        .roundWidth: 0.75, .spacing: 0.5, .slant: 1.5, .serifLength: 2.5, .serifThickness: 1, .aperture: 1,
        .squareness: 0.75, .doubleStoryA: 1, .doubleStoryG: 0.75, .monospaced: 2,
    ]

    /// Added to the distance between families whose classifications differ, when both have one.
    public static let otherClassification: Float = 4

    /// - Parameters:
    ///   - measurements: a family's regular style's, nil when it couldn't be measured; such families are left out.
    ///   - classification: nil for one without.
    public init(families: [Family], measurements: (Family) -> LetterMeasurements?, classification: (Family) -> String?,
                weights: [LetterMeasurements.Measure: Float] = SimilarFonts.weights) {
        var ids: [String] = [], values: [Float] = [], classifications: [String?] = []
        for family in families {
            guard let measured = measurements(family) else { continue }
            ids.append(family.id)
            values += measured.values
            classifications.append(classification(family))
        }
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        self.values = values
        self.classifications = classifications
        let count = ids.count
        scales = LetterMeasurements.Measure.allCases.map { measure in
            if measure == .doubleStoryA || measure == .doubleStoryG || measure == .monospaced { return 0.5 }
            let column = (0..<count).map { values[$0 * Self.measures + measure.rawValue] }.filter { !$0.isNaN }.sorted()
            guard column.count >= 3 else { return 1 }
            let spread = (column[column.count * 5 / 6] - column[column.count / 6]) / 2
            return spread > 0.0001 ? spread : 1
        }
        self.weights = LetterMeasurements.Measure.allCases.map { weights[$0] ?? 0 }
    }

    /// How many families were measured.
    public var count: Int { ids.count }

    public func contains(_ id: String) -> Bool { positions[id] != nil }

    /// The families that look most like this one, the nearest first, without it; empty when it wasn't measured.
    public func nearest(to id: String, limit: Int) -> [String] {
        nearestWithDistances(to: id, limit: limit).map(\.id)
    }

    public func nearestWithDistances(to id: String, limit: Int) -> [(id: String, distance: Float)] {
        guard let reference = positions[id] else { return [] }
        var found: [(id: String, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices where other != reference {
            found.append((ids[other], distance(reference, other)))
        }
        found.sort { $0.distance < $1.distance }
        return Array(found.prefix(limit))
    }

    /// How many steps apart a measure one family has and the other hasn't counts as.
    static let oneMissing: Float = 1.5

    /// The weighted distance between two families' measurements, plus `otherClassification` when they're classified
    /// differently. A measure neither has (two scripts without a straight stem, say) is as alike as can be.
    private func distance(_ a: Int, _ b: Int) -> Float {
        var sum: Float = 0
        let base = a * Self.measures, other = b * Self.measures
        for measure in 0..<Self.measures {
            let x = values[base + measure], y = values[other + measure]
            let steps: Float = switch (x.isNaN, y.isNaN) {
            case (false, false): min(abs(x - y) / scales[measure], 4)
            case (true, true): 0
            default: Self.oneMissing
            }
            sum += weights[measure] * steps * steps
        }
        if let first = classifications[a], let second = classifications[b], first != second { sum += Self.otherClassification }
        return sum.squareRoot()
    }
}
