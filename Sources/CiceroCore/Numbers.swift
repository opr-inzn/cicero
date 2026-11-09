import Foundation

extension BinaryInteger {
    // A String, as SwiftUI's Text puts the Mac's thousands separator into an interpolated whole number, as in Text("\(count) families").
    public var plain: String {
        Int64(self).formatted(.number.grouping(.never))
    }
}
