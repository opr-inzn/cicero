import CoreText
import Foundation

/// An OpenType feature setting (AAT type/selector as CoreText reports them).
public struct FeatureSetting: Hashable, Codable, Sendable {
    public var type: Int
    public var selector: Int

    public init(type: Int, selector: Int) {
        self.type = type
        self.selector = selector
    }
}

/// Creates CTFonts straight from font files, so inactive fonts preview without being installed.
/// Thread-safe. Descriptors are prefetched in the background after scans so scrolling never parses files.
public final class FontLoader: Sendable {
    public static let shared = FontLoader()

    public init() {
        fatalError("Implemented in PointCore")
    }

    /// `weight` sets the weight axis of variable faces (clamped to its range); ignored otherwise.
    public func font(_ face: FontFace, size: CGFloat, weight: Double? = nil, features: [FeatureSetting] = []) -> CTFont {
        fatalError("Implemented in PointCore")
    }

    /// Loads descriptors for these faces at low priority, in order.
    public func prefetch(_ faces: [FontFace]) {
        fatalError("Implemented in PointCore")
    }

    /// Drops what's cached for files that changed or went away.
    public func invalidate(paths: Set<String>) {
        fatalError("Implemented in PointCore")
    }
}

/// A group of OpenType features as CoreText describes them for one face.
public struct FontFeatureGroup: Identifiable, Sendable {
    public struct Option: Identifiable, Sendable {
        public let selector: Int
        public let name: String
        public let isDefault: Bool
        public var id: Int { selector }

        public init(selector: Int, name: String, isDefault: Bool) {
            self.selector = selector
            self.name = name
            self.isDefault = isDefault
        }
    }

    public let type: Int
    public let name: String
    /// One option at a time (a menu) rather than independent switches.
    public let isExclusive: Bool
    public let options: [Option]
    public var id: Int { type }

    public init(type: Int, name: String, isExclusive: Bool, options: [Option]) {
        self.type = type
        self.name = name
        self.isExclusive = isExclusive
        self.options = options
    }

    /// The face's optional features; reads the font, so call off the main thread.
    public static func load(for face: FontFace) -> [FontFeatureGroup] {
        fatalError("Implemented in PointCore")
    }
}

/// The name table and other facts the Info panel shows, as label/value pairs in display order.
public struct FontInfo: Sendable {
    public let rows: [(label: String, value: String)]

    public init(rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    /// Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Weight, Variable
    /// weight, Glyphs, Format, Copyright. Reads the font; call off the main thread.
    public static func read(_ face: FontFace) -> FontInfo {
        fatalError("Implemented in PointCore")
    }
}

/// A face's characters grouped for the glyph grid.
public struct GlyphSection: Identifiable, Sendable {
    public let title: String
    public let scalars: [UInt32]
    public var id: String { title }

    public init(title: String, scalars: [UInt32]) {
        self.title = title
        self.scalars = scalars
    }

    /// Latin, Numbers, Symbols & punctuation, then other scripts by name, then "Other". Limits very
    /// large fonts to a sensible number of characters per section.
    public static func sections(for coverage: ScalarRanges) -> [GlyphSection] {
        fatalError("Implemented in PointCore")
    }

    /// The Unicode name, e.g. "LATIN SMALL LETTER A WITH ACUTE".
    public static func name(of scalar: UInt32) -> String? {
        fatalError("Implemented in PointCore")
    }
}
