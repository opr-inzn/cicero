import Foundation

/// A face's characters grouped for the glyph grid: one section per Unicode block.
public struct GlyphSection: Identifiable, Sendable {
    public let title: String
    public let scalars: [UInt32]
    public var id: String { title }

    public init(title: String, scalars: [UInt32]) {
        self.title = title
        self.scalars = scalars
    }

    /// Characters outside every Unicode block.
    public static let other = "Other"
    /// Keeps the grid usable for fonts with tens of thousands of CJK characters.
    public static let limit = 6000

    /// The face's visible characters by Unicode block, in code point order, then "Other". Limits
    /// very large fonts to a sensible number of characters per section.
    public static func sections(for coverage: ScalarRanges) -> [GlyphSection] {
        let blocks = UnicodeBlock.all
        var buckets: [Int: [UInt32]] = [:]
        var other: [UInt32] = []
        var block = 0
        for range in coverage.ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                switch scalar.properties.generalCategory {
                case .control, .format, .surrogate, .spaceSeparator, .lineSeparator, .paragraphSeparator: continue
                default: break
                }
                // Scalars come in order, so the block only ever moves forward.
                while block < blocks.count && blocks[block].range.upperBound < value { block += 1 }
                if block < blocks.count && blocks[block].range.contains(value) {
                    buckets[block, default: []].append(value)
                } else {
                    other.append(value)
                }
            }
        }
        var sections = buckets.keys.sorted().map { GlyphSection(title: blocks[$0].name, scalars: Array(buckets[$0]!.prefix(limit))) }
        if !other.isEmpty { sections.append(GlyphSection(title: Self.other, scalars: Array(other.prefix(limit)))) }
        return sections
    }

    /// The Unicode name, e.g. "LATIN SMALL LETTER A WITH ACUTE".
    public static func name(of scalar: UInt32) -> String? {
        guard let scalar = Unicode.Scalar(scalar) else { return nil }
        return scalar.properties.name ?? scalar.properties.nameAlias
    }

    /// The Unicode block a scalar is in, e.g. "Latin Extended-A".
    public static func block(of scalar: UInt32) -> String? {
        let blocks = UnicodeBlock.all
        var low = 0
        var high = blocks.count
        while low < high {
            let mid = (low + high) / 2
            if blocks[mid].range.lowerBound <= scalar { low = mid + 1 } else { high = mid }
        }
        guard low > 0, blocks[low - 1].range.contains(scalar) else { return nil }
        return blocks[low - 1].name
    }
}
