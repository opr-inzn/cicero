import CoreText
import Foundation

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
    public let isExclusive: Bool
    public let options: [Option]
    public var id: Int { type }

    public init(type: Int, name: String, isExclusive: Bool, options: [Option]) {
        self.type = type
        self.name = name
        self.isExclusive = isExclusive
        self.options = options
    }

    public static func load(for face: FontFace) -> [FontFeatureGroup] {
        let font = FontLoader.shared.font(face, size: 12)
        guard let features = CTFontCopyFeatures(font) as? [[String: Any]] else { return [] }
        return features.compactMap { feature in
            // Features with no AAT type (only an OpenType tag) can't be set by type and selector.
            guard let type = feature[kCTFontFeatureTypeIdentifierKey as String] as? Int,
                  type != Int(kAllTypographicFeaturesType),
                  let name = feature[kCTFontFeatureTypeNameKey as String] as? String,
                  let selectors = feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]]
            else { return nil }
            let isExclusive = feature[kCTFontFeatureTypeExclusiveKey as String] as? Bool ?? false
            let listed = selectors.compactMap { selector -> Option? in
                guard let id = selector[kCTFontFeatureSelectorIdentifierKey as String] as? Int,
                      let name = selector[kCTFontFeatureSelectorNameKey as String] as? String,
                      selector[kCTFontOpenTypeFeatureTag as String] as? String != "kern"
                else { return nil }
                return Option(selector: id, name: name, isDefault: selector[kCTFontFeatureSelectorDefaultKey as String] as? Bool ?? false)
            }
            guard let options = isExclusive ? (listed.count > 1 ? listed : nil) : switches(listed) else { return nil }
            return FontFeatureGroup(type: type, name: name, isExclusive: isExclusive, options: options)
        }
    }

    private static func switches(_ listed: [Option]) -> [Option]? {
        // AAT pairs each switch's on selector, an even number, with an off one, the next odd number.
        let on = listed.filter { $0.selector.isMultiple(of: 2) }
        let off = Dictionary(listed.filter { !$0.selector.isMultiple(of: 2) }.map { ($0.selector - 1, $0.isDefault) }, uniquingKeysWith: { a, _ in a })
        guard !on.isEmpty, off.keys.allSatisfy({ key in on.contains { $0.selector == key } }) else { return nil }
        return on.map { option in
            guard let offIsDefault = off[option.selector] else { return option }
            return Option(selector: option.selector, name: option.name, isDefault: option.isDefault || !offIsDefault)
        }
    }
}
