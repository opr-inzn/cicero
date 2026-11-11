import CoreText
import Foundation
import Synchronization

public struct FontInfo: Sendable {
    public let rows: [(label: String, value: String)]

    public init(rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    private static let cache = Mutex<[CacheKey: FontInfo]>([:])

    private struct CacheKey: Hashable {
        let face: FaceID
        let generation: Int

        init(_ face: FontFace) {
            self.face = face.id
            generation = FontLoader.shared.generation(of: face.path)
        }
    }

    public static func cached(_ face: FontFace) -> FontInfo? {
        let key = CacheKey(face)
        return cache.withLock { $0[key] }
    }

    public static func read(_ face: FontFace) -> FontInfo {
        let cacheKey = CacheKey(face)
        let font = FontLoader.shared.font(face, size: 12)
        let names = NameTable(CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?)
        func name(_ id: Int, _ key: CFString, else fallback: String? = nil) -> String? {
            guard let names else { return (CTFontCopyName(font, key) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback }
            return names.english(id)
        }
        func label(_ text: String, _ id: Int) -> String { names == nil ? text : "\(text) (ID \(id))" }
        let axes = FontLoader.shared.axes(of: face)
        func range(_ tag: String) -> String? {
            axes.first { $0.tag == tag && !$0.isHidden }.map { axis in
                [axis.minimum, axis.maximum].map { $0.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) }.joined(separator: "–")
            }
        }
        let rows: [(String, String?)] = [
            (label("Family", 1), name(1, kCTFontFamilyNameKey, else: face.familyName)),
            (label("Style", 2), name(2, kCTFontSubFamilyNameKey, else: face.styleName)),
            ("Typographic Family (ID 16)", names?.english(16)),
            ("Typographic Style (ID 17)", names?.english(17)),
            (label("Full Name", 4), name(4, kCTFontFullNameKey, else: face.fullName)),
            (label("PostScript Name", 6), name(6, kCTFontPostScriptNameKey, else: face.postScriptName)),
            (label("Version", 5), name(5, kCTFontVersionNameKey, else: face.version).map(FontFace.displayVersion)),
            (label("Designer", 9), name(9, kCTFontDesignerNameKey)),
            (label("Manufacturer", 8), name(8, kCTFontManufacturerNameKey, else: face.manufacturer)),
            ("Vendor ID", face.vendorID),
            ("Weight", range("wght")),
            ("Width", range("wdth")),
            ("Slant", range("slnt")),
            ("Italic", range("ital")),
            ("Optical Size", range("opsz")),
            ("Glyphs", CTFontGetGlyphCount(font).plain),
            ("Format", FontFormat.of(path: face.path).rawValue),
            ("Embedding", face.embedding?.title),
            (label("Copyright", 0), name(0, kCTFontCopyrightNameKey)),
        ]
        let info = FontInfo(rows: rows.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        })
        cache.withLock { cache in
            if cache.count >= 500 { cache.removeAll() }
            cache[cacheKey] = info
        }
        return info
    }
}
