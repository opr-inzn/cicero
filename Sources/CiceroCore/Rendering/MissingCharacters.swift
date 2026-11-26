import CoreText
import Foundation

public extension CTFont {
    func missingCharacters(in text: String) -> [NSRange] {
        var missing: [NSRange] = []
        var offset = 0
        for cluster in text {
            let composed = Array(String(cluster).precomposedStringWithCanonicalMapping.unicodeScalars)
            if composed.count == 1, glyph(for: composed[0].value) != nil {
                offset += cluster.utf16.count
                continue
            }
            for scalar in cluster.unicodeScalars {
                let length = UTF16.width(scalar)
                // Not a variation selector, as the one that asks for an emoji, which no font maps to a glyph of its own.
                if scalar.isCheckable, !scalar.properties.isDefaultIgnorableCodePoint, glyph(for: scalar.value) == nil {
                    missing.append(NSRange(location: offset, length: length))
                }
                offset += length
            }
        }
        return missing
    }
}
