import Foundation

extension BinaryInteger {
    /// A whole number as Cicero writes it everywhere, counts as much as weights and axis values: without a thousands
    /// separator, 4205, not 4,205 or 4.205, whatever the Mac's language. A String, so a SwiftUI text it's put into, as
    /// in `Text("\(count.plain) families")`, takes it as it is: a whole number put in as it is gets the separator there.
    public var plain: String {
        Int64(self).formatted(.number.grouping(.never))
    }
}
