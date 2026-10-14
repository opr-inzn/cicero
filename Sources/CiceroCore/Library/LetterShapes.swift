import CoreText
import Foundation

/// Serif or sans serif from the shapes of a face's capital I and lowercase l, for faces whose files don't say.
/// Each must be one straight stem. With feet reaching out to both sides at the baseline (the I's at the top too)
/// the face is serif; with plain ends, sans serif. A font with capitals or lowercase only goes by the one it has.
/// Anything else says nothing: Verdana's I has serifs and its l none, and a script's strokes curve. A wrong
/// classification is worse than none. A face whose i, m and W are as wide is monospaced, whatever its I and l look
/// like: monospaced styles give both serifs to tell them apart.
enum LetterShapes {
    /// How far past the stem, in stem widths, a serif reaches at least, and plain ends at most.
    private static let serif: CGFloat = 0.3
    private static let plain: CGFloat = 0.12

    static func classification(of font: CTFont) -> Classification? {
        if isMonospaced(font) { return .monospaced }
        // How far italics lean: along for each unit up.
        let slant = tan(-CTFontGetSlantAngle(font) * .pi / 180)
        switch (Reading(font, "I", slant: slant), Reading(font, "l", slant: slant)) {
        case (.measured(let i), .measured(let l)):
            if i.foot > serif && i.head > serif && l.foot > serif { return .serif }
            // A sans serif l may end in a tail to one side, but not in a foot to both.
            if i.reach < plain && l.foot < plain { return .sansSerif }
        case (.measured(let i), .missing):
            if i.foot > serif && i.head > serif { return .serif }
            if i.reach < plain { return .sansSerif }
        case (.missing, .measured(let l)):
            if l.foot > serif { return .serif }
            if l.reach < plain { return .sansSerif }
        default:
            break
        }
        return nil
    }

    private static func glyph(_ font: CTFont, _ character: Character) -> CGGlyph? {
        var characters = Array(String(character).utf16)
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1) && glyph != 0 ? glyph : nil
    }

    /// Whether a drawn i, m and W are exactly as wide (I, M and W, without lowercase), as in a monospaced style
    /// the font doesn't flag as one. Fonts in three widths have i and m alike, and unfinished ones letters that
    /// aren't drawn yet, all as wide.
    private static func isMonospaced(_ font: CTFont) -> Bool {
        func drawn(_ characters: [Character]) -> [CGGlyph]? {
            let glyphs = characters.compactMap { character -> CGGlyph? in
                guard let glyph = glyph(font, character), let path = CTFontCreatePathForGlyph(font, glyph, nil),
                      !path.boundingBoxOfPath.isEmpty else { return nil }
                return glyph
            }
            return glyphs.count == characters.count ? glyphs : nil
        }
        guard var glyphs = drawn(["i", "m", "W"]) ?? drawn(["I", "M", "W"]) else { return false }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
        let widths = advances.map(\.width)
        return widths[0] > 0 && widths.max()! - widths.min()! < widths[0] * 0.001
    }

    private enum Reading {
        case measured(Letter)
        /// The font hasn't got the letter.
        case missing
        /// It isn't one straight stem leaning as the font does.
        case unclear

        init(_ font: CTFont, _ character: Character, slant: CGFloat) {
            if LetterShapes.glyph(font, character) == nil {
                self = .missing
            } else if let letter = Letter(font, character, slant: slant) {
                self = .measured(letter)
            } else {
                self = .unclear
            }
        }
    }

    private struct Letter {
        /// How far the ink near the baseline reaches past the stem on its shorter side, in stem widths.
        var foot: CGFloat
        /// The same near the top.
        var head: CGFloat
        /// The farthest the ink reaches past the stem at either end, to either side.
        var reach: CGFloat

        /// nil when the font has no such letter, or it isn't one straight stem leaning as the font does.
        init?(_ font: CTFont, _ character: Character, slant: CGFloat) {
            // In thousandths of an em, whatever size the font was made at.
            var scale = CGAffineTransform(scaleX: 1000 / CTFontGetSize(font), y: 1000 / CTFontGetSize(font))
            guard let glyph = LetterShapes.glyph(font, character), let path = CTFontCreatePathForGlyph(font, glyph, &scale) else { return nil }
            let box = path.boundingBoxOfPath
            guard box.height > 50, box.width > 0 else { return nil }
            let outline = Outline(path.flattened(threshold: 1))
            // A stem, or a stem drawn in two overlapping parts; an outline or inline letter has more.
            guard outline.contours <= 2 else { return nil }
            func y(_ fraction: CGFloat) -> CGFloat { box.minY + box.height * fraction }

            // One run of ink at 30, 50 and 70 per cent of the height, about as wide at each, on a straight line.
            let stem = ([0.3, 0.5, 0.7] as [CGFloat]).compactMap { fraction -> ClosedRange<CGFloat>? in
                let runs = outline.runs(at: y(fraction))
                return runs.count == 1 ? runs[0] : nil
            }
            guard stem.count == 3 else { return nil }
            let widths = stem.map { $0.upperBound - $0.lowerBound }
            let width = widths[1]
            guard widths.min()! > 0, widths.max()! / widths.min()! < 1.3, width < box.height * 0.4 else { return nil }
            let centers = stem.map { ($0.lowerBound + $0.upperBound) / 2 }
            guard abs(centers[1] - (centers[0] + centers[2]) / 2) < width * 0.15 else { return nil }
            let lean = (centers[2] - centers[0]) / (box.height * 0.4)
            guard abs(lean - slant) < 0.12 else { return nil }

            // How far the ink a little way in from an end reaches past where the stem would be there.
            func overhang(_ fractions: [CGFloat]) -> (left: CGFloat, right: CGFloat) {
                var left: CGFloat = 0, right: CGFloat = 0
                for fraction in fractions {
                    let shift = (y(fraction) - y(0.5)) * lean
                    let here = (stem[1].lowerBound + shift)...(stem[1].upperBound + shift)
                    guard let run = outline.runs(at: y(fraction)).first(where: { $0.overlaps(here) }) else { continue }
                    left = max(left, (here.lowerBound - run.lowerBound) / width)
                    right = max(right, (run.upperBound - here.upperBound) / width)
                }
                return (left, right)
            }
            let foot = overhang([0.01, 0.02, 0.035, 0.05])
            let head = overhang([0.99, 0.98, 0.965, 0.95])
            self.foot = min(foot.left, foot.right)
            self.head = min(head.left, head.right)
            reach = max(foot.left, foot.right, head.left, head.right)
        }
    }

    /// A flattened glyph outline as straight edges, to find the ink along a horizontal line.
    private struct Outline {
        private struct Edge {
            var from: CGPoint
            var to: CGPoint
        }

        private var edges: [Edge] = []
        private(set) var contours = 0

        init(_ path: CGPath) {
            var start = CGPoint.zero, current = CGPoint.zero
            var edges: [Edge] = []
            var contours = 0
            func line(to point: CGPoint) {
                // Flat edges cross no horizontal line.
                if point.y != current.y { edges.append(Edge(from: current, to: point)) }
                current = point
            }
            path.applyWithBlock { element in
                let element = element.pointee
                switch element.type {
                case .moveToPoint:
                    line(to: start)
                    start = element.points[0]
                    current = start
                    contours += 1
                case .addLineToPoint:
                    line(to: element.points[0])
                case .addQuadCurveToPoint:
                    line(to: element.points[1])
                case .addCurveToPoint:
                    line(to: element.points[2])
                case .closeSubpath:
                    line(to: start)
                @unknown default:
                    break
                }
            }
            line(to: start)
            self.edges = edges
            self.contours = contours
        }

        /// The ink along y, left to right, filled as glyphs are (non-zero winding).
        func runs(at y: CGFloat) -> [ClosedRange<CGFloat>] {
            var crossings: [(x: CGFloat, winding: Int)] = []
            for edge in edges {
                let (low, high) = edge.from.y < edge.to.y ? (edge.from.y, edge.to.y) : (edge.to.y, edge.from.y)
                guard y >= low, y < high else { continue }
                let x = edge.from.x + (y - edge.from.y) * (edge.to.x - edge.from.x) / (edge.to.y - edge.from.y)
                crossings.append((x, edge.to.y > edge.from.y ? 1 : -1))
            }
            crossings.sort { $0.x < $1.x }
            var runs: [ClosedRange<CGFloat>] = []
            var winding = 0
            var begin: CGFloat = 0
            for crossing in crossings {
                let before = winding
                winding += crossing.winding
                if before == 0, winding != 0 { begin = crossing.x }
                guard before != 0, winding == 0 else { continue }
                // Overlapping contours can leave a hairline between their runs.
                if let last = runs.last, begin - last.upperBound < 1 {
                    runs[runs.count - 1] = last.lowerBound...crossing.x
                } else {
                    runs.append(begin...crossing.x)
                }
            }
            return runs
        }
    }
}
