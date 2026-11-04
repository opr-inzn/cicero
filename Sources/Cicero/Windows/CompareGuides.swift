#if canImport(CiceroCore)
import CiceroCore
#endif
import AppKit
import SwiftUI

/// The lines Compare's Overlay draws under its samples, the baseline and each font's cap height, x-height, ascender and
/// descender
/// (`GuideHeights`), with their names in a column to the left and their heights in the font's units to the right.
/// A font's lines of different kinds at the same height in its units are one line, with one label naming them all,
/// like "Ascender = Cap Height". Lines of a kind closer together than a label is tall share one: one name, the fonts'
/// values side by side in their order and tints. Labels that would overlap make way for each other, as little as they
/// can.
struct CompareGuides {
    enum Kind: CaseIterable {
        case ascender, capHeight, xHeight, baseline, descender

        var name: String {
            switch self {
            case .ascender: "Ascender"
            case .capHeight: "Cap Height"
            case .xHeight: "x-Height"
            case .baseline: "Baseline"
            case .descender: "Descender"
            }
        }

        /// Whether its line goes over the glyphs it measures, rather than under them as the baseline's does.
        var isAbove: Bool { self == .ascender || self == .capHeight || self == .xHeight }
    }

    struct Line {
        /// Every kind it stands for, in `Kind`'s order: more than one where a font's heights are the same in its units.
        let kinds: [Kind]
        var kind: Kind { kinds[0] }
        /// Its kinds' names, like "Ascender = Cap Height".
        var name: String { kinds.map(\.name).joined(separator: " = ") }
        /// Above the baseline; negative for a descender.
        let height: CGFloat
        /// The height in the font's units.
        let units: Int
        /// The font's place in the samples; nil for the baseline, which every font shares.
        let font: Int?
        let tint: Color?
    }

    struct Label {
        let kinds: [Kind]
        var name: String { kinds.map(\.name).joined(separator: " = ") }
        /// In the fonts' order.
        let lines: [Line]
        /// Its middle, in points below the baseline (negative above it).
        let center: CGFloat
    }

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// How much room a label takes from the next one above or below it.
    static let labelHeight: CGFloat = 15
    /// Between the labels and the ends of the lines.
    static let gap: CGFloat = 8

    let lines: [Line]
    let labels: [Label]
    /// The widest name and the widest row of values, measured.
    let nameWidth: CGFloat
    let valueWidth: CGFloat
    /// How far the labels reach above and below the baseline.
    let labelsAbove: CGFloat
    let labelsBelow: CGFloat

    init(_ fonts: [(guides: GuideHeights, tint: Color)]) {
        var lines = [Line(kinds: [.baseline], height: 0, units: 0, font: nil, tint: nil)]
        for (index, (guides, tint)) in fonts.enumerated() {
            let heights: [(Kind, CGFloat?)] = [(.ascender, guides.ascender), (.capHeight, guides.capHeight), (.xHeight, guides.xHeight),
                                               (.descender, guides.descender.map { -$0 })]
            var own: [Line] = []
            for case let (kind, height?) in heights {
                let units = height < 0 ? -guides.units(-height) : guides.units(height)
                // The same in the font's units as one already there: one line for both, as far out as the further,
                // so it stays clear of both their glyphs. Each with its own line and label, a font whose ascenders
                // were as tall as its capitals showed the same value twice.
                if let same = own.firstIndex(where: { $0.units == units }) {
                    let line = own[same]
                    own[same] = Line(kinds: line.kinds + [kind], height: height < 0 ? min(line.height, height) : max(line.height, height),
                                     units: units, font: index, tint: tint)
                } else {
                    own.append(Line(kinds: [kind], height: height, units: units, font: index, tint: tint))
                }
            }
            lines += own
        }
        self.lines = lines

        // Lines of the same kinds each less than a label's height from the next share a label.
        var groups: [(kinds: [Kind], lines: [Line])] = []
        var kindsInOrder: [[Kind]] = []
        for line in lines where !kindsInOrder.contains(line.kinds) { kindsInOrder.append(line.kinds) }
        for kinds in kindsInOrder {
            var group: [Line] = []
            for line in lines.filter({ $0.kinds == kinds }).sorted(by: { $0.height > $1.height }) {
                if let last = group.last, last.height - line.height >= Self.labelHeight {
                    groups.append((kinds, group))
                    group = []
                }
                group.append(line)
            }
            if !group.isEmpty { groups.append((kinds, group)) }
        }

        // Each label where its lines are on average; labels that would overlap pushed apart into a block, at the
        // average of where its labels would be, so each moves as little as it can.
        let height = Self.labelHeight
        let wanted = groups.map { group in -group.lines.map(\.height).reduce(0, +) / CGFloat(group.lines.count) }
        let order = wanted.indices.sorted { wanted[$0] < wanted[$1] }
        var blocks: [(members: [Int], top: CGFloat)] = []
        for index in order {
            blocks.append(([index], wanted[index] - height / 2))
            while blocks.count > 1 {
                let lower = blocks[blocks.count - 1], upper = blocks[blocks.count - 2]
                guard upper.top + CGFloat(upper.members.count) * height > lower.top else { break }
                let members = upper.members + lower.members
                let tops = members.enumerated().map { place, member in wanted[member] - height / 2 - CGFloat(place) * height }
                blocks.removeLast(2)
                blocks.append((members, tops.reduce(0, +) / CGFloat(tops.count)))
            }
        }
        var centers = [CGFloat](repeating: 0, count: groups.count)
        for block in blocks {
            for (place, member) in block.members.enumerated() { centers[member] = block.top + (CGFloat(place) + 0.5) * height }
        }
        labels = order.map { index in
            Label(kinds: groups[index].kinds, lines: groups[index].lines.sorted { ($0.font ?? -1) < ($1.font ?? -1) }, center: centers[index])
        }
        nameWidth = labels.map { Self.width(Self.text(name: $0, environment: nil)) }.max() ?? 0
        valueWidth = labels.map { Self.width(Self.text(values: $0, environment: nil)) }.max() ?? 0
        labelsAbove = max(0, -(centers.min() ?? 0) + height / 2)
        labelsBelow = max(0, (centers.max() ?? 0) + height / 2)
    }

    /// The lines from `x` across `width`, under samples whose baseline is `baseline` points down, each one device pixel
    /// thick on the pixel row just outside the glyphs it measures, as glyphs sit on a baseline: under the baseline and
    /// the descenders, over the cap height, the x-height and the ascenders (across two rows, or through the glyphs' last row, a line
    /// looked blurred or a pixel off). The fonts' lines in their tints at 80 %, mixed as the samples are, the baseline
    /// grey over them. The names end `gap` left of `x`, the values start `gap` right of the lines.
    func draw(in cg: CGContext, baselineAt baseline: CGFloat, from x: CGFloat, width: CGFloat, labels showsLabels: Bool = true,
              scale: CGFloat, environment: EnvironmentValues) {
        let scale = max(scale, 1)
        func line(_ line: Line, color: CGColor) {
            let row = ((baseline - line.height) * scale).rounded() - (line.kind.isAbove ? 1 : 0)
            cg.setFillColor(color)
            cg.fill(CGRect(x: x, y: row / scale, width: width, height: 1 / scale))
        }
        cg.saveGState()
        cg.setBlendMode(environment.colorScheme == .dark ? .screen : .multiply)
        for each in lines where each.tint != nil {
            line(each, color: each.tint!.opacity(0.8).resolve(in: environment).cgColor)
        }
        for each in lines where each.tint == nil {
            line(each, color: Color.secondary.resolve(in: environment).cgColor)
        }
        cg.setBlendMode(.normal)
        for label in labels where showsLabels {
            // Its capitals and figures centred on the label's middle.
            let textBaseline = baseline + label.center + Self.font.capHeight / 2
            let name = Self.text(name: label, environment: environment)
            Self.draw(name, in: cg, at: CGPoint(x: x - Self.gap - Self.width(name), y: textBaseline))
            Self.draw(Self.text(values: label, environment: environment), in: cg, at: CGPoint(x: x + width + Self.gap, y: textBaseline))
        }
        cg.restoreGState()
    }

    /// The name in the font's tint when the label is one font's, else grey.
    private static func text(name label: Label, environment: EnvironmentValues?) -> CTLine {
        let tint = label.lines.count == 1 ? label.lines[0].tint : nil
        return line([(label.name, tint)], environment: environment)
    }

    /// Each font's value in its tint, side by side; the baseline's 0 in grey. Below the baseline with a minus sign.
    private static func text(values label: Label, environment: EnvironmentValues?) -> CTLine {
        let runs = label.lines.enumerated().map { place, line in
            ((place > 0 ? "  " : "") + (line.units < 0 ? "\u{2212}\(-line.units)" : "\(line.units)"), line.tint)
        }
        return line(runs, environment: environment)
    }

    /// Without an environment, for measuring only.
    private static func line(_ runs: [(String, Color?)], environment: EnvironmentValues?) -> CTLine {
        let text = NSMutableAttributedString()
        for (string, tint) in runs {
            var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            if let environment {
                attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = (tint ?? Color.secondary).resolve(in: environment).cgColor
            }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        return CTLineCreateWithAttributedString(text)
    }

    private static func width(_ line: CTLine) -> CGFloat { CTLineGetTypographicBounds(line, nil, nil, nil).rounded(.up) }

    /// Into a flipped context, its baseline's start at `origin`.
    private static func draw(_ line: CTLine, in cg: CGContext, at origin: CGPoint) {
        cg.saveGState()
        cg.textMatrix = .identity
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: 1, y: -1)
        cg.textPosition = .zero
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}
