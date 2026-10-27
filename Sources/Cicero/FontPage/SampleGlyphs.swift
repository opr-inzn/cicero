import AppKit
import CiceroCore

/// A glyph copied from a font page's Glyphs, like a stylistic set's "a", a small capital or a ligature, that the
/// page's text draws in place of the characters it stands for once it's pasted there. The text keeps the characters:
/// the family's pages draw them as the glyph, in whichever style they show, and other pages as they are.
nonisolated struct SampleGlyph: Codable, Hashable, Sendable {
    /// The family it was copied from (`Family.id`).
    let family: String
    /// The characters it's drawn for: one, or a ligature's.
    let characters: String
    /// The style it was copied from, and its ID there.
    let path: String
    let index: Int
    let glyph: CGGlyph
    /// Its name in the font, like "a.ss01", which the family's other styles mostly give their own.
    let name: String?
    /// The features that draw it together, for a style that names its glyphs otherwise or not at all.
    let features: [String]

    init(family: String, characters: String, face: FontFace, glyph: CGGlyph, features: [String]) {
        self.family = family
        self.characters = characters
        path = face.id.path
        index = face.id.index
        self.glyph = glyph
        let font = FontLoader.shared.font(face, size: 12)
        name = (CTFontCopyNameForGlyph(font, glyph) as String?).flatMap { $0.isEmpty ? nil : $0 }
        self.features = features
    }

    /// Its glyph in another of the family's styles: the same one in the same style, else the one with its name,
    /// else the one its features draw for its characters.
    func glyph(in font: CTFont, face: FontFace) -> CGGlyph? {
        if face.id == FaceID(path: path, index: index) { return glyph }
        if let name {
            let named = CTFontGetGlyphWithName(font, name as CFString)
            if named != 0 { return named }
        }
        return drawn(in: font)
    }

    /// The one glyph the features draw the characters as, when it isn't what they're drawn as without them.
    private func drawn(in font: CTFont) -> CGGlyph? {
        guard !features.isEmpty else { return nil }
        let settings = features.map { [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 1] as CFDictionary }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        let featured = CTFontCreateCopyWithAttributes(font, 0, nil, descriptor)
        guard let glyphs = Self.glyphs(of: characters, in: featured), glyphs.count == 1,
              glyphs != Self.glyphs(of: characters, in: font) else { return nil }
        return glyphs[0]
    }

    private static func glyphs(of text: String, in font: CTFont) -> [CGGlyph]? {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.flatMap { run in
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            return glyphs
        }
    }
}

/// A glyph pasted into the text, where its characters start, in UTF-16 units.
nonisolated struct SampleGlyphRun: Codable, Hashable, Sendable {
    let location: Int
    let glyph: SampleGlyph

    var range: NSRange { NSRange(location: location, length: (glyph.characters as NSString).length) }
}

/// What Cicero puts on the clipboard along with characters for the font page's text: the glyphs it draws in their
/// place, if any, like an alternate copied from Glyphs. The text pastes them as glyphs, and other apps as characters.
struct SampleClip: Codable {
    let text: String
    let glyphs: [SampleGlyphRun]

    init(text: String, glyphs: [SampleGlyphRun]) {
        self.text = text
        self.glyphs = glyphs
    }

    /// One glyph's characters, the glyph drawn in their place.
    init(text: String, glyph: SampleGlyph?) {
        self.init(text: text, glyphs: glyph.map { [SampleGlyphRun(location: 0, glyph: $0)] } ?? [])
    }

    var data: Data? { try? JSONEncoder().encode(self) }

    /// On the clipboard, in place of what's there.
    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.sampleClip, .string], owner: nil)
        NSPasteboard.general.setString(text, forType: .string)
        if let data { NSPasteboard.general.setData(data, forType: .sampleClip) }
    }

    /// Along with the text a text view put on the pasteboard.
    func add(to pasteboard: NSPasteboard) {
        guard let data else { return }
        pasteboard.addTypes([.sampleClip], owner: nil)
        pasteboard.setData(data, forType: .sampleClip)
    }

    static func read(from pasteboard: NSPasteboard) -> SampleClip? {
        pasteboard.data(forType: .sampleClip).flatMap { try? JSONDecoder().decode(SampleClip.self, from: $0) }
    }
}

extension NSPasteboard.PasteboardType {
    nonisolated static let sampleClip = NSPasteboard.PasteboardType("com.maximilianinzinger.Cicero.sample-text")
}

extension NSAttributedString.Key {
    /// The glyph pasted in place of these characters (`SampleGlyphValue`).
    nonisolated static let sampleGlyph = NSAttributedString.Key("CiceroSampleGlyph")
}

/// A `SampleGlyph` as an attribute's value, equal to another for the same glyph, so that copies pasted side by side
/// share a run.
nonisolated final class SampleGlyphValue: NSObject {
    let glyph: SampleGlyph

    init(_ glyph: SampleGlyph) {
        self.glyph = glyph
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? SampleGlyphValue)?.glyph == glyph
    }

    override var hash: Int { glyph.hashValue }
}

nonisolated extension NSAttributedString {
    /// The glyphs pasted into it whose characters are still there as pasted, in order.
    func sampleGlyphs(in range: NSRange? = nil) -> [SampleGlyphRun] {
        let string = self.string as NSString
        let range = range ?? NSRange(location: 0, length: length)
        var runs: [SampleGlyphRun] = []
        enumerateAttribute(.sampleGlyph, in: range) { value, run, _ in
            guard let glyph = (value as? SampleGlyphValue)?.glyph else { return }
            let length = (glyph.characters as NSString).length
            guard length > 0 else { return }
            // Copies pasted side by side, or what's left of them after typing.
            var location = run.location
            while location + length <= NSMaxRange(run) {
                if string.substring(with: NSRange(location: location, length: length)) == glyph.characters {
                    runs.append(SampleGlyphRun(location: location - range.location, glyph: glyph))
                    location += length
                } else {
                    location += 1
                }
            }
        }
        return runs
    }
}

nonisolated extension NSMutableAttributedString {
    /// Marks the glyphs' characters, those that are still there as pasted.
    func addSampleGlyphs(_ runs: [SampleGlyphRun]) {
        let string = self.string as NSString
        for run in runs where NSMaxRange(run.range) <= length && string.substring(with: run.range) == run.glyph.characters {
            addAttribute(.sampleGlyph, value: SampleGlyphValue(run.glyph), range: run.range)
        }
    }
}
