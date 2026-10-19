import CoreText
import Foundation

/// What a face's letters look like, as numbers: how tall its lowercase is, how heavy and how contrasted its strokes,
/// how wide, slanted and open its letters, and whether it has serifs and how big. Measured from the outlines of a
/// few letters (H, I, O, a, c, d, e, g, l, n, o, p, x) and given against the cap height, so a face drawn small on its
/// em measures as one drawn large. Similar fonts are the faces whose measurements are nearest (see `SimilarFonts`).
public struct LetterMeasurements: Equatable, Sendable {
    /// One value for each measure, in the order of `Measure.allCases`; NaN where the face hasn't the letters to say.
    public internal(set) var values: [Float]

    public enum Measure: Int, CaseIterable, Sendable {
        /// The x's height against the H's.
        case xHeight
        /// How far the l and d reach, against the H's height.
        case ascender
        /// How far the p and q reach below the baseline, against the H's height.
        case descender
        /// The H's and n's stems against the H's height.
        case weight
        /// The thin strokes against the thick: the o's top and bottom against its sides, and the H's crossbar
        /// against its stems. 1 for strokes all as thick.
        case contrast
        /// How far the o's thinnest parts are turned from its top and bottom, as a pen held at an angle leaves
        /// them, in units of 30°, and less the less its thickness changes going round: 0 for Bodoni's upright
        /// stress and for strokes about as thick all round, about 0.5 for Garamond's.
        case stress
        /// The lowercase's average advance against the x-height.
        case width
        /// The capitals' average advance against the cap height.
        case capitalWidth
        /// The o's width against its height.
        case roundWidth
        /// The room either side of n, o, H and O, against the x-height.
        case spacing
        /// How far the letters lean: along for each unit up.
        case slant
        /// How far serifs reach past the stems of H and n (of I and l when neither can say), on each side, against
        /// the H's height; 0 without. Not the I's and l's first, which sans serif monospaced faces give serifs.
        case serifLength
        /// How thick serifs are at the stem, bracket and all, against the H's height; 0 without.
        case serifThickness
        /// How open c and e are: the share of directions from inside them that leads out.
        case aperture
        /// How much of its box the o fills: π/4 for an ellipse, more for a squarer one.
        case squareness
        /// 1 when the a has a bowl and a hook over it, 0 when it's a bowl alone.
        case doubleStoryA
        /// 1 when the g has two bowls, 0 when it has one and a tail.
        case doubleStoryG
        /// 1 for a monospaced face.
        case monospaced
    }

    init(values: [Float]) {
        self.values = values
    }

    public subscript(_ measure: Measure) -> Float { values[measure.rawValue] }

    /// Fewer than this many measures, and the face hasn't enough of the Latin alphabet to compare.
    private static let fewest = 10

    /// nil when the face hasn't enough Latin letters drawn as outlines to say, as for most fonts of other scripts,
    /// symbols and bitmap emoji.
    public static func measure(_ font: CTFont) -> LetterMeasurements? {
        // In thousandths of an em.
        let font = CTFontCreateCopyWithAttributes(font, 1000, nil, nil)
        var letters: [Character: Letter] = [:]
        func letter(_ character: Character) -> Letter? {
            if let known = letters[character] { return known }
            let letter = Letter(font, character)
            letters[character] = letter
            return letter
        }
        guard let capHeight = letter("H").map({ $0.box.maxY }) ?? positive(CTFontGetCapHeight(font)), capHeight > 50 else { return nil }
        let xHeight = letter("x").map(\.box.maxY) ?? positive(CTFontGetXHeight(font)) ?? capHeight
        var values = [Float](repeating: .nan, count: Measure.allCases.count)
        func set(_ measure: Measure, _ value: CGFloat?) {
            if let value, value.isFinite { values[measure.rawValue] = Float(value) }
        }

        set(.xHeight, xHeight / capHeight)
        set(.ascender, mean(["l", "d"].compactMap { letter($0).map { $0.box.maxY / capHeight } }))
        set(.descender, mean(["p", "q"].compactMap { letter($0).map { -$0.box.minY / capHeight } }))

        // Stems: the H's left one away from its crossbar, and the n's.
        var stems: [CGFloat] = []
        let h = letter("H")
        if let h, let stem = h.leftStem(at: [0.25, 0.75]) { stems.append(stem) }
        let n = letter("n")
        if let n, let stem = n.leftStem(at: [0.3, 0.45]) { stems.append(stem) }
        let stem = mean(stems)
        set(.weight, stem.map { $0 / capHeight })

        var contrasts: [CGFloat] = []
        let o = letter("o")
        if let o {
            let sides = o.rows(at: o.box.midY), ends = o.columns(at: o.box.midX)
            if sides.count == 2, ends.count == 2, let thick = mean(sides.map(\.length)), let thin = mean(ends.map(\.length)), thick > 0 {
                contrasts.append(thin / thick)
            }
        }
        if let h, let hStem = h.leftStem(at: [0.25, 0.75]), hStem > 0 {
            let bar = h.columns(at: h.box.midX)
            if bar.count == 1 { contrasts.append(bar[0].length / hStem) }
        }
        let contrast = mean(contrasts).map { min($0, 1.5) }
        set(.contrast, contrast)
        // Strokes about as thick all round have no stress to speak of, whichever way they're thinnest.
        if let o, let axis = o.stressAxis() { set(.stress, min(max(axis.tilt, -40), 40) / 30 * min(axis.modulation / 0.5, 1)) }

        let lowercase = "abcdefghijklmnopqrstuvwxyz".compactMap { letter($0)?.advance }
        let capitals = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".compactMap { letter($0)?.advance }
        if lowercase.count >= 13 { set(.width, mean(lowercase).map { $0 / xHeight }) }
        if capitals.count >= 13 { set(.capitalWidth, mean(capitals).map { $0 / capHeight }) }
        set(.roundWidth, o.map { $0.box.width / $0.box.height })
        let room = [("n", xHeight), ("o", xHeight), ("H", capHeight), ("O", capHeight)].compactMap { character, height in
            letter(character).map { ($0.advance - $0.box.width) / height }
        }
        set(.spacing, mean(room))

        let stemLetters = ["I", "l"].compactMap { letter($0).flatMap(\.straightStem) }
        let fontSlant = tan(-CTFontGetSlantAngle(font) * .pi / 180)
        let measuredSlant = mean(stemLetters.map(\.lean))
        set(.slant, abs(fontSlant) > 0.01 ? fontSlant : measuredSlant ?? fontSlant)

        var serifs: [Letter.Foot] = []
        if let h, let foot = h.leftFoot(height: h.box.height, at: [0.25, 0.4]) { serifs.append(foot) }
        if let n, let foot = n.leftFoot(height: xHeight, at: [0.3, 0.45]) { serifs.append(foot) }
        if serifs.isEmpty { serifs = stemLetters.map(\.foot) }
        set(.serifLength, mean(serifs.map(\.length)).map { $0 / capHeight })
        set(.serifThickness, mean(serifs.map(\.thickness)).map { $0 / capHeight })

        var openings: [CGFloat] = []
        if let c = letter("c"), let open = c.openness(fromHeights: [0.5, 0.45, 0.55]) { openings.append(open) }
        if let e = letter("e"), let open = e.openness(fromHeights: [0.3, 0.25, 0.35]) { openings.append(open) }
        set(.aperture, mean(openings))

        set(.squareness, mean([o, letter("O")].compactMap { $0?.filledShare }))
        if let a = letter("a") { set(.doubleStoryA, a.mostCrossings(at: [0.45, 0.5, 0.55]) >= 3 ? 1 : 0) }
        if let g = letter("g") { set(.doubleStoryG, g.mostCrossings(at: [0.4, 0.5, 0.6]) >= 4 ? 1 : 0) }
        set(.monospaced, LetterShapes.isMonospaced(font) ? 1 : 0)

        guard values.count(where: { !$0.isNaN }) >= fewest else { return nil }
        return LetterMeasurements(values: values)
    }

    private static func positive(_ value: CGFloat) -> CGFloat? { value > 0 ? value : nil }

    private static func mean(_ values: [CGFloat]) -> CGFloat? {
        values.isEmpty ? nil : values.reduce(0, +) / CGFloat(values.count)
    }
}

/// A letter's outline at 1,000 units to the em, to measure.
private struct Letter {
    let box: CGRect
    let advance: CGFloat
    /// The ink along horizontal lines.
    private let horizontal: LetterShapes.Outline
    /// The ink along vertical lines: the outline with x and y swapped.
    private let vertical: LetterShapes.Outline
    /// Every edge, to see what a line from inside the letter runs into.
    private let edges: [(CGPoint, CGPoint)]

    init?(_ font: CTFont, _ character: Character) {
        guard let glyph = LetterShapes.glyph(font, character), let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let box = path.boundingBoxOfPath
        guard box.width > 1, box.height > 1 else { return nil }
        let flat = path.flattened(threshold: 1)
        var swap = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        guard let swapped = flat.copy(using: &swap) else { return nil }
        var glyphs = [glyph]
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        self.box = box
        self.advance = advance.width
        horizontal = LetterShapes.Outline(flat)
        vertical = LetterShapes.Outline(swapped)
        edges = Self.edges(of: flat)
    }

    /// The ink along y, left to right.
    func rows(at y: CGFloat) -> [ClosedRange<CGFloat>] { horizontal.runs(at: y) }

    /// The ink along x, bottom to top.
    func columns(at x: CGFloat) -> [ClosedRange<CGFloat>] { vertical.runs(at: x) }

    private func y(_ fraction: CGFloat) -> CGFloat { box.minY + box.height * fraction }

    /// The width of the leftmost of two stems at these heights, as in H and n; nil unless there are two there.
    func leftStem(at fractions: [CGFloat]) -> CGFloat? {
        let widths = fractions.compactMap { fraction -> CGFloat? in
            let runs = rows(at: y(fraction))
            return runs.count == 2 ? runs[0].length : nil
        }
        guard widths.count == fractions.count, let width = widths.min(), width > 0, widths.max()! / width < 1.4 else { return nil }
        return widths.reduce(0, +) / CGFloat(widths.count)
    }

    /// A straight stem, as in I and l: one run of ink at 30, 50 and 70 per cent of the height, about as wide at
    /// each, on a straight line. nil for anything else.
    var straightStem: Stem? {
        let stem = ([0.3, 0.5, 0.7] as [CGFloat]).compactMap { fraction -> ClosedRange<CGFloat>? in
            let runs = rows(at: y(fraction))
            return runs.count == 1 ? runs[0] : nil
        }
        guard stem.count == 3 else { return nil }
        let widths = stem.map(\.length)
        let width = widths[1]
        guard widths.min()! > 0, widths.max()! / widths.min()! < 1.3, width < box.height * 0.4 else { return nil }
        let centers = stem.map { ($0.lowerBound + $0.upperBound) / 2 }
        guard abs(centers[1] - (centers[0] + centers[2]) / 2) < width * 0.15 else { return nil }
        let lean = (centers[2] - centers[0]) / (box.height * 0.4)
        return Stem(lean: lean, foot: foot(of: stem[1], lean: lean, from: box.minY, height: box.height))
    }

    struct Stem {
        var lean: CGFloat
        var foot: Foot
    }

    struct Foot {
        /// How far the foot reaches past the stem, on average each side.
        var length: CGFloat
        /// How far up the stem it's wider than the stem.
        var thickness: CGFloat
    }

    /// The foot of the left of two stems, as in H and n, from the baseline up; `fractions` are two heights, of
    /// `height`, where the stems are on their own.
    func leftFoot(height: CGFloat, at fractions: [CGFloat]) -> Foot? {
        let at = fractions.map { rows(at: box.minY + height * $0) }
        guard at.allSatisfy({ $0.count == 2 }), at[0][0].length > 0, abs(at[1][0].length / at[0][0].length - 1) < 0.3 else { return nil }
        let lean = (at[1][0].center - at[0][0].center) / (height * (fractions[1] - fractions[0]))
        return foot(of: at[0][0], lean: lean, from: box.minY, height: height, measuredAt: box.minY + height * fractions[0])
    }

    /// The foot of a stem that runs along `stem` at the middle of the height (or at `measuredAt`), leaning by `lean`.
    private func foot(of stem: ClosedRange<CGFloat>, lean: CGFloat, from base: CGFloat, height: CGFloat, measuredAt: CGFloat? = nil) -> Foot {
        let middle = measuredAt ?? base + height / 2
        let width = stem.length
        func run(at y: CGFloat) -> ClosedRange<CGFloat>? {
            let shift = (y - middle) * lean
            let here = (stem.lowerBound + shift)...(stem.upperBound + shift)
            return rows(at: y).first { $0.overlaps(here) }
        }
        // Up from the baseline, past a cupped foot's hollow, to where the ink is about as wide as the stem again.
        let step = max(1, height * 0.005)
        var widest = width, thickness: CGFloat = 0
        var y = base + step / 2
        while y < base + height * 0.3 {
            if let run = run(at: y), run.length > width + max(width * 0.1, 4) {
                widest = max(widest, run.length)
                thickness = y - base
            } else if thickness > 0 || y > base + height * 0.05 {
                break
            }
            y += step
        }
        return Foot(length: (widest - width) / 2, thickness: thickness)
    }

    /// Which way the stroke of a round letter is thick and thin: the thickness of the ring along lines out from the
    /// middle, every 6°, as one wave that peaks twice going round. `tilt` is how far in degrees its thin parts are
    /// turned from the top and bottom, positive when turned to the left at the top, as a broad pen held at an angle
    /// leaves them; `modulation` how much the thickness changes, against the average: 0 for strokes as thick all
    /// round, about 1 for hairlines against thick sides.
    func stressAxis() -> (tilt: CGFloat, modulation: CGFloat)? {
        let center = CGPoint(x: box.midX, y: box.midY)
        guard !rows(at: center.y).contains(where: { $0.contains(center.x) }) else { return nil }
        let reach = (box.width + box.height) * 2
        var sum: CGFloat = 0, cosines: CGFloat = 0, sines: CGFloat = 0
        let directions = 60
        for step in 0..<directions {
            let angle = CGFloat(step) / CGFloat(directions) * 2 * .pi
            let end = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
            let crossings = edges.compactMap { Self.crossing(center, end, $0.0, $0.1) }.sorted()
            guard crossings.count >= 2 else { return nil }
            let thickness = (crossings[1] - crossings[0]) * reach
            sum += thickness
            cosines += thickness * cos(2 * angle)
            sines += thickness * sin(2 * angle)
        }
        let mean = sum / CGFloat(directions)
        guard mean > 0 else { return nil }
        // Thickest where the wave peaks; thinnest a quarter turn on, so the tilt from upright is the thickest
        // direction's from level.
        let thickest = atan2(sines, cosines) / 2 * 180 / .pi
        return (thickest, hypot(cosines, sines) / CGFloat(directions / 2) / mean)
    }

    /// The most runs of ink crossed going up at these places across the letter: 3 for a double-story a, 2 for a
    /// single-story one.
    func mostCrossings(at fractions: [CGFloat]) -> Int {
        fractions.map { columns(at: box.minX + box.width * $0).count }.max() ?? 0
    }

    /// How much of the box the letter fills, its counters filled in: π/4 for an ellipse.
    var filledShare: CGFloat? {
        let lines = 40
        var area: CGFloat = 0
        for line in 0..<lines {
            let runs = rows(at: y((CGFloat(line) + 0.5) / CGFloat(lines)))
            if let first = runs.first, let last = runs.last { area += last.upperBound - first.lowerBound }
        }
        let share = area / CGFloat(lines) / box.width
        return share > 0 ? share : nil
    }

    /// The share of directions in which a line from inside the letter, at the middle of its width and the first
    /// of these heights that isn't in ink, leaves it without running into ink: how open a c or an e is.
    func openness(fromHeights fractions: [CGFloat]) -> CGFloat? {
        let x = box.midX
        guard let fraction = fractions.first(where: { fraction in !rows(at: y(fraction)).contains { $0.contains(x) } }) else { return nil }
        let origin = CGPoint(x: x, y: y(fraction))
        let reach = (box.width + box.height) * 2
        let directions = 180
        var open = 0
        for step in 0..<directions {
            let angle = CGFloat(step) / CGFloat(directions) * 2 * .pi
            let end = CGPoint(x: origin.x + cos(angle) * reach, y: origin.y + sin(angle) * reach)
            if !edges.contains(where: { Self.cross(origin, end, $0.0, $0.1) }) { open += 1 }
        }
        return CGFloat(open) / CGFloat(directions)
    }

    private static func edges(of path: CGPath) -> [(CGPoint, CGPoint)] {
        var edges: [(CGPoint, CGPoint)] = []
        var start = CGPoint.zero, current = CGPoint.zero
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                if current != start { edges.append((current, start)) }
                start = element.points[0]
                current = start
            case .addLineToPoint:
                edges.append((current, element.points[0]))
                current = element.points[0]
            case .addQuadCurveToPoint:
                edges.append((current, element.points[1]))
                current = element.points[1]
            case .addCurveToPoint:
                edges.append((current, element.points[2]))
                current = element.points[2]
            case .closeSubpath:
                if current != start { edges.append((current, start)) }
                current = start
            @unknown default:
                break
            }
        }
        if current != start { edges.append((current, start)) }
        return edges
    }

    /// How far along a–b, from 0 to 1, it crosses c–d; nil when they don't cross.
    private static func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y), s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        return (0...1).contains(t) && (0...1).contains(u) ? t : nil
    }

    /// Whether the segments a–b and c–d cross.
    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
        return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)
    }
}

private extension ClosedRange where Bound == CGFloat {
    var length: CGFloat { upperBound - lowerBound }
    var center: CGFloat { (lowerBound + upperBound) / 2 }
}
