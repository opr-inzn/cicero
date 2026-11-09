import AppKit
import CiceroCore

nonisolated struct SampleGlyph: Codable, Hashable, Sendable {
    let family: String
    let characters: String
    let path: String
    let index: Int
    let glyph: CGGlyph
    let name: String?
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

    func glyph(in font: CTFont, face: FontFace) -> CGGlyph? {
        if face.id == FaceID(path: path, index: index) { return glyph }
        if let name {
            let named = CTFontGetGlyphWithName(font, name as CFString)
            if named != 0 { return named }
        }
        return drawn(in: font)
    }

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

nonisolated struct SampleGlyphRun: Codable, Hashable, Sendable {
    let location: Int
    let glyph: SampleGlyph

    var range: NSRange { NSRange(location: location, length: (glyph.characters as NSString).length) }
}

struct SampleClip: Codable {
    let text: String
    let glyphs: [SampleGlyphRun]

    init(text: String, glyphs: [SampleGlyphRun]) {
        self.text = text
        self.glyphs = glyphs
    }

    init(text: String, glyph: SampleGlyph?) {
        self.init(text: text, glyphs: glyph.map { [SampleGlyphRun(location: 0, glyph: $0)] } ?? [])
    }

    var data: Data? { try? JSONEncoder().encode(self) }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.sampleClip, .string], owner: nil)
        NSPasteboard.general.setString(text, forType: .string)
        if let data { NSPasteboard.general.setData(data, forType: .sampleClip) }
    }

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
    nonisolated static let sampleGlyph = NSAttributedString.Key("CiceroSampleGlyph")
}

nonisolated final class SampleGlyphValue: NSObject {
    let glyph: SampleGlyph

    init(_ glyph: SampleGlyph) {
        self.glyph = glyph
    }

    // Equal for the same glyph, so that copies pasted side by side share a run.
    override func isEqual(_ object: Any?) -> Bool {
        (object as? SampleGlyphValue)?.glyph == glyph
    }

    override var hash: Int { glyph.hashValue }
}

nonisolated extension NSAttributedString {
    func sampleGlyphs(in range: NSRange? = nil) -> [SampleGlyphRun] {
        let string = self.string as NSString
        let range = range ?? NSRange(location: 0, length: length)
        var runs: [SampleGlyphRun] = []
        enumerateAttribute(.sampleGlyph, in: range) { value, run, _ in
            guard let glyph = (value as? SampleGlyphValue)?.glyph else { return }
            let length = (glyph.characters as NSString).length
            guard length > 0 else { return }
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
    func addSampleGlyphs(_ runs: [SampleGlyphRun]) {
        let string = self.string as NSString
        for run in runs where NSMaxRange(run.range) <= length && string.substring(with: run.range) == run.glyph.characters {
            addAttribute(.sampleGlyph, value: SampleGlyphValue(run.glyph), range: run.range)
        }
    }
}
