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
            ("Variable weight", face.weightAxis.map { "\(Int($0.minimum))–\(Int($0.maximum))" }),
            ("Glyphs", CTFontGetGlyphCount(font).plain),
            ("Format", FontFormat.of(path: face.path).rawValue),
            ("Embedding", face.embedding?.title),
            ("Copyright", name(kCTFontCopyrightNameKey)),
        ]
        let info = FontInfo(rows: rows.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        })
        cache.withLock { $0[cacheKey] = info }
        return info
    }
}
