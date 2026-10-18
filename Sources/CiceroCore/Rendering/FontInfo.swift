import CoreText
import Foundation

/// The name table and other facts the Info panel shows, as label/value pairs in display order.
public struct FontInfo: Sendable {
    public let rows: [(label: String, value: String)]

    public init(rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    /// Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Vendor ID, Weight, Variable
    /// weight, Glyphs, Format, Embedding, Copyright. Reads the font; call off the main thread.
    public static func read(_ face: FontFace) -> FontInfo {
        let font = FontLoader.shared.font(face, size: 12)
        func name(_ key: CFString) -> String? {
            (CTFontCopyName(font, key) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let version = (name(kCTFontVersionNameKey) ?? face.version).map(FontFace.displayVersion)
        let rows: [(String, String?)] = [
            ("Family", name(kCTFontFamilyNameKey) ?? face.familyName),
            ("Style", name(kCTFontSubFamilyNameKey) ?? face.styleName),
            ("Full name", name(kCTFontFullNameKey) ?? face.fullName),
            ("PostScript name", name(kCTFontPostScriptNameKey) ?? face.postScriptName),
            ("Version", version),
            ("Designer", name(kCTFontDesignerNameKey)),
            ("Manufacturer", name(kCTFontManufacturerNameKey) ?? face.manufacturer),
            ("Vendor ID", face.vendorID),
            ("Weight", String(face.weight)),
            ("Variable weight", face.weightAxis.map { "\(Int($0.minimum))–\(Int($0.maximum))" }),
            ("Glyphs", CTFontGetGlyphCount(font).formatted()),
            ("Format", FontFormat.of(path: face.path).rawValue),
            ("Embedding", face.embedding?.title),
            ("Copyright", name(kCTFontCopyrightNameKey)),
        ]
        return FontInfo(rows: rows.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        })
    }
}
