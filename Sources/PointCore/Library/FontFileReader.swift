import CoreText
import Foundation

/// Reads a font file's faces with CoreText, without registering it.
enum FontFileReader {
    static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "dfont", "woff", "woff2"]

    /// Empty when CoreText can't read the file.
    static func faces(atPath path: String) -> [FontFace] {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return descriptors.enumerated().compactMap { index, descriptor in
            face(from: descriptor, id: FaceID(path: path, index: index))
        }
    }

    /// Finder's Date Added, else the creation date.
    static func dateAdded(atPath path: String) -> Date? {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    private static func face(from descriptor: CTFontDescriptor, id: FaceID) -> FontFace? {
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let postScriptName = CTFontCopyPostScriptName(font) as String
        guard !postScriptName.isEmpty else { return nil }
        let familyName = CTFontCopyFamilyName(font) as String
        let styleName = name(kCTFontStyleNameKey, of: font) ?? "Regular"
        let fullName = CTFontCopyFullName(font) as String
        let symbolic = CTFontGetSymbolicTraits(font)
        let lowercasedStyle = styleName.lowercased()
        var axis: WeightAxis?
        if let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] {
            for entry in axes where (entry[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value == weightAxisTag {
                guard let minimum = entry[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                      let maximum = entry[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                      let defaultValue = entry[kCTFontVariationAxisDefaultValueKey as String] as? Double
                else { continue }
                axis = WeightAxis(minimum: minimum, maximum: maximum, defaultValue: defaultValue)
            }
        }
        return FontFace(
            id: id, postScriptName: postScriptName, familyName: familyName, styleName: styleName, fullName: fullName,
            weight: weightClass(of: font),
            isItalic: symbolic.contains(.italicTrait) || lowercasedStyle.contains("italic") || lowercasedStyle.contains("oblique"),
            isMonospaced: symbolic.contains(.monoSpaceTrait),
            familyClass: Int((symbolic.rawValue >> 28) & 0xF),
            manufacturer: name(kCTFontManufacturerNameKey, of: font),
            version: name(kCTFontVersionNameKey, of: font),
            weightAxis: axis
        )
    }

    private static let weightAxisTag: UInt32 = 0x7767_6874  // 'wght'

    private static func name(_ key: CFString, of font: CTFont) -> String? {
        guard let value = CTFontCopyName(font, key) as String? else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// OS/2 usWeightClass when it's in range, else the nearest class to CoreText's weight trait.
    private static func weightClass(of font: CTFont) -> Int {
        if let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), CTFontTableOptions(rawValue: 0)) as Data?, table.count >= 6 {
            let weight = Int(table[table.startIndex + 4]) << 8 | Int(table[table.startIndex + 5])
            if (1...1000).contains(weight) { return weight }
        }
        let traits = CTFontCopyTraits(font) as NSDictionary
        let trait = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
        // AppKit's weight scale: ultraLight -0.8 … regular 0 … black 0.62.
        let scale: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return scale.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
    }
}
