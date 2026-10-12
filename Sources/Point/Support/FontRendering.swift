import AppKit
import CoreText
import SwiftUI

struct FeatureSetting: Hashable, Sendable {
    var type: Int
    var selector: Int
}

/// Creates CTFonts straight from font files, so inactive fonts preview without being installed.
final class FontCache: @unchecked Sendable {
    static let shared = FontCache()

    private let lock = NSLock()
    private var descriptors: [String: [CTFontDescriptor]] = [:]
    private let fonts = NSCache<NSString, CTFont>()

    private init() {
        fonts.countLimit = 4000
    }

    func font(_ face: FontFace, size: CGFloat, weight: Double? = nil, features: [FeatureSetting] = []) -> CTFont {
        let featureKey = features.map { "\($0.type):\($0.selector)" }.joined(separator: ",")
        let weightKey = face.weightAxis == nil ? "" : weight.map { String(Int($0)) } ?? ""
        let key = "\(face.id)|\(size)|\(weightKey)|\(featureKey)" as NSString
        if let cached = fonts.object(forKey: key) { return cached }

        guard var descriptor = descriptor(for: face) else {
            return CTFontCreateWithName(face.postScriptName as CFString, size, nil)
        }
        if let axis = face.weightAxis, let weight {
            let value = min(max(weight, axis.min), axis.max)
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: axis.tag) as CFNumber, CGFloat(value))
        }
        if !features.isEmpty {
            let settings = features.map {
                [kCTFontFeatureTypeIdentifierKey as String: $0.type, kCTFontFeatureSelectorIdentifierKey as String: $0.selector]
            }
            descriptor = CTFontDescriptorCreateCopyWithAttributes(
                descriptor, [kCTFontFeatureSettingsAttribute as String: settings] as CFDictionary
            )
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        fonts.setObject(font, forKey: key)
        return font
    }

    private func descriptor(for face: FontFace) -> CTFontDescriptor? {
        lock.lock()
        if let list = descriptors[face.path] {
            lock.unlock()
            return face.index < list.count ? list[face.index] : nil
        }
        lock.unlock()
        let list = (CTFontManagerCreateFontDescriptorsFromURL(face.url as CFURL) as? [CTFontDescriptor]) ?? []
        lock.lock()
        descriptors[face.path] = list
        lock.unlock()
        return face.index < list.count ? list[face.index] : nil
    }

    func invalidate() {
        lock.lock()
        descriptors.removeAll()
        lock.unlock()
        fonts.removeAllObjects()
    }
}

// MARK: - Metadata

struct FontMetadata {
    var rows: [(String, String)]

    init(face: FontFace) {
        let font = FontCache.shared.font(face, size: 12)
        func name(_ key: CFString) -> String? {
            guard let value = CTFontCopyName(font, key) as String? else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var rows: [(String, String)] = [
            ("Family", face.familyName),
            ("Style", face.styleName),
            ("Full name", face.fullName),
            ("PostScript name", face.postScriptName),
        ]
        if let version = name(kCTFontVersionNameKey) { rows.append(("Version", version)) }
        if let designer = name(kCTFontDesignerNameKey) { rows.append(("Designer", designer)) }
        if let manufacturer = name(kCTFontManufacturerNameKey) { rows.append(("Manufacturer", manufacturer)) }
        rows.append(("Weight", "\(face.weightClass)"))
        if let axis = face.weightAxis {
            rows.append(("Variable weight", "\(Int(axis.min))–\(Int(axis.max))"))
        }
        rows.append(("Glyphs", "\(CTFontGetGlyphCount(font))"))
        rows.append(("Format", FontMetadata.format(of: face.url)))
        if let copyright = name(kCTFontCopyrightNameKey) { rows.append(("Copyright", copyright)) }
        self.rows = rows
    }

    static func format(of url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "otf": "OpenType, PostScript outlines"
        case "ttf": "OpenType, TrueType outlines"
        case "ttc", "otc": "Font Collection"
        case "dfont": "Datafork TrueType"
        case "woff", "woff2": "Web Font"
        default: url.pathExtension.uppercased()
        }
    }
}

// MARK: - OpenType features

struct FontFeatureType: Identifiable {
    struct Selector: Identifiable {
        var id: Int
        var name: String
        var isDefault: Bool
    }

    var id: Int
    var name: String
    var isExclusive: Bool
    var selectors: [Selector]

    static func load(for face: FontFace) -> [FontFeatureType] {
        let font = FontCache.shared.font(face, size: 12)
        guard let raw = CTFontCopyFeatures(font) as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let id = (entry[kCTFontFeatureTypeIdentifierKey as String] as? NSNumber)?.intValue,
                  let name = entry[kCTFontFeatureTypeNameKey as String] as? String,
                  let selectors = entry[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]],
                  id != 0 /* all typographic features */ else { return nil }
            let exclusive = (entry[kCTFontFeatureTypeExclusiveKey as String] as? NSNumber)?.boolValue ?? false
            let parsed: [Selector] = selectors.compactMap { selector in
                guard let sid = (selector[kCTFontFeatureSelectorIdentifierKey as String] as? NSNumber)?.intValue,
                      let sname = selector[kCTFontFeatureSelectorNameKey as String] as? String else { return nil }
                let isDefault = (selector[kCTFontFeatureSelectorDefaultKey as String] as? NSNumber)?.boolValue ?? false
                return Selector(id: sid, name: sname, isDefault: isDefault)
            }
            return parsed.isEmpty ? nil : FontFeatureType(id: id, name: name, isExclusive: exclusive, selectors: parsed)
        }
    }
}

// MARK: - Character grid

struct CharacterSection: Identifiable {
    var id: String { title }
    var title: String
    var scalars: [UInt32]
}

enum CharacterSections {
    static let order = ["Latin", "Numbers", "Symbols & Punctuation", "Greek", "Cyrillic", "Hebrew", "Arabic", "Indic",
                        "Thai", "Hangul", "Kana", "CJK Ideographs", "Other Letters", "Marks"]

    /// Capped so fonts with huge CJK repertoires stay quick to show.
    private static let limit = 6000

    static func compute(for face: FontFace) -> [CharacterSection] {
        let font = FontCache.shared.font(face, size: 12)
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        var groups: [String: [UInt32]] = [:]
        var count = 0
        outer: for plane in 0...16 where set.hasMember(inPlane: UInt8(plane)) {
            let start = UInt32(plane) << 16
            for value in start...(start + 0xFFFF) {
                guard let scalar = Unicode.Scalar(value), set.contains(scalar), let group = group(for: scalar) else { continue }
                groups[group, default: []].append(value)
                count += 1
                if count >= limit { break outer }
            }
        }
        if var latin = groups["Latin"] {
            latin.sort { latinSortKey($0) < latinSortKey($1) }
            groups["Latin"] = latin
        }
        return order.compactMap { title in groups[title].map { CharacterSection(title: title, scalars: $0) } }
    }

    private static func group(for scalar: Unicode.Scalar) -> String? {
        let props = scalar.properties
        switch props.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return nil
        case .decimalNumber, .otherNumber, .letterNumber:
            return "Numbers"
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return "Marks"
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return script(of: scalar.value)
        default:
            return "Symbols & Punctuation"
        }
    }

    private static func script(of v: UInt32) -> String {
        switch v {
        case 0x0000...0x024F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFB00...0xFB06: "Latin"
        case 0x0370...0x03FF, 0x1F00...0x1FFF: "Greek"
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: "Cyrillic"
        case 0x0590...0x05FF, 0xFB1D...0xFB4F: "Hebrew"
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: "Arabic"
        case 0x0900...0x0DFF: "Indic"
        case 0x0E00...0x0E7F: "Thai"
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: "Hangul"
        case 0x3040...0x30FF, 0x31F0...0x31FF: "Kana"
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2FFFF: "CJK Ideographs"
        default: "Other Letters"
        }
    }

    /// Orders like a type specimen: A a À Á … à á … Ā ā B b …
    private static func latinSortKey(_ v: UInt32) -> (String, Int, UInt32) {
        let decomposed = String(Unicode.Scalar(v)!).decomposedStringWithCanonicalMapping
        let base = decomposed.unicodeScalars.first.map { String($0).lowercased() } ?? ""
        return (base, decomposed.unicodeScalars.count > 1 ? 1 : 0, v)
    }
}

// MARK: - Colors

enum PreviewColorMode: String, CaseIterable {
    case light, dark, custom
}

struct PreviewColors {
    var foreground: Color
    var background: Color

    /// The window chrome follows the canvas so toolbar text stays readable.
    var colorScheme: ColorScheme {
        guard let color = NSColor(background).usingColorSpace(.sRGB) else { return .light }
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5 ? .dark : .light
    }

    init(mode: PreviewColorMode, foregroundHex: String, backgroundHex: String) {
        switch mode {
        case .light:
            foreground = .black
            background = .white
        case .dark:
            foreground = .white
            background = .black
        case .custom:
            foreground = Color(hex: foregroundHex) ?? .white
            background = Color(hex: backgroundHex) ?? .orange
        }
    }
}

extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum Prefs {
    static let pointSize = "browser.pointSize"
    static let weight = "browser.weight"
    static let sampleText = "browser.sampleText"
    static let viewMode = "browser.viewMode"
    static let colorMode = "display.colorMode"
    static let customForeground = "display.customForeground"
    static let customBackground = "display.customBackground"
    static let detailPointSize = "detail.pointSize"
    static let detailWeight = "detail.weight"
    static let detailTracking = "detail.tracking"
    static let detailText = "detail.text"
}
