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
        /// Variable faces' axes, by face and generation (see `axes(of:)`).
        var axes: [String: [AxisRange]] = [:]
    }

    /// The 'wght' axis.
    private static let weightAxisID = 0x7767_6874

    public init() {}

    /// `weight` sets the weight axis of variable faces (clamped to its range); ignored otherwise. `variations` sets
    /// any of their axes, by tag, the weight axis over `weight`; the slider that sets one keeps it in range. A variable
    /// face is otherwise drawn exactly where it sits on its axes, optical size included: CoreText would match that to
    /// the point size, and drops a setting of the default to do so. `cached` false makes the font without keeping it, for
    /// measuring many faces once: kept, they'd push the fonts on screen out of the cache.
    public func font(_ face: FontFace, size: CGFloat, weight: Double? = nil, variations: [String: Double] = [:],
                     features: [FeatureSetting] = [], cached: Bool = true) -> CTFont {
        let weight = face.weightAxis.flatMap { axis in weight.map { min(max($0, axis.minimum), axis.maximum) } }
        let variations = face.axes.isEmpty ? [] : variations.sorted { $0.key < $1.key }
        let features = features.sorted { ($0.type, $0.selector) < ($1.type, $1.selector) }
        let generation = state.withLock { $0.generations[face.path] ?? 0 }
        var key = "\(face.id)|\(generation)|\(Int((size * 2).rounded()))"
        if let weight { key += "|w\(Int(weight.rounded()))" }
        for (tag, value) in variations { key += "|\(tag)=\(value)" }
        for feature in features { key += "|\(feature.type):\(feature.selector)" }
        if let font = fonts[key] { return font }

        var descriptor = descriptor(for: face)
        if face.weightAxis != nil || !face.axes.isEmpty {
            descriptor = Self.descriptor(descriptor, weight: weight, variations: variations)
        }
        for feature in features {
            descriptor = CTFontDescriptorCreateCopyWithFeature(descriptor, NSNumber(value: feature.type), NSNumber(value: feature.selector))
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if cached { fonts[key] = font }
        return font
    }

    /// How many times the file changed while Cicero ran, for caches of what's measured from its faces.
    public func generation(of path: String) -> Int {
        state.withLock { $0.generations[path] ?? 0 }
    }

    /// A variable face where `weight` and `variations` put it, its other axes where it sits, at that optical size
    /// whatever the point size. CoreText reads a setting that leaves a descriptor where it already is (a weight set
    /// again, or a named style left alone) as the named style itself, which optical sizing "none" then draws at the
    /// default optical size, losing a style's own or a moved one. So every axis is set at once, after a step to the
    /// defaults, which only leaves a descriptor where it is when that's where it's drawn.
    private static func descriptor(_ descriptor: CTFontDescriptor, weight: Double?,
                                   variations: [(key: String, value: Double)]) -> CTFontDescriptor {
        var values = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber] ?? [:]
        if let weight { values[NSNumber(value: weightAxisID)] = NSNumber(value: weight) }
        for (tag, value) in variations { values[NSNumber(value: AxisTag.identifier(tag))] = NSNumber(value: value) }
        let axes = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAxesAttribute) as? [[String: Any]] ?? []
        let defaults = axes.reduce(into: [NSNumber: NSNumber]()) { defaults, axis in
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                  let value = axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber else { return }
            defaults[identifier] = value
        }
        let atDefaults = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: defaults] as CFDictionary)
        return CTFontDescriptorCreateCopyWithAttributes(
            atDefaults, [kCTFontOpticalSizeAttribute: "none", kCTFontVariationAttribute: values] as CFDictionary)
    }

    /// A variable face's axes and how far each goes, those the font hides too, in the font's order; none for a static face.
    /// Read once per face, as CoreText looks up the axes' names each time it's asked.
    public func axes(of face: FontFace) -> [AxisRange] {
        guard !face.axes.isEmpty else { return [] }
        let key = state.withLock { "\(face.id)|\($0.generations[face.path] ?? 0)" }
        if let axes = state.withLock({ $0.axes[key] }) { return axes }
        let entries = CTFontCopyVariationAxes(font(face, size: 12)) as? [[String: Any]] ?? []
        let axes = entries.compactMap { entry -> AxisRange? in
            guard let identifier = (entry[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value,
                  let minimum = entry[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                  let maximum = entry[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                  let defaultValue = entry[kCTFontVariationAxisDefaultValueKey as String] as? Double,
                  minimum < maximum
            else { return nil }
            let tag = AxisTag.string(identifier)
            let name = (entry[kCTFontVariationAxisNameKey as String] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return AxisRange(tag: tag, name: name.isEmpty || name == tag ? AxisTag.registeredNames[tag] ?? tag : name,
                             minimum: minimum, maximum: maximum, defaultValue: defaultValue,
                             isHidden: entry[kCTFontVariationAxisHiddenKey as String] as? Bool == true)
        }
        state.withLock { $0.axes[key] = axes }
        return axes
    }

    /// Where a font is drawn on each of its axes, by tag: the named instance's place and the values it was made with.
    /// Axes left out are at their defaults.
    public static func variation(of font: CTFont) -> [String: Double] {
        (CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]).reduce(into: [:]) {
            $0[AxisTag.string($1.key.uint32Value)] = $1.value.doubleValue
        }
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
            Self.readAhead(path)
            let descriptors = FileDescriptors(FontFiles.descriptors(at: path))
            state.withLock { state in
                // Still pending means nothing read or invalidated the file in the meantime.
                if state.pending.remove(path) != nil { state.descriptors[path] = descriptors }
            }
        }
    }

    /// Has the whole file read into memory in the background, not only the tables a descriptor needs: drawing text
    /// reads the glyphs, which in a file not read since the Mac started came off the disk as the text was drawn, and
    /// prefetching descriptors alone left scrolling as slow as before.
    private static func readAhead(_ path: String) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return }
        var advice = radvisory(ra_offset: 0, ra_count: Int32(min(info.st_size, Int64(Int32.max))))
        _ = fcntl(fd, F_RDADVISE, &advice)
    }

    /// Keeps descriptors read elsewhere: the scanner reads every new file. It reads one only when it's new or changed, so
    /// fonts made from the path before are out of date, like the stand-in for a file that was moved away and back: the
    /// grid still drew it as it went, from no file, which macOS answers with its "?" font for one that's on.
    func keep(_ descriptors: [CTFontDescriptor], for path: String) {
        state.withLock { state in
            state.descriptors[path] = FileDescriptors(descriptors)
            state.pending.remove(path)
            state.generations[path, default: 0] += 1
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

    /// Whether making a font from the file would read it now from a server, or download it, as a cloud service keeps it
    /// online only: either can take a while, or never finish, on a server that stopped answering. Files on the Mac's
    /// own disks are read at once (see `read`).
    public func wouldWait(for path: String) -> Bool {
        !hasDescriptors(for: path) && (!Reachability.isOnLocalDisk(path) || Reachability.isOnlineOnly(path))
    }

    /// Reads the file's faces off the caller's thread, and the whole file into memory, unless they were read already.
    public func read(_ path: String) async {
        guard !hasDescriptors(for: path) else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                Self.readAhead(path)
                _ = fileDescriptors(at: path)
                continuation.resume()
            }
        }
    }

    /// Reads these files' faces off the caller's thread, side by side (see `read(_:)`).
    public func read(_ paths: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths { group.addTask { await self.read(path) } }
        }
    }

    /// Drops what's cached for files that changed, went away or came back (see `Library.changedPaths`).
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

/// An axis's four-character tag, and the number CoreText knows it by: 'wght' is 0x77676874.
enum AxisTag {
    static func string(_ identifier: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: identifier >> $0) }, encoding: .isoLatin1) ?? ""
    }

    static func identifier(_ tag: String) -> UInt32 {
        tag.unicodeScalars.prefix(4).reduce(0) { $0 << 8 | ($1.value & 0xFF) }
    }

    /// The names of the common axes, for fonts that name one by its tag or not at all.
    static let registeredNames = ["wght": "Weight", "wdth": "Width", "opsz": "Optical Size", "ital": "Italic",
                                  "slnt": "Slant", "GRAD": "Grade"]
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
