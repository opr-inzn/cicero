import CoreText
import Foundation

struct ScannedFile: Sendable {
    var path: String
    var faces: [FontFace]
    var isActive: Bool
    var folderID: UUID?
}

/// Finds every font file Point should know about: everything macOS has active, plus the watched folders.
enum FontScanner {
    static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "dfont", "woff", "woff2"]

    struct Folder: Sendable {
        var id: UUID
        var path: String
    }

    static func scan(folders: [Folder], progress: @escaping @Sendable (String) -> Void) -> [ScannedFile] {
        let fm = FileManager.default
        var entries: [String: (active: Bool, folder: UUID?)] = [:]

        progress("Finding fonts…")
        for url in (CTFontManagerCopyAvailableFontURLs() as? [URL]) ?? [] {
            let path = url.standardizedFileURL.path
            if fm.fileExists(atPath: path) { entries[path] = (true, nil) }
        }
        // macOS activates anything in the Fonts folders, so treat them as active even before fontd catches up.
        for dir in [NSHomeDirectory() + "/Library/Fonts", "/Library/Fonts"] {
            for path in fontFiles(in: dir) {
                entries[path, default: (true, nil)].active = true
            }
        }
        for folder in folders {
            for path in fontFiles(in: folder.path) {
                entries[path, default: (false, nil)].folder = folder.id
            }
        }

        let paths = entries.keys.sorted()
        var cache = FaceCache.load()
        var faces = [[FontFace]](repeating: [], count: paths.count)
        var stamps = [FaceCache.Stamp?](repeating: nil, count: paths.count)
        var toParse: [Int] = []
        for (i, path) in paths.enumerated() {
            let stamp = FaceCache.stamp(of: path)
            stamps[i] = stamp
            if let stamp, let cached = cache.files[path], cached.stamp == stamp {
                faces[i] = cached.faces
            } else {
                toParse.append(i)
            }
        }

        if !toParse.isEmpty {
            progress("Identifying fonts…")
            let counter = Counter()
            let total = toParse.count
            faces.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: total) { k in
                    let i = toParse[k]
                    buffer[i] = parseFile(paths[i])
                    let done = counter.increment()
                    if done % 200 == 0 { progress("Identifying fonts… \(done) of \(total)") }
                }
            }
            var files: [String: FaceCache.Entry] = [:]
            for (i, path) in paths.enumerated() {
                if let stamp = stamps[i] { files[path] = .init(stamp: stamp, faces: faces[i]) }
            }
            cache.files = files
            cache.save()
        }

        return paths.enumerated().map { i, path in
            ScannedFile(path: path, faces: faces[i], isActive: entries[path]!.active, folderID: entries[path]!.folder)
        }
    }

    static func fontFiles(in directory: String) -> [String] {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]
        ) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator where fontExtensions.contains(url.pathExtension.lowercased()) {
            result.append(url.standardizedFileURL.path)
        }
        return result
    }

    static func parseFile(_ path: String) -> [FontFace] {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor] else { return [] }
        return descriptors.enumerated().map { index, descriptor in
            face(from: descriptor, path: path, index: index)
        }
    }

    private static func face(from descriptor: CTFontDescriptor, path: String, index: Int) -> FontFace {
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let traits = CTFontGetSymbolicTraits(font)
        let style = (CTFontCopyName(font, kCTFontStyleNameKey) as String?) ?? "Regular"
        let lowerStyle = style.lowercased()
        var manufacturer = (CTFontCopyName(font, kCTFontManufacturerNameKey) as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if manufacturer?.isEmpty == true { manufacturer = nil }
        return FontFace(
            path: path,
            index: index,
            postScriptName: CTFontCopyPostScriptName(font) as String,
            familyName: CTFontCopyFamilyName(font) as String,
            styleName: style,
            fullName: CTFontCopyFullName(font) as String,
            weightClass: os2WeightClass(font) ?? weightClassFromTraits(font),
            isItalic: traits.contains(.traitItalic) || lowerStyle.contains("italic") || lowerStyle.contains("oblique"),
            isMonospace: traits.contains(.traitMonoSpace),
            fontClass: Int((traits.rawValue >> 28) & 0xF),
            manufacturer: manufacturer,
            weightAxis: weightAxis(font)
        )
    }

    private static func os2WeightClass(_ font: CTFont) -> Int? {
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?, table.count >= 6 else {
            return nil
        }
        let start = table.startIndex
        let value = Int(table[start + 4]) << 8 | Int(table[start + 5])
        return (1...1000).contains(value) ? value : nil
    }

    private static func weightClassFromTraits(_ font: CTFont) -> Int {
        let traits = CTFontCopyTraits(font) as? [String: Any]
        let weight = (traits?[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
        let table: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return table.min { abs($0.0 - weight) < abs($1.0 - weight) }!.1
    }

    private static func weightAxis(_ font: CTFont) -> VariationAxis? {
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return nil }
        for axis in axes {
            guard let tag = (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value,
                  tag == 0x7767_6874 /* 'wght' */ else { continue }
            func value(_ key: CFString, _ fallback: Double) -> Double {
                (axis[key as String] as? NSNumber)?.doubleValue ?? fallback
            }
            return VariationAxis(
                tag: tag,
                min: value(kCTFontVariationAxisMinimumValueKey, 100),
                max: value(kCTFontVariationAxisMaximumValueKey, 900)
            )
        }
        return nil
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Parsed faces keyed by file path, invalidated by modification date and size.
struct FaceCache: Codable {
    struct Stamp: Codable, Equatable {
        var modified: Double
        var size: Int64
    }

    struct Entry: Codable {
        var stamp: Stamp
        var faces: [FontFace]
    }

    var version = 1
    var files: [String: Entry] = [:]

    private static var url: URL { Persistence.cacheDirectory.appendingPathComponent("faces-v1.plist") }

    static func load() -> FaceCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? PropertyListDecoder().decode(FaceCache.self, from: data),
              cache.version == 1 else { return FaceCache() }
        return cache
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Persistence.cacheDirectory, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(self).write(to: Self.url, options: .atomic)
        } catch {
            NSLog("Point: failed to save face cache: \(error)")
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    static func stamp(of path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        return Stamp(modified: modified, size: Int64(info.st_size))
    }
}
