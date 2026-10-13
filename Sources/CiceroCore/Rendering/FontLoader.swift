import CoreText
import Foundation
import Synchronization

/// An OpenType feature setting (AAT type/selector as CoreText reports them).
public struct FeatureSetting: Hashable, Codable, Sendable {
    public var type: Int
    public var selector: Int

    public init(type: Int, selector: Int) {
        self.type = type
        self.selector = selector
    }
}

/// Creates CTFonts straight from font files, so inactive fonts preview without being installed.
/// Thread-safe. Descriptors are prefetched in the background after scans so scrolling never parses files,
/// and the scanner hands over the ones it reads, so a new file is read once.
public final class FontLoader: Sendable {
    public static let shared = FontLoader()

    private let state = Mutex(State())
    private let fonts = FontCache(limit: 2000)
    /// Files read at once by a prefetch: enough to warm up thousands of files in well under a second,
    /// while leaving cores for drawing.
    private static let prefetchLanes = 4

    private struct State: Sendable {
        /// The faces of every file read so far (empty for files CoreText can't read).
        var descriptors: [String: FileDescriptors] = [:]
        /// Files a prefetch is about to read.
        var pending: Set<String> = []
        /// Files waiting to be prefetched, the next one last; the latest request goes first.
        var queue: [String] = []
        var lanes = 0
        /// Bumped by `invalidate`, so fonts made from an old version of a file are never served again.
        var generations: [String: Int] = [:]
    }

    /// The 'wght' axis.
    private static let weightAxisID = 0x7767_6874

    public init() {}

    /// `weight` sets the weight axis of variable faces (clamped to its range); ignored otherwise.
    public func font(_ face: FontFace, size: CGFloat, weight: Double? = nil, features: [FeatureSetting] = []) -> CTFont {
        let weight = face.weightAxis.flatMap { axis in weight.map { min(max($0, axis.minimum), axis.maximum) } }
        let features = features.sorted { ($0.type, $0.selector) < ($1.type, $1.selector) }
        let generation = state.withLock { $0.generations[face.path] ?? 0 }
        var key = "\(face.id)|\(generation)|\(Int((size * 2).rounded()))"
        if let weight { key += "|w\(Int(weight.rounded()))" }
        for feature in features { key += "|\(feature.type):\(feature.selector)" }
        if let font = fonts[key] { return font }

        var descriptor = descriptor(for: face)
        if let weight {
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: Self.weightAxisID), weight)
        }
        for feature in features {
            descriptor = CTFontDescriptorCreateCopyWithFeature(descriptor, NSNumber(value: feature.type), NSNumber(value: feature.selector))
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        fonts[key] = font
        return font
    }

    /// Loads descriptors for these faces at low priority, in order, ahead of what earlier calls asked for.
    public func prefetch(_ faces: [FontFace]) {
        let lanes: Int = state.withLock { state in
            var paths: [String] = []
            for face in faces where state.descriptors[face.path] == nil && state.pending.insert(face.path).inserted {
                paths.append(face.path)
            }
            state.queue += paths.reversed()
            let added = min(Self.prefetchLanes - state.lanes, state.queue.count)
            state.lanes += max(added, 0)
            return max(added, 0)
        }
        for _ in 0..<lanes {
            DispatchQueue.global(qos: .utility).async { [self] in readQueue() }
        }
    }

    private func readQueue() {
        while let path = state.withLock({ state -> String? in
            guard let path = state.queue.popLast() else {
                state.lanes -= 1
                return nil
            }
            return path
        }) {
            guard state.withLock({ $0.pending.contains(path) }) else { continue }
            let descriptors = FileDescriptors(FontFiles.descriptors(at: path))
            state.withLock { state in
                // Still pending means nothing read or invalidated the file in the meantime.
                if state.pending.remove(path) != nil { state.descriptors[path] = descriptors }
            }
        }
    }

    /// Keeps descriptors read elsewhere: the scanner reads every new file.
    func keep(_ descriptors: [CTFontDescriptor], for path: String) {
        state.withLock { state in
            state.descriptors[path] = FileDescriptors(descriptors)
            state.pending.remove(path)
        }
    }

    /// The file's faces, read now unless they were already; for coverage, which needs the same ones.
    func descriptors(at path: String) -> [CTFontDescriptor] {
        fileDescriptors(at: path).list
    }

    /// Whether the file's faces have been read (prefetched or on demand), so making a font from it won't read the file.
    public func hasDescriptors(for path: String) -> Bool {
        state.withLock { $0.descriptors[path] != nil }
    }

    /// Drops what's cached for files that changed or went away.
    public func invalidate(paths: Set<String>) {
        state.withLock { state in
            for path in paths {
                state.descriptors[path] = nil
                state.pending.remove(path)
                state.generations[path, default: 0] += 1
            }
        }
    }

    /// The face's descriptor, reading its file now if it wasn't prefetched; an installed font of
    /// the same name when the file can't be read.
    private func descriptor(for face: FontFace) -> CTFontDescriptor {
        FontFiles.descriptor(for: face, in: fileDescriptors(at: face.path).list) ?? FontFiles.installedDescriptor(named: face.postScriptName)
    }

    private func fileDescriptors(at path: String) -> FileDescriptors {
        if let cached = state.withLock({ $0.descriptors[path] }) { return cached }
        let descriptors = FileDescriptors(FontFiles.descriptors(at: path))
        state.withLock { state in
            state.descriptors[path] = descriptors
            state.pending.remove(path)
        }
        return descriptors
    }
}

/// The faces of one file. CTFontDescriptor is immutable and thread-safe, just not marked Sendable.
private struct FileDescriptors: @unchecked Sendable {
    let list: [CTFontDescriptor]

    init(_ list: [CTFontDescriptor]) {
        self.list = list
    }
}

/// NSCache is thread-safe but not marked Sendable.
private final class FontCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CTFont>()

    init(limit: Int) {
        cache.countLimit = limit
    }

    subscript(key: String) -> CTFont? {
        get { cache.object(forKey: key as NSString) }
        set {
            if let newValue {
                cache.setObject(newValue, forKey: key as NSString)
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }
    }
}
