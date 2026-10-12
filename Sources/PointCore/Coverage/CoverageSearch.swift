import Foundation

/// Families whose regular face has every character of some text, or misses at most a few.
public struct TextMatch: Identifiable, Sendable {
    public let family: Family
    /// In the order the text uses them.
    public let missing: [UInt32]
    public var id: String { family.id }

    public init(family: Family, missing: [UInt32]) {
        self.family = family
        self.missing = missing
    }
}

public enum CoverageSearch {
    /// Unique scalars worth checking in some text (no whitespace or invisible characters), in order of appearance.
    public static func scalars(in text: String) -> [UInt32] {
        var seen: Set<UInt32> = []
        var scalars: [UInt32] = []
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.isCheckable && seen.insert(scalar.value).inserted {
            scalars.append(scalar.value)
        }
        return scalars
    }

    /// Sorted by fewest missing, then the families' order. Families not yet indexed are skipped and counted.
    public static func families(having text: String, in families: [Family], maxMissing: Int, index: CoverageIndex) -> (matches: [TextMatch], unindexed: Int) {
        let ordered = scalars(in: text)
        let sorted = ordered.sorted()
        var matches: [(position: Int, match: TextMatch)] = []
        var unindexed = 0
        for (position, family) in families.enumerated() {
            guard let coverage = index.coverage(of: family.regular.id) else {
                unindexed += 1
                continue
            }
            let missingCount = coverage.scalars.missingCount(sorted: sorted)
            guard missingCount <= maxMissing else { continue }
            var missing: [UInt32] = []
            if missingCount > 0 {
                let set = Set(coverage.scalars.missing(sorted: sorted))
                missing = ordered.filter(set.contains)
            }
            matches.append((position, TextMatch(family: family, missing: missing)))
        }
        matches.sort { ($0.match.missing.count, $0.position) < ($1.match.missing.count, $1.position) }
        return (matches.map(\.match), unindexed)
    }

    public static func families(supporting languageID: String, in families: [Family], index: CoverageIndex) -> (full: [Family], base: [Family], unindexed: Int) {
        var full: [Family] = []
        var base: [Family] = []
        var unindexed = 0
        for family in families {
            guard let coverage = index.coverage(of: family.regular.id) else {
                unindexed += 1
                continue
            }
            switch coverage.support(for: languageID) {
            case .full: full.append(family)
            case .base: base.append(family)
            case nil: break
            }
        }
        return (full, base, unindexed)
    }
}

extension Unicode.Scalar {
    /// Worth checking a font for: not whitespace, a control or format character, a surrogate or unassigned.
    var isCheckable: Bool {
        switch properties.generalCategory {
        case .control, .format, .surrogate, .unassigned, .spaceSeparator, .lineSeparator, .paragraphSeparator: false
        default: !properties.isWhitespace
        }
    }
}
