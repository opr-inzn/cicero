import CoreText
import Foundation
import Synchronization

/// Text in a font's own script for its previews, when it has none of the letters of the text they ask for, like a Syriac
/// font asked for Latin, which macOS would set in another font, with that font's weights rather than the font's own axes:
/// the names of the most spoken languages written in its script, in their own letters, that the font has every character
/// of, like ܣܘܪܝܝܐ; or else its first letters of that script.
public struct ScriptSample: Hashable, Sendable {
    /// One name, or a few letters, for small previews like a grid tile.
    public let short: String
    /// A few names, or more letters, for the font page's text.
    public let long: String

    /// Whether a font needs one for `text`: when the text has letters, and the font, which `has` says has a character or
    /// not, none of them.
    public static func isNeeded(for text: String, has: (Unicode.Scalar) -> Bool) -> Bool {
        var hasLetters = false
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if has(scalar) { return false }
            hasLetters = true
        }
        return hasLetters
    }

    /// The sample for a font with `characters`, from `languages`; nil for one without letters of a script other than
    /// Latin, like a symbol font.
    public init?(characters: ScalarRanges, languages: [Language]) {
        let scripts = GlyphGroup.scripts(of: characters).filter { $0.key != "Latin" }
        guard let script = scripts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return nil }
        var names: [String] = []
        for language in languages.filter(\.isCurrent).sorted(by: { $0.speakers > $1.speakers }) {
            // Without the comma some names end in, like Punjabi's ਪੰਜਾਬੀ,
            guard let name = language.autonym?.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)), !name.isEmpty,
                  !names.contains(name),
                  name.unicodeScalars.allSatisfy({ $0.properties.isWhitespace || characters.contains($0.value) }),
                  name.unicodeScalars.contains(where: { UnicodeScripts.script(of: $0.value) == script })
            else { continue }
            names.append(name)
            if names.count == 3 { break }
        }
        if let first = names.first {
            short = first
            long = names.joined(separator: " ")
            return
        }
        var letters: [Unicode.Scalar] = []
        for range in characters.ranges {
            for value in range where letters.count < 24 {
                guard let scalar = Unicode.Scalar(value), UnicodeScripts.script(of: value) == script else { continue }
                switch scalar.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .otherLetter: letters.append(scalar)
                default: break
                }
            }
        }
        guard !letters.isEmpty else { return nil }
        short = String(String.UnicodeScalarView(letters.prefix(4)))
        long = String(String.UnicodeScalarView(letters))
    }
}

/// Each face's `ScriptSample`, worked out the first time a preview needs it.
public final class ScriptSamples: Sendable {
    private let languages: LanguageCatalog
    private let samples = Mutex<[FaceID: ScriptSample?]>([:])

    public init(languages: LanguageCatalog) {
        self.languages = languages
    }

    /// What a preview of `face` sets: `text`, or, when the face has none of its letters, text in its own script (see
    /// `ScriptSample`), `long` or short. `text` while the face's file hasn't been read, as reading it could take a while.
    public func text(_ text: String, for face: FontFace, long: Bool = false) -> String {
        guard !FontLoader.shared.wouldWait(for: face.path) else { return text }
        let font = FontLoader.shared.font(face, size: 12)
        guard ScriptSample.isNeeded(for: text, has: { Self.has($0, font) }), let sample = sample(for: face, font: font) else { return text }
        return long ? sample.long : sample.short
    }

    private func sample(for face: FontFace, font: CTFont) -> ScriptSample? {
        if let known = samples.withLock({ $0[face.id] }) { return known }
        let sample = ScriptSample(characters: ScalarRanges(characterSet: CTFontCopyCharacterSet(font)), languages: languages.languages)
        samples.withLock { $0[face.id] = .some(sample) }
        return sample
    }

    private static func has(_ scalar: Unicode.Scalar, _ font: CTFont) -> Bool {
        var units = Array(String(Character(scalar)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) && glyphs[0] != 0
    }
}
