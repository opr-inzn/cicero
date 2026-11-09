import Foundation

extension BinaryInteger {
    // A String, as SwiftUI's Text puts the Mac's thousands separator into a whole number put in as it is, as in Text("\(count) families").
    public var plain: String {
        Int64(self).formatted(.number.grouping(.never))
    }
}
