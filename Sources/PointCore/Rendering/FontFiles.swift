import CoreText
import Foundation

/// Reads faces straight from font files with CoreText, whether or not they're installed.
enum FontFiles {
    /// Every face in the file, in file order; empty when CoreText can't read it.
    static func descriptors(at path: String) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL) as? [CTFontDescriptor] ?? []
    }

    /// The face among a file's descriptors: the one at its index when the name agrees, else the
    /// one with its PostScript name, else whatever is at its index.
    static func descriptor(for face: FontFace, in descriptors: [CTFontDescriptor]) -> CTFontDescriptor? {
        guard !descriptors.isEmpty else { return nil }
        let index = face.id.index
        if index < descriptors.count, postScriptName(of: descriptors[index]) == face.postScriptName {
            return descriptors[index]
        }
        if let named = descriptors.first(where: { postScriptName(of: $0) == face.postScriptName }) {
            return named
        }
        return index < descriptors.count ? descriptors[index] : descriptors[0]
    }

    static func postScriptName(of descriptor: CTFontDescriptor) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    }

    /// An installed font with this name, for files Point can't read; CoreText substitutes a
    /// default font when none is installed.
    static func installedDescriptor(named postScriptName: String) -> CTFontDescriptor {
        CTFontCopyFontDescriptor(CTFontCreateWithName(postScriptName as CFString, 0, nil))
    }
}
