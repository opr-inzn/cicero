import CiceroCore
import CoreText
import Foundation
import Synchronization

/// How wide the families' grid samples are, per point of the size, and so how wide the tiles need to be for all but the
/// library's widest fonts to be drawn at the size chosen (see `FontGrid`). One width for every list, so the tiles and the
/// rows don't change from one sidebar item, or search, to the next. Each sample is measured once, off the main thread and
/// several side by side, for its style, text and settings: its glyphs' outlines scale with the size, so dragging Size
/// measures nothing.
@Observable
final class SampleWidths {
    static let shared = SampleWidths()

    /// Per point of the preview size, as wide as the samples of all but the widest twentieth of the families All Fonts
    /// lists (of all of them, in a library of fewer than twenty): nil until they're measured. Kept for the next launch,
    /// where the library most often needs the same, so the tiles don't change once it's measured again.
    private(set) var listRatio: CGFloat?

    @ObservationIgnored private var measuredInputs: Int?
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
    }

    /// Measures the library's samples, unless `inputs` says they're those measured last, and returns `listRatio` for them:
    /// as it was, should it be cancelled or have no sample to measure.
    func measure(_ inputs: Int, samples: [Sample], scriptSamples: ScriptSamples) async -> CGFloat? {
        guard inputs != measuredInputs else { return listRatio }
        guard let ratio = await Self.listRatio(samples, scriptSamples: scriptSamples), !Task.isCancelled else { return listRatio }
        measuredInputs = inputs
        if listRatio != ratio { listRatio = ratio }
        UserDefaults.standard.set(Double(ratio), forKey: Self.savedKey)
        return ratio
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
    @concurrent
    nonisolated private static func listRatio(_ samples: [Sample], scriptSamples: ScriptSamples) async -> CGFloat? {
        let lanes = ProcessInfo.processInfo.activeProcessorCount
        let share = max(1, (samples.count + lanes - 1) / lanes)
        let measured = await withTaskGroup(of: [CGFloat]?.self) { group -> [CGFloat]? in
            for start in stride(from: 0, to: samples.count, by: share) {
                let part = samples[start..<min(start + share, samples.count)]
                group.addTask { widths(of: part, scriptSamples: scriptSamples) }
            }
            var all: [CGFloat] = []
            all.reserveCapacity(samples.count)
            for await part in group {
                guard let part else { return nil }
                all += part
            }
            return all
        }
        return measured.flatMap(widest)
    }

    /// Each sample's width per point of the size; nil once the task is cancelled.
    nonisolated private static func widths(of samples: ArraySlice<Sample>, scriptSamples: ScriptSamples) -> [CGFloat]? {
        var widths: [CGFloat] = []
        widths.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            if index % 32 == 0, Task.isCancelled { return nil }
            // Not a file on a server, or one a cloud service keeps online only, which reading would wait for: its tile
            // measures it once it has it, and it counts the next time the list is measured.
            guard !FontLoader.shared.wouldWait(for: sample.face.path) else { continue }
            let text = scriptSamples.text(sample.text, for: sample.face)
            if let known = ratios.withLock({ $0[sample.key(text: text)] }) {
                widths.append(known)
            } else {
                let font = FontLoader.shared.font(sample.face, size: 100, weight: sample.weight, variations: sample.variations,
                                                  features: sample.features, cached: false)
                widths.append(ratio(of: sample, text: text, in: font))
            }
        }
        return widths
    }

    /// All but the widest twentieth, or all of fewer than twenty.
    nonisolated static func widest(_ ratios: [CGFloat]) -> CGFloat? {
        guard !ratios.isEmpty else { return nil }
        let sorted = ratios.sorted()
        return sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
    }
}
