import CiceroCore
import CoreText
import Foundation

public struct FileNames: Sendable, Equatable {
    public var copyright: String?
    public var description: String?
    public var designerURL: String?
    public var manufacturerURL: String?
    public var license: String?
    public var licenseURL: String?

    public static func read(_ face: FontFace) -> FileNames {
        let font = FontLoader.shared.font(face, size: 12)
        // A file that's gone gives some other font: nothing, then.
        guard CTFontCopyPostScriptName(font) as String == face.postScriptName else { return FileNames() }
        func name(_ key: CFString) -> String? {
            guard let value = (CTFontCopyName(font, key) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            return value.isEmpty ? nil : value
        }
        return FileNames(
            copyright: name(kCTFontCopyrightNameKey), description: name(kCTFontDescriptionNameKey), designerURL: name(kCTFontDesignerURLNameKey),
            manufacturerURL: name(kCTFontVendorURLNameKey), license: name(kCTFontLicenseNameKey), licenseURL: name(kCTFontLicenseURLNameKey)
        )
    }

    public static func read(_ faces: [FontFace]) -> [FaceID: FileNames] {
        let read = faces.concurrentMap { ($0.id, FileNames.read($0)) }
        return Dictionary(read) { first, _ in first }
    }
}

extension Array where Element: Sendable {
    func concurrentMap<T: Sendable>(_ transform: @Sendable (Element) -> T) -> [T] {
        guard count > 1 else { return map(transform) }
        let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        nonisolated(unsafe) let output = results
        DispatchQueue.concurrentPerform(iterations: count) { output[$0] = transform(self[$0]) }
        return results.map { $0! }
    }
}
