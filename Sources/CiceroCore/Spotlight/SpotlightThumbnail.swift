import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A family's picture in Spotlight's results, where it takes the place of the app's icon, which sits on it small: "Ag"
/// set in its regular style, in black on a white card, as a PNG. Spotlight shows `thumbnailData` but not `thumbnailURL`
/// and `darkThumbnailURL` (macOS 26.6), so the picture is one for both appearances, and black letters on a clear
/// ground all but disappear in Dark Mode; on a card they read in both, as the font files Spotlight lists do.
///
/// What they cost, measured on the 1,180 families of a real library: about 1.5 ms each on one core (half a
/// millisecond to make the font from a file the prefetch has read, half to draw, a third to encode), so under two
/// seconds for all of them, and 2.4 KB each at 128 pixels, 2.8 MB for 1,200. HEIC was a third smaller but took 65 ms
/// each to encode, 80 seconds for the library. They're made only for the families whose items change.
enum SpotlightThumbnail {
    /// Pixels on each side.
    static let pixels = 128
    /// Goes up whenever the pictures look different, so every item gets a new one.
    static let version = 2

    /// nil when the file can't be read now without waiting, as from a server or a cloud service that keeps it online
    /// only, or has no characters to show.
    static func png(for face: FontFace, loader: FontLoader = .shared) -> Data? {
        guard !loader.wouldWait(for: face.path) else { return nil }
        let font = loader.uncachedFont(face, size: 100)
        guard let text = sample(in: font) else { return nil }
        let size = CGFloat(pixels)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size / 32, dy: size / 32),
                               cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil))
        context.fillPath()
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]))
        // The ink, not the font's line, fills the card, whatever the font's proportions, with room left for the app's
        // icon in the corner.
        let ink = CTLineGetImageBounds(line, context)
        guard ink.width > 0, ink.height > 0 else { return nil }
        let scale = min(size * 0.62 / ink.width, size * 0.62 / ink.height)
        context.translateBy(x: size / 2, y: size / 2)
        context.scaleBy(x: scale, y: scale)
        context.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// "Ag" when the font has both, "AG" for capitals only, else the first two characters it has: a symbol font's or
    /// a script's own.
    static func sample(in font: CTFont) -> String? {
        let characters = CTFontCopyCharacterSet(font)
        func has(_ value: UInt32) -> Bool { CFCharacterSetIsLongCharacterMember(characters, value) }
        if has(0x41) { if has(0x67) { return "Ag" } else if has(0x47) { return "AG" } }
        var found = String.UnicodeScalarView()
        for value in UInt32(0x21)...0x10_FFFF where has(value) {
            guard let scalar = Unicode.Scalar(value), !scalar.properties.isWhitespace,
                  ![.control, .format, .surrogate, .unassigned].contains(scalar.properties.generalCategory) else { continue }
            found.append(scalar)
            if found.count == 2 { break }
        }
        return found.isEmpty ? nil : String(found)
    }
}
