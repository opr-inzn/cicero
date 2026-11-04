import CiceroCore
import CoreText
import Foundation
import Synchronization

/// How wide the families' grid samples are, per point of the size, and so how wide the tiles need to be for all but the
/// library's widest fonts to be drawn at the size chosen (see `FontGrid`). One width for every list, so the tiles and the
/// rows don't change from one sidebar item, or search, to the next. Each sample is measured once, off the main thread and
/// several side by side, for its style, text and settings: its glyphs' outlines scale with the size, so dragging Size
/// measures nothing. What the last measurement found is saved for the next launch (`Saved`), which then opens no file
/// to measure: at 20,000 families that took 8 s of CPU on every core during each launch.
@Observable
final class SampleWidths {
    static let shared = SampleWidths()

    /// Per point of the preview size, as wide as the samples of all but the widest twentieth of the families All Fonts
    /// lists (of all of them, in a library of fewer than twenty): nil until they're measured. Kept for the next launch,
    /// where the library most often needs the same, so the tiles don't change once it's measured again.
    private(set) var listRatio: CGFloat?

    @ObservationIgnored private var measuredInputs: Int?
    /// Each sample's width per point of the size, by `Sample.savedKey`: as the last measurement found them, saved for the
    /// next launch. nil until read.
    @ObservationIgnored private var saved: [String: CGFloat]?
    @ObservationIgnored private var saving: Task<Void, Never>?
    #if CICERO_MEASURE
    /// Each finished measurement: how many samples it measured, and how many it knew or measured in all.
    @ObservationIgnored private(set) var measuredLog: [(new: Int, all: Int)] = []
    static var savedURL: URL { Saved.url }
    #endif
    private static let savedKey = "grid.sampleWidthRatio"
    /// What each sample measured, per point of the size, by `Sample.key`.
    nonisolated private static let ratios = Mutex<[String: CGFloat]>([:])

    private init() {
        listRatio = (UserDefaults.standard.object(forKey: Self.savedKey) as? Double).map { CGFloat($0) }
    }

    /// A family's sample as its tile draws it.
    nonisolated struct Sample: Sendable {
        var face: FontFace
        /// Before `ScriptSamples` gives a font without its letters text in its own script.
        var text: String
        var weight: Double
        var variations: [String: Double]
        var features: [FeatureSetting]

        /// The weight only for a face with a weight axis, the only ones it changes.
        func key(text: String) -> String {
            var key = "\(face.id)|\(FontLoader.shared.generation(of: face.path))|"
            if face.weightAxis != nil { key += "w\(weight)" }
            for (tag, value) in variations.sorted(by: { $0.key < $1.key }) { key += "|\(tag)=\(value)" }
            for feature in features.sorted(by: { ($0.type, $0.selector) < ($1.type, $1.selector) }) { key += "|\(feature.type):\(feature.selector)" }
            return key + "|" + text
        }

        /// The key its width is saved by for the next launch: the file as it is on disk now (path, face, modification
        /// time and size, so a file saved again or replaced is measured again), the settings, and the text asked for,
        /// before `ScriptSamples` puts it in the font's own script, so a saved width needs no font opened.
        func savedKey(_ file: stat) -> String {
            var key = "\(face.id.path)|\(face.id.index)|\(file.st_mtimespec.tv_sec).\(file.st_mtimespec.tv_nsec)|\(file.st_size)|"
            if face.weightAxis != nil { key += "w\(weight)" }
            for (tag, value) in variations.sorted(by: { $0.key < $1.key }) { key += "|\(tag)=\(value)" }
            for feature in features.sorted(by: { ($0.type, $0.selector) < ($1.type, $1.selector) }) { key += "|\(feature.type):\(feature.selector)" }
            return key + "|" + text
        }
    }

    /// Measures the library's samples, unless `inputs` says they're those measured last, and returns `listRatio` for them:
    /// as it was, should it be cancelled or have no sample to measure.
    /// Whether `inputs` are those measured last, so there's nothing to make samples for.
    func hasMeasured(_ inputs: Int) -> Bool { inputs == measuredInputs }

    func measure(_ inputs: Int, samples: [Sample], scriptSamples: ScriptSamples) async -> CGFloat? {
        guard inputs != measuredInputs else { return listRatio }
        if saved == nil { saved = await Saved.read() ?? [:] }
        let known = saved ?? [:]
        guard let measured = await Self.listRatio(samples, known: known, scriptSamples: scriptSamples), !Task.isCancelled else { return listRatio }
        #if CICERO_MEASURE
        Measurements.record("sampleWidths", ms: 0, detail: "\(measured.new) measured, \(measured.used.count) saved")
        measuredLog.append((measured.new, measured.used.count))
        #endif
        // Only this measurement's samples are kept, so the file doesn't grow with every preview text tried.
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

    /// Forgets the saved widths, as Rebuild Library forgets what was read from the files.
    func clearSaved() {
        saved = [:]
        measuredInputs = nil
        save([:])
    }

    /// Writes the widths off the main thread, once they've stayed the same for 2 s, as while typing a preview text.
    private func save(_ ratios: [String: CGFloat]) {
        saving?.cancel()
        saving = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            Saved.write(ratios)
        }
    }

    /// The widths as saved in Cicero's caches folder, for this build of Cicero on this version of macOS only: a new
    /// one may put other text in a font's own script, or CoreText measure it differently.
    nonisolated private enum Saved {
        static let url = Locations.standard.caches.appendingPathComponent("sample-widths.cache", isDirectory: false)
        static var version: String {
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
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

    /// The sample's width per point of `font`'s size, `text` being what the tile draws in it: measured before, or now.
    nonisolated static func ratio(of sample: Sample, text: String, in font: CTFont) -> CGFloat {
        let key = sample.key(text: text)
        if let ratio = ratios.withLock({ $0[key] }) { return ratio }
        let ratio = width(of: text, in: font) / CTFontGetSize(font)
        ratios.withLock { $0[key] = ratio }
        return ratio
    }

    /// From the left edge of whichever reaches further left, the first glyph's outline or its line, to the right edge of
    /// whichever reaches further right: all a tile needs room for.
    nonisolated static func width(of text: String, in font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard !ink.isEmpty else { return advance }
        return max(advance, ink.maxX) - min(0, ink.minX)
    }

    /// A share of the samples on each core, so a new preview text is measured in a moment: the grid waits for it to show
    /// the text (see `FontGrid.shown`).
    /// What measuring the samples found: the list's ratio (nil without a sample to measure), each sample's width by
    /// `Sample.savedKey`, and how many weren't known from the saved ones.
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

    /// One share of the samples, measured by one task: their widths per point of the size, by `Sample.savedKey`, and how
    /// many were measured rather than known.
    nonisolated private struct Lane: Sendable {
        var widths: [CGFloat] = []
        var used: [String: CGFloat] = [:]
        var new = 0
    }

    /// Each sample's width per point of the size, from the saved ones or measured; nil once the task is cancelled. What a
    /// lane measures goes into `ratios` once at its end: ten lanes taking the lock for every sample kept waiting on it.
    nonisolated private static func widths(of samples: ArraySlice<Sample>, known: [String: CGFloat], scriptSamples: ScriptSamples) -> Lane? {
        var lane = Lane()
        lane.widths.reserveCapacity(samples.count)
        var measured: [String: CGFloat] = [:]
        defer { if !measured.isEmpty { ratios.withLock { $0.merge(measured) { first, _ in first } } } }
        for (index, sample) in samples.enumerated() {
            if index % 32 == 0, Task.isCancelled { return nil }
            let path = sample.face.path
            // Not a file on a server, which asking anything could hold up, unless it was read already; it isn't saved.
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
            // Nor one a cloud service keeps online only, which reading would download: its tile measures it once it has
            // it, and it counts the next time the list is measured.
            if local, file.st_flags & UInt32(SF_DATALESS) != 0, !FontLoader.shared.hasDescriptors(for: path) { continue }
            let text = scriptSamples.text(sample.text, for: sample.face, cached: false)
            let key = sample.key(text: text)
            let ratio: CGFloat
            if let known = measured[key] ?? ratios.withLock({ $0[key] }) {
                ratio = known
            } else {
                let font = FontLoader.shared.font(sample.face, size: 100, weight: sample.weight, variations: sample.variations,
                                                  features: sample.features, cached: false)
                ratio = width(of: text, in: font) / CTFontGetSize(font)
                measured[key] = ratio
            }
            lane.widths.append(ratio)
            if let savedKey { lane.used[savedKey] = ratio }
            lane.new += 1
        }
        return lane
    }

    /// All but the widest twentieth, or all of fewer than twenty.
    nonisolated static func widest(_ ratios: [CGFloat]) -> CGFloat? {
        guard !ratios.isEmpty else { return nil }
        let sorted = ratios.sorted()
        return sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
    }
}
