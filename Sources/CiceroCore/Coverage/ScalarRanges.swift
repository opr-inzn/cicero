import CoreFoundation
import Foundation

/// Unicode scalars a face covers, as sorted closed ranges.
public struct ScalarRanges: Sendable, Equatable {
    /// Lower and upper bounds, alternating: sorted, non-overlapping and never adjacent, so every
    /// lookup is a binary search over half the array.
    let bounds: [UInt32]

    public init(_ ranges: [ClosedRange<UInt32>]) {
        var bounds: [UInt32] = []
        bounds.reserveCapacity(ranges.count * 2)
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = bounds.last, last == .max || range.lowerBound <= last + 1 {
                bounds[bounds.count - 1] = max(last, range.upperBound)
            } else {
                bounds.append(range.lowerBound)
                bounds.append(range.upperBound)
            }
        }
        self.bounds = bounds
    }

    /// Bounds already in canonical form (from the cache or the bitmap reader).
    init(bounds: [UInt32]) {
        self.bounds = bounds
    }

    /// Reads a CoreText character set from its bitmap: 8192 bytes for the BMP, then a plane number
    /// and 8192 bytes for every other plane with members. Bit n of byte b is scalar b * 8 + n.
    public init(characterSet: CFCharacterSet) {
        guard let data = CFCharacterSetCreateBitmapRepresentation(nil, characterSet) else {
            self.init(bounds: [])
            return
        }
        let bytes = CFDataGetBytePtr(data)!
        let length = CFDataGetLength(data)
        let planeSize = 8192
        var bounds: [UInt32] = []

        func add(_ plane: UInt32, from offset: Int) {
            var byte = 0
            while byte < planeSize {
                let value = bytes[offset + byte]
                if value != 0 {
                    let first = plane << 16 | UInt32(byte << 3)
                    if value == 0xFF {
                        append(first, first + 7)
                    } else {
                        for bit in 0..<8 where value & (1 << bit) != 0 {
                            append(first + UInt32(bit), first + UInt32(bit))
                        }
                    }
                }
                byte += 1
            }
        }

        func append(_ low: UInt32, _ high: UInt32) {
            if let last = bounds.last, last + 1 == low {
                bounds[bounds.count - 1] = high
            } else {
                bounds.append(low)
                bounds.append(high)
            }
        }

        if length >= planeSize {
            add(0, from: 0)
        }
        var offset = planeSize
        while offset + 1 + planeSize <= length {
            add(UInt32(bytes[offset]), from: offset + 1)
            offset += 1 + planeSize
        }
        self.init(bounds: bounds)
    }

    public static let empty = ScalarRanges(bounds: [])

    public var isEmpty: Bool { bounds.isEmpty }

    public var ranges: [ClosedRange<UInt32>] {
        stride(from: 0, to: bounds.count, by: 2).map { bounds[$0]...bounds[$0 + 1] }
    }

    public var count: Int {
        var total = 0
        for i in stride(from: 0, to: bounds.count, by: 2) {
            total += Int(bounds[i + 1] - bounds[i]) + 1
        }
        return total
    }

    public func contains(_ scalar: UInt32) -> Bool {
        // The last range whose lower bound is at or before the scalar is the only one that can hold it.
        var low = 0
        var high = bounds.count / 2
        while low < high {
            let mid = (low + high) / 2
            if bounds[mid * 2] <= scalar { low = mid + 1 } else { high = mid }
        }
        return low > 0 && scalar <= bounds[low * 2 - 1]
    }

    /// How many of these sorted, unique scalars are missing (one pass over both lists).
    public func missingCount(sorted scalars: [UInt32]) -> Int {
        var missing = 0
        walk(sorted: scalars) { _, present in
            if !present { missing += 1 }
        }
        return missing
    }

    public func missing(sorted scalars: [UInt32]) -> [UInt32] {
        var missing: [UInt32] = []
        walk(sorted: scalars) { scalar, present in
            if !present { missing.append(scalar) }
        }
        return missing
    }

    /// Whether each of these sorted scalars is covered, in the same order.
    func presence(sorted scalars: [UInt32]) -> [Bool] {
        var present: [Bool] = []
        present.reserveCapacity(scalars.count)
        walk(sorted: scalars) { _, isPresent in present.append(isPresent) }
        return present
    }

    private func walk(sorted scalars: [UInt32], _ visit: (UInt32, Bool) -> Void) {
        let rangeCount = bounds.count / 2
        var range = 0
        for scalar in scalars {
            while range < rangeCount && bounds[range * 2 + 1] < scalar { range += 1 }
            visit(scalar, range < rangeCount && bounds[range * 2] <= scalar)
        }
    }

    /// Every covered scalar, in order.
    public var scalars: [UInt32] {
        var all: [UInt32] = []
        all.reserveCapacity(count)
        for i in stride(from: 0, to: bounds.count, by: 2) {
            all.append(contentsOf: bounds[i]...bounds[i + 1])
        }
        return all
    }
}
