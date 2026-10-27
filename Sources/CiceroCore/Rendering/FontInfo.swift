import CoreText
import Foundation
import Synchronization

/// The name table and other facts the Info panel shows, as label/value pairs in display order.
public struct FontInfo: Sendable {
    public let rows: [(label: String, value: String)]

    public init(rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    /// What `read` found, by face and its file's generation (see `FontLoader.generation(of:)`), so a file that
    /// changed is read again.
    private static let cache = Mutex<[CacheKey: FontInfo]>([:])

    private struct CacheKey: Hashable {
        let face: FaceID
        let generation: Int

        init(_ face: FontFace) {
            self.face = face.id
            generation = FontLoader.shared.generation(of: face.path)
        }
    }

    /// What `read` found for the face, unless its file changed since. Doesn't read the font, so the main thread
    /// can ask.
    public static func cached(_ face: FontFace) -> FontInfo? {
        let key = CacheKey(face)
        return cache.withLock { $0[key] }
    }

    /// Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Vendor ID, Variable weight, Glyphs,
    /// Format, Embedding, Copyright; no weight, as the style's read as the whole family's, and its name says it. Reads
    /// the font, so call off the main thread unless the file wouldn't keep it waiting (see `FontLoader.wouldWait(for:)`),
    /// and keeps what it finds for `cached`.
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
            ("Glyphs", CTFontGetGlyphCount(font).formatted()),
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
