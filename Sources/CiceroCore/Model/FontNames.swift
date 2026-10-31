import CoreText
import Foundation

/// What toasts call the fonts something happened to: by name where they can, as a style (Inter Bold) or a family
/// (Inter), so it doesn't matter whether a whole family was picked or some of its styles.
public enum FontNames {
    /// One style by its name ("Inter Bold"), the styles of one family by the family's ("Inter"), those of two by
    /// both ("Inter and Roboto"), more by how many families ("12 families"). nil for none.
    public static func describe(_ fonts: [(family: String, style: String)]) -> String? {
        var seen = Set<[String]>()
        let fonts = fonts.filter { !$0.family.isEmpty && seen.insert([$0.family, $0.style]).inserted }
        if fonts.count == 1 { return [fonts[0].family, fonts[0].style].filter { !$0.isEmpty }.joined(separator: " ") }
        return describe(families: fonts.map(\.family))
    }

    public static func describe(_ faces: [LibraryFace]) -> String? {
        describe(faces.map { ($0.face.displayFamilyName, $0.face.styleName) })
    }

    /// One family by its name ("Inter"), two by both, in alphabetical order ("Inter and Roboto"), more by how many
    /// ("12 families"). nil for none.
    public static func describe(families names: [String]) -> String? {
        var seen = Set<String>()
        let names = names.filter { !$0.isEmpty && seen.insert($0).inserted }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2:
            let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return "\(sorted[0]) and \(sorted[1])"
        default: return "\(names.count.formatted()) families"
        }
    }

    /// The fonts in font files, read from the files, for files the library hasn't listed yet. Families macOS hides
    /// (their names start with a period) are left out, as the library leaves them out.
    static func fonts(inFiles paths: [String]) -> [(family: String, style: String)] {
        paths.flatMap { path in
            FontFiles.descriptors(at: path).compactMap { descriptor -> (family: String, style: String)? in
                guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                      !family.isEmpty, !family.hasPrefix(".")
                else { return nil }
                return (family, CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular")
            }
        }
    }
}

extension Sequence where Element == String {
    /// "Inter", "Inter and Roboto", "Inter, Roboto and Lato", in English as the app is: macOS's own list format follows
    /// the Mac's language, so it said "Inter, Roboto und Lato" in an English sentence on a German Mac.
    public func listed(_ conjunction: String = "and") -> String {
        let items = Array(self)
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }
}
