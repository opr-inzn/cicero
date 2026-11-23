import CoreText
import Foundation
import Synchronization

public struct FeatureSetting: Hashable, Codable, Sendable {
    public var type: Int
    public var selector: Int

    public init(type: Int, selector: Int) {
        self.type = type
        self.selector = selector
    }
}

public final class FontLoader: Sendable {
    public static let shared = FontLoader()

    private let state = Mutex(State())
    private let fonts = FontCache(limit: 2000)
    private static let prefetchLanes = 4
    static let keptFiles = 3000

    private struct State: Sendable {
        var descriptors: [String: FileDescriptors] = [:]
        var lastUse: [String: Int] = [:]
        var clock = 0
        var pending: Set<String> = []
        var queue: [String] = []
        var lanes = 0
        var generations: [String: Int] = [:]
        var drawn: Set<String> = []
        var changes: [String: Int] = [:]
        var axes: [String: [AxisRange]] = [:]

        mutating func use(_ path: String) {
            clock += 1
            lastUse[path] = clock
        }

        mutating func keep(_ fileDescriptors: FileDescriptors, for path: String) {
            descriptors[path] = fileDescriptors
            use(path)
            guard descriptors.count > FontLoader.keptFiles else { return }
            let drop = descriptors.count - FontLoader.keptFiles * 9 / 10
            for (old, _) in lastUse.sorted(by: { $0.value < $1.value }).prefix(drop) {
                descriptors[old] = nil
                lastUse[old] = nil
            }
        }

        mutating func forget(_ path: String) {
            descriptors[path] = nil
            lastUse[path] = nil
        }

        mutating func changed(_ path: String) {
            generations[path, default: 0] += 1
            if drawn.remove(path) != nil { changes[path, default: 0] += 1 }
        }
    }

    public init() {}

    public func font(_ face: FontFace, size: CGFloat, weight: Double? = nil, variations: [String: Double] = [:],
                     features: [FeatureSetting] = [], cached: Bool = true) -> CTFont {
        let weight = face.weightAxis.flatMap { axis in weight.map { min(max($0, axis.minimum), axis.maximum) } }
        let variations = face.axes.isEmpty ? [] : variations.sorted { $0.key < $1.key }
        let features = features.sorted { ($0.type, $0.selector) < ($1.type, $1.selector) }
        let (generation, changes) = state.withLock { state in
            state.drawn.insert(face.path)
            if state.descriptors[face.path] != nil { state.use(face.path) }
            return (state.generations[face.path] ?? 0, state.changes[face.path] ?? 0)
        }
        var key = "\(face.id)|\(generation)|\(Int((size * 2).rounded()))"
        if let weight { key += "|w\(Int(weight.rounded()))" }
        for (tag, value) in variations { key += "|\(tag)=\(value)" }
        for feature in features { key += "|\(feature.type):\(feature.selector)" }
        if let font = fonts[key] { return font }

        var descriptor = descriptor(for: face, in: cached ? fileDescriptors(at: face.path).list : descriptors(at: face.path))
        if face.weightAxis != nil || !face.axes.isEmpty {
            descriptor = Self.descriptor(descriptor, weight: weight, variations: variations)
        }
        for feature in features {
            descriptor = CTFontDescriptorCreateCopyWithFeature(descriptor, NSNumber(value: feature.type), NSNumber(value: feature.selector))
        }
        // A millionth of a point larger for each time the file changed: CoreText calls fonts of the same file, name and size equal whatever the file holds now, and text reuses an equal font it already has, so it kept drawing the old letters.
        let font = CTFontCreateWithFontDescriptor(descriptor, size + CGFloat(changes) / 1_000_000, nil)
        if cached { fonts[key] = font }
        return font
    }

    public func generation(of path: String) -> Int {
        state.withLock { $0.generations[path] ?? 0 }
    }

    private static func descriptor(_ descriptor: CTFontDescriptor, weight: Double?,
                                   variations: [(key: String, value: Double)]) -> CTFontDescriptor {
        var values = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber] ?? [:]
        if let weight { values[NSNumber(value: AxisTag.weight)] = NSNumber(value: weight) }
        for (tag, value) in variations { values[NSNumber(value: AxisTag.identifier(tag))] = NSNumber(value: value) }
        let axes = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAxesAttribute) as? [[String: Any]] ?? []
        let defaults = axes.reduce(into: [NSNumber: NSNumber]()) { defaults, axis in
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                  let value = axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber else { return }
            defaults[identifier] = value
        }
        // Optical size "none", or CoreText matches it to the point size and drops a setting of the default; and every axis at once, after a step to the defaults, as CoreText reads a setting that leaves a descriptor where it is, like a weight set again, as the named style itself, which "none" then draws at the default optical size.
        let atDefaults = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: defaults] as CFDictionary)
        return CTFontDescriptorCreateCopyWithAttributes(
            atDefaults, [kCTFontOpticalSizeAttribute: "none", kCTFontVariationAttribute: values] as CFDictionary)
    }

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
            return AxisRange(tag: tag, name: AxisTag.name(of: tag, given: entry[kCTFontVariationAxisNameKey as String] as? String ?? ""),
                             minimum: minimum, maximum: maximum, defaultValue: defaultValue,
                             isHidden: entry[kCTFontVariationAxisHiddenKey as String] as? Bool == true)
        }
        state.withLock { $0.axes[key] = axes }
        return axes
    }

    public static func variation(of font: CTFont) -> [String: Double] {
        (CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]).reduce(into: [:]) {
            $0[AxisTag.string($1.key.uint32Value)] = $1.value.doubleValue
        }
    }

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
            guard let generation = state.withLock({ $0.pending.contains(path) ? $0.generations[path] ?? 0 : nil }) else { continue }
            Self.readAhead(path)
            let descriptors = FileDescriptors(FontFiles.descriptors(at: path))
            state.withLock { state in
                if state.generations[path] ?? 0 == generation, state.pending.remove(path) != nil { state.keep(descriptors, for: path) }
            }
        }
    }

    private static func readAhead(_ path: String) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return }
        let count = min(info.st_size, Self.mostReadAhead)
        var advice = radvisory(ra_offset: 0, ra_count: Int32(count))
        _ = fcntl(fd, F_RDADVISE, &advice)
        #if CICERO_MEASURE
        Measurements.record("readAhead.mb", ms: Double(count) / 1_048_576, detail: path)
        #endif
    }

    private static let mostReadAhead: Int64 = 32 << 20

    func descriptors(at path: String) -> [CTFontDescriptor] {
        state.withLock { $0.descriptors[path] }?.list ?? FontFiles.descriptors(at: path)
    }

    public func hasDescriptors(for path: String) -> Bool {
        state.withLock { $0.descriptors[path] != nil }
    }

    public func wouldWait(for path: String) -> Bool {
        !hasDescriptors(for: path) && (!Reachability.isOnLocalDisk(path) || Reachability.isOnlineOnly(path))
    }

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

    public func read(_ paths: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths { group.addTask { await self.read(path) } }
        }
    }

    public func invalidate(paths: Set<String>) {
        state.withLock { state in
            for path in paths {
                state.forget(path)
                state.pending.remove(path)
                state.changed(path)
            }
        }
    }

    private func descriptor(for face: FontFace, in descriptors: [CTFontDescriptor]) -> CTFontDescriptor {
        FontFiles.descriptor(for: face, in: descriptors) ?? FontFiles.installedDescriptor(named: face.postScriptName)
    }

    private func fileDescriptors(at path: String) -> FileDescriptors {
        if let cached = state.withLock({ $0.descriptors[path] }) { return cached }
        #if CICERO_MEASURE
        let measuring = Thread.isMainThread ? Measurements.begin("mainThreadFileRead") : nil
        defer { measuring?.end(detail: path) }
        #endif
        let generation = state.withLock { $0.generations[path] ?? 0 }
        let descriptors = FileDescriptors(FontFiles.descriptors(at: path))
        state.withLock { state in
            guard state.generations[path] ?? 0 == generation else { return }
            state.keep(descriptors, for: path)
            state.pending.remove(path)
        }
        return descriptors
    }
}

enum AxisTag {
    static let weight: UInt32 = 0x7767_6874

    static func string(_ identifier: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: identifier >> $0) }, encoding: .isoLatin1) ?? ""
    }

    static func identifier(_ tag: String) -> UInt32 {
        tag.unicodeScalars.prefix(4).reduce(0) { $0 << 8 | ($1.value & 0xFF) }
    }

    static let registeredNames = ["wght": "Weight", "wdth": "Width", "opsz": "Optical Size", "ital": "Italic",
                                  "slnt": "Slant", "GRAD": "Grade"]

    static func name(of tag: String, given: String) -> String {
        // macOS names the registered axes in the Mac's language, like Breite in German, and a library read before the language changed would keep that name.
        if tag.first?.isLowercase == true, let name = registeredNames[tag] { return name }
        let given = given.trimmingCharacters(in: .whitespaces)
        return given.isEmpty || given == tag ? registeredNames[tag] ?? tag : given
    }
}

private struct FileDescriptors: @unchecked Sendable {
    let list: [CTFontDescriptor]

    init(_ list: [CTFontDescriptor]) {
        self.list = list
    }
}

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
