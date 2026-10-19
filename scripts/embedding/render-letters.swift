// Draws the letters of the fonts in a manifest the way Cicero does (Sources/CiceroCore/Similarity/LetterImages.swift),
// for train.py to learn from. Reads the files with CoreText; installs and activates nothing.
//
//   swiftc -O -parse-as-library scripts/embedding/render-letters.swift \
//       Sources/CiceroCore/Similarity/LetterImages.swift -o /tmp/render-letters
//   /tmp/render-letters manifest.json letters
//
// The manifest is a list of {"file": path, "variations": {"wght": 400, …}}, as prepare.py writes it; a variable
// font's other axes are at their defaults. Writes letters.u8, each entry's squares one after the other (an empty
// square block for an entry that couldn't be drawn), letters-advances.f32, the letters' advances, 16 floats an
// entry, and letters.json, whether each was drawn.

import CoreText
import Foundation

@main
struct RenderLetters {
    struct Entry: Decodable {
        var file: String
        var variations: [String: Double]?
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            FileHandle.standardError.write("usage: render-letters manifest.json output-prefix\n".data(using: .utf8)!)
            exit(2)
        }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let block = LetterImages.size * LetterImages.size * LetterImages.letters.count
        let count = LetterImages.letters.count
        var pixels = [UInt8](repeating: 0, count: block * entries.count)
        var advances = [Float](repeating: 0, count: count * entries.count)
        var drawn = [Bool](repeating: false, count: entries.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: entries.count) { position in
            guard let font = font(entries[position]), let letters = LetterImages.draw(font) else { return }
            lock.withLock {
                pixels.replaceSubrange(position * block..<(position + 1) * block, with: letters.pixels)
                advances.replaceSubrange(position * count..<(position + 1) * count, with: letters.advances)
                drawn[position] = true
            }
        }
        try Data(pixels).write(to: URL(fileURLWithPath: arguments[2] + ".u8"))
        try advances.withUnsafeBytes { Data($0) }.write(to: URL(fileURLWithPath: arguments[2] + "-advances.f32"))
        try JSONEncoder().encode(drawn).write(to: URL(fileURLWithPath: arguments[2] + ".json"))
        print("drew \(drawn.count(where: { $0 })) of \(entries.count)")
    }

    /// The file's first face, its axes at their defaults but for the entry's.
    static func font(_ entry: Entry) -> CTFont? {
        let url = URL(fileURLWithPath: entry.file) as CFURL
        guard var descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first else { return nil }
        let axes = CTFontCopyVariationAxes(CTFontCreateWithFontDescriptor(descriptor, 0, nil)) as? [[CFString: Any]] ?? []
        for axis in axes {
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber,
                  let fallback = (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue,
                  let low = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
                  let high = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue
            else { continue }
            let value = entry.variations?[tag(identifier.uint32Value)] ?? fallback
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, identifier, min(max(value, low), high))
        }
        return CTFontCreateWithFontDescriptor(descriptor, 0, nil)
    }

    static func tag(_ identifier: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: identifier >> $0) }, encoding: .ascii) ?? ""
    }
}
