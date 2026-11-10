import CiceroCore
import CoreText
import Foundation
import Synchronization

@Observable
final class SampleWidths {
    static let shared = SampleWidths()

    private(set) var listRatio: CGFloat?

    @ObservationIgnored private var measuredInputs: Int?
    @ObservationIgnored private var saved: [String: CGFloat]?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var clears = 0
    #if CICERO_MEASURE
    @ObservationIgnored private(set) var measuredLog: [(new: Int, all: Int)] = []
    static var savedURL: URL { Saved.url }
    #endif
    private static let savedKey = "grid.sampleWidthRatio"
    nonisolated private static let ratios = Mutex(Ratios())

    nonisolated private struct Ratios {
        static let texts = 4
        var byText: [String: [String: CGFloat]] = [:]
        var recent: [String] = []

        func value(_ key: String, text: String) -> CGFloat? { byText[text]?[key] }

        mutating func add(_ ratios: [String: CGFloat], text: String) {
            recent.removeAll { $0 == text }
            recent.append(text)
            byText[text, default: [:]].merge(ratios) { first, _ in first }
            while recent.count > Self.texts { byText[recent.removeFirst()] = nil }
        }
    }

    private init() {
        listRatio = (UserDefaults.standard.object(forKey: Self.savedKey) as? Double).map { CGFloat($0) }
    }

    nonisolated struct Sample: Sendable {
        var face: FontFace
        var text: String
        var weight: Double
        var variations: [String: Double]
        var features: [FeatureSetting]

        func key(text: String) -> String {
            var key = "\(face.id)|\(FontLoader.shared.generation(of: face.path))|"
            if face.weightAxis != nil { key += "w\(weight)" }
            for (tag, value) in variations.sorted(by: { $0.key < $1.key }) { key += "|\(tag)=\(value)" }
            for feature in features.sorted(by: { ($0.type, $0.selector) < ($1.type, $1.selector) }) { key += "|\(feature.type):\(feature.selector)" }
            return key + "|" + text
        }

        func savedKey(_ file: stat) -> String {
            var key = "\(face.id.path)|\(face.id.index)|\(file.st_mtimespec.tv_sec).\(file.st_mtimespec.tv_nsec)|\(file.st_size)|"
            if face.weightAxis != nil { key += "w\(weight)" }
            for (tag, value) in variations.sorted(by: { $0.key < $1.key }) { key += "|\(tag)=\(value)" }
            for feature in features.sorted(by: { ($0.type, $0.selector) < ($1.type, $1.selector) }) { key += "|\(feature.type):\(feature.selector)" }
            return key + "|" + text
        }
    }

    func hasMeasured(_ inputs: Int) -> Bool { inputs == measuredInputs }

    func measure(_ inputs: Int, samples: [Sample], scriptSamples: ScriptSamples) async -> CGFloat? {
        guard inputs != measuredInputs else { return listRatio }
        let clearsBefore = clears
        if saved == nil {
            let read = await Saved.read() ?? [:]
            if clears == clearsBefore { saved = read }
        }
        let known = saved ?? [:]
        guard let measured = await Self.listRatio(samples, known: known, scriptSamples: scriptSamples), !Task.isCancelled,
              clears == clearsBefore else { return listRatio }
        #if CICERO_MEASURE
        Measurements.record("sampleWidths", ms: 0, detail: "\(measured.new) measured, \(measured.used.count) saved")
        measuredLog.append((measured.new, measured.used.count))
        #endif
        if measured.new > 0 || measured.used.count != known.count {
            saved = measured.used
            save(measured.used)
        }
        guard let ratio = measured.ratio else { return listRatio }
        measuredInputs = inputs
        if listRatio != ratio { listRatio = ratio }
        UserDefaults.standard.set(Double(ratio), forKey: Self.savedKey)
        return ratio
    }

    func clearSaved() {
        clears += 1
        saved = [:]
        measuredInputs = nil
        save([:])
    }

    private func save(_ ratios: [String: CGFloat]) {
        saving?.cancel()
        saving = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            Saved.write(ratios)
        }
    }

    nonisolated private enum Saved {
        static let url = Locations.standard.caches.appendingPathComponent("sample-widths.cache", isDirectory: false)
        static var version: String {
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            // For this build of Cicero on this version of macOS only: a new one may put other text in a font's own script, or CoreText measure it differently.
            return "1|\(build)|\(ProcessInfo.processInfo.operatingSystemVersionString)"
        }

        @concurrent
        static func read() async -> [String: CGFloat]? {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  plist["version"] as? String == version, let ratios = plist["ratios"] as? [String: Double]
            else { return nil }
            return ratios.mapValues { CGFloat($0) }
        }

        static func write(_ ratios: [String: CGFloat]) {
            let plist: [String: Any] = ["version": version, "ratios": ratios.mapValues { Double($0) }]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated static func ratio(of sample: Sample, text: String, in font: CTFont) -> CGFloat {
        let key = sample.key(text: text)
        if let ratio = ratios.withLock({ $0.value(key, text: sample.text) }) { return ratio }
        let ratio = width(of: text, in: font) / CTFontGetSize(font)
        ratios.withLock { $0.add([key: ratio], text: sample.text) }
        return ratio
    }

    nonisolated static func width(of text: String, in font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard !ink.isEmpty else { return advance }
        return max(advance, ink.maxX) - min(0, ink.minX)
    }

    nonisolated struct Measured: Sendable {
        var ratio: CGFloat?
        var used: [String: CGFloat]
        var new: Int
    }

    @concurrent
    nonisolated private static func listRatio(_ samples: [Sample], known: [String: CGFloat], scriptSamples: ScriptSamples) async -> Measured? {
        let lanes = ProcessInfo.processInfo.activeProcessorCount
        let share = max(1, (samples.count + lanes - 1) / lanes)
        let measured = await withTaskGroup(of: Lane?.self) { group -> Measured? in
            for start in stride(from: 0, to: samples.count, by: share) {
                let part = samples[start..<min(start + share, samples.count)]
                group.addTask { widths(of: part, known: known, scriptSamples: scriptSamples) }
            }
            var all: [CGFloat] = []
            all.reserveCapacity(samples.count)
            var used: [String: CGFloat] = [:]
            used.reserveCapacity(samples.count)
            var new = 0
            for await lane in group {
                guard let lane else { return nil }
                all += lane.widths
                used.merge(lane.used) { first, _ in first }
                new += lane.new
            }
            return Measured(ratio: widest(all), used: used, new: new)
        }
        return measured
    }

    nonisolated private struct Lane: Sendable {
        var widths: [CGFloat] = []
        var used: [String: CGFloat] = [:]
        var new = 0
    }

    nonisolated private static func widths(of samples: ArraySlice<Sample>, known: [String: CGFloat], scriptSamples: ScriptSamples) -> Lane? {
        var lane = Lane()
        lane.widths.reserveCapacity(samples.count)
        var measured: [String: [String: CGFloat]] = [:]
        defer {
            if !measured.isEmpty { ratios.withLock { ratios in for (text, found) in measured { ratios.add(found, text: text) } } }
        }
        for (index, sample) in samples.enumerated() {
            if index % 32 == 0, Task.isCancelled { return nil }
            let path = sample.face.path
            // Not a file on a server, which asking anything could hold up, unless it was read already.
            var file = stat()
            let local = Reachability.isOnLocalDisk(path)
            if local {
                guard lstat(path, &file) == 0 else { continue }
            } else if !FontLoader.shared.hasDescriptors(for: path) {
                continue
            }
            let savedKey = local ? sample.savedKey(file) : nil
            if let savedKey, let ratio = known[savedKey] {
                lane.widths.append(ratio)
                lane.used[savedKey] = ratio
                continue
            }
            // Nor one a cloud service keeps online only, which reading would download.
            if local, file.st_flags & UInt32(SF_DATALESS) != 0, !FontLoader.shared.hasDescriptors(for: path) { continue }
            let text = scriptSamples.text(sample.text, for: sample.face, cached: false)
            let key = sample.key(text: text)
            let ratio: CGFloat
            if let known = measured[sample.text]?[key] ?? ratios.withLock({ $0.value(key, text: sample.text) }) {
                ratio = known
            } else {
                let font = FontLoader.shared.font(sample.face, size: 100, weight: sample.weight, variations: sample.variations,
                                                  features: sample.features, cached: false)
                ratio = width(of: text, in: font) / CTFontGetSize(font)
                measured[sample.text, default: [:]][key] = ratio
            }
            lane.widths.append(ratio)
            if let savedKey { lane.used[savedKey] = ratio }
            lane.new += 1
        }
        return lane
    }

    nonisolated static func widest(_ ratios: [CGFloat]) -> CGFloat? {
        guard !ratios.isEmpty else { return nil }
        let sorted = ratios.sorted()
        return sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
    }
}
