import CoreText
import Foundation

public enum FontNames {
    public static func describe(_ fonts: [(family: String, style: String)]) -> String? {
        var seen = Set<[String]>()
        let fonts = fonts.filter { !$0.family.isEmpty && seen.insert([$0.family, $0.style]).inserted }
        if fonts.count == 1 { return name(family: fonts[0].family, style: fonts[0].style) }
        return describe(families: fonts.map(\.family))
    }

    static func name(family: String, style: String) -> String {
        let lowerFamily = family.lowercased(), lowerStyle = style.lowercased()
        if lowerStyle == lowerFamily || lowerStyle.hasPrefix(lowerFamily + " ") { return style }
        if style.isEmpty || lowerFamily.hasSuffix(" " + lowerStyle) { return family }
        return "\(family) \(style)"
    }

    public static func describe(_ faces: [LibraryFace]) -> String? {
        describe(faces.map { ($0.face.displayFamilyName, $0.face.styleName) })
    }

    public static func describe(families names: [String]) -> String? {
        var seen = Set<String>()
        let names = names.filter { !$0.isEmpty && seen.insert($0).inserted }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2:
            let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return "\(sorted[0]) and \(sorted[1])"
        default: return "\(names.count.plain) families"
        }
    }

    static func fonts(inFiles paths: [String]) -> [(family: String, style: String)] {
        paths.flatMap { path in
            FontFiles.descriptors(at: path).compactMap { descriptor -> (family: String, style: String)? in
                // macOS hides families whose names start with a period.
                guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                      !family.isEmpty, !family.hasPrefix(".")
                else { return nil }
                return (family, CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular")
            }
        }
    }
}

extension Sequence where Element == String {
    public func listed(_ conjunction: String = "and") -> String {
        // Not ListFormatter: it follows the Mac's language, and said "Inter, Roboto und Lato" in an English sentence on a German Mac.
        let items = Array(self)
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }
}
