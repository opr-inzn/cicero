// Reads basic family, style, weight, width, italic and variation axis metadata from font files in a folder
// (for prepare.py --extra), using CoreText without installing or activating anything.
//
//   swiftc -O -parse-as-library scripts/embedding/inspect-fonts.swift -o /tmp/inspect-fonts
//   /tmp/inspect-fonts <folder>

import CoreText
import Foundation

@main
struct InspectFonts {
    struct Axis: Encodable {
        var tag: String
        var min_value: Double
        var max_value: Double
    }
    struct Face: Encodable {
        var file: String
        var family: String
        var style: String
        var weight: Int
        var italic: Bool
        var axes: [Axis]
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write("usage: inspect-fonts <folder>\n".data(using: .utf8)!)
            exit(2)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        var files: [URL] = []
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in e {
                let ext = url.pathExtension.lowercased()
                if ext == "otf" || ext == "ttf" { files.append(url) }
            }
        }
        files.sort { $0.path < $1.path }
        var faces: [Face] = []
        for url in files {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first else { continue }
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            let family = (CTFontCopyAttribute(font, kCTFontFamilyNameAttribute) as? String) ?? ""
            guard !family.isEmpty else { continue }
            let style = (CTFontCopyAttribute(font, kCTFontStyleNameAttribute) as? String) ?? "Regular"
            let traits = CTFontCopyTraits(font) as NSDictionary
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            let italic = (symbolic & CTFontSymbolicTraits.traitItalic.rawValue) != 0
                || style.lowercased().contains("italic") || style.lowercased().contains("oblique")
            var weight = 400
            if let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?, os2.count >= 6 {
                let w = Int(os2[4]) << 8 | Int(os2[5])
                if w >= 100 && w <= 1000 { weight = w }
            }
            var axes: [Axis] = []
            if let rawAxes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] {
                for a in rawAxes {
                    guard let id = a[kCTFontVariationAxisIdentifierKey] as? NSNumber,
                          let low = (a[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
                          let high = (a[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue else { continue }
                    let v = id.uint32Value
                    let tag = String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) }, encoding: .ascii) ?? ""
                    axes.append(Axis(tag: tag, min_value: low, max_value: high))
                }
            }
            faces.append(Face(file: url.path, family: family, style: style, weight: weight, italic: italic, axes: axes))
        }
        let data = try JSONEncoder().encode(faces)
        FileHandle.standardOutput.write(data)
    }
}
