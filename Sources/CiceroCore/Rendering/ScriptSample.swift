import CoreText
import Foundation
import Synchronization

struct ScriptSample: Hashable, Sendable {
    let short: String
    let long: String

    static let minimumLetters = 20

    static func isNeeded(for text: String, has: (Unicode.Scalar) -> Bool) -> Bool {
        var hasLetters = false
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if has(scalar) { return false }
            hasLetters = true
        }
        return hasLetters
    }

    init?(characters: ScalarRanges, languages: [Language]) {
        let scripts = GlyphGroup.scripts(of: characters).filter { $0.key != "Latin" && $0.value >= Self.minimumLetters }
        guard let script = scripts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return nil }
        var names: [String] = []
        for language in languages.filter(\.isCurrent).sorted(by: { $0.speakers > $1.speakers }) {
            // Without the comma some names end in, like Punjabi's "ਪੰਜਾਬੀ,".
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

public final class ScriptSamples: Sendable {
    private let languages: LanguageCatalog
    private let samples = Mutex<[FaceID: (generation: Int, sample: ScriptSample?)]>([:])

    public init(languages: LanguageCatalog) {
        self.languages = languages
    }

    public func text(_ text: String, for face: FontFace, long: Bool = false, cached: Bool = true, font: CTFont? = nil) -> String {
        guard !FontLoader.shared.wouldWait(for: face.path) else { return text }
        let generation = FontLoader.shared.generation(of: face.path)
        let font = font ?? FontLoader.shared.font(face, size: 12, cached: cached)
        guard ScriptSample.isNeeded(for: text, has: { font.glyph(for: Character($0)) != nil }),
              let sample = sample(for: face, generation: generation, font: font)
        else { return text }
        return long ? sample.long : sample.short
    }

    private func sample(for face: FontFace, generation: Int, font: CTFont) -> ScriptSample? {
        if let known = samples.withLock({ $0[face.id] }), known.generation == generation { return known.sample }
        let sample = ScriptSample(characters: CharacterMap.characters(of: font), languages: languages.languages)
        samples.withLock { $0[face.id] = (generation, sample) }
        return sample
    }
}
