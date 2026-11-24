import CoreText
import Foundation

public struct LetterMeasurements: Equatable, Sendable {
    public internal(set) var values: [Float]

    public enum Measure: Int, CaseIterable, Sendable {
        case xHeight
        case ascender
        case descender
        case weight
        case contrast
        case stress
        case width
        case capitalWidth
        case roundWidth
        case spacing
        case slant
        case serifLength
        case serifThickness
        case aperture
        case squareness
        case doubleStoryA
        case doubleStoryG
        case monospaced
        case rounded
        case allCaps
        case stencil
        case outline
    }

    init(values: [Float]) {
        self.values = values
    }

    public subscript(_ measure: Measure) -> Float { values[measure.rawValue] }

    private static let fewest = 10

    public static func measure(_ font: CTFont, glyphMap: ((Character) -> CGGlyph?)? = nil) -> LetterMeasurements? {
        let font = LetterImages.inThousandths(font)
        let lookup: (Character) -> CGGlyph? = glyphMap ?? { font.glyph(for: $0) }
        var letters: [Character: Letter] = [:]
        func letter(_ character: Character) -> Letter? {
            if let known = letters[character] { return known }
            let letter = Letter(font, character, lookup: lookup)
            letters[character] = letter
            return letter
        }
        guard let capHeight = letter("H").map({ $0.box.maxY }) ?? positive(CTFontGetCapHeight(font))
            ?? letter("O").map({ $0.box.maxY }) ?? letter("A").map({ $0.box.maxY }) ?? letter("M").map({ $0.box.maxY }),
            capHeight > 50 else { return nil }
        let xHeight = letter("x").map(\.box.maxY) ?? letter("n").map(\.box.maxY) ?? letter("o").map(\.box.maxY)
            ?? positive(CTFontGetXHeight(font)) ?? capHeight
        var values = [Float](repeating: .nan, count: Measure.allCases.count)
        func set(_ measure: Measure, _ value: CGFloat?) {
            if let value, value.isFinite { values[measure.rawValue] = Float(value) }
        }

        set(.xHeight, xHeight / capHeight)
        set(.ascender, mean(["l", "d"].compactMap { letter($0).map { $0.box.maxY / capHeight } }))
        set(.descender, mean(["p", "q"].compactMap { letter($0).map { -$0.box.minY / capHeight } }))

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
        let curvedSlant = abs(fontSlant) > 0.01 || measuredSlant != nil ? nil : Self.covarianceSlant(font, lookup: lookup)
        set(.slant, abs(fontSlant) > 0.01 ? fontSlant : measuredSlant ?? curvedSlant ?? fontSlant)

        var serifs: [Letter.Foot] = []
        if let h, let foot = h.leftFoot(height: h.box.height, at: [0.25, 0.4]) { serifs.append(foot) }
        if let n, let foot = n.leftFoot(height: xHeight, at: [0.3, 0.45]) { serifs.append(foot) }
        // I and l only when H and n can't say: sans serif monospaced faces give their I and l serifs.
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
        if glyphMap == nil {
            set(.monospaced, LetterShapes.isMonospaced(font) ? 1 : 0)
        } else if let i = letter("i"), let m = letter("m"), let w = letter("W") {
            set(.monospaced, abs(i.advance - m.advance) < 1 && abs(m.advance - w.advance) < 1 ? 1 : 0)
        }
        let reach = (stem ?? capHeight * 0.08) * 0.25
        let ends = "HEILTlik".compactMap { letter($0) }
        if ends.count >= 4 {
            let dotted = "HOn".compactMap { letter($0) }.count { $0.contours >= 5 } >= 2
            let corners = ends.map { $0.sharpCorners(within: reach) }
            set(.rounded, !dotted && CGFloat(corners.reduce(0, +)) / CGFloat(corners.count) < 0.5 ? 1 : 0)
        }
        let ascenderOverX = mean(["l", "d"].compactMap { letter($0).map { $0.box.maxY / xHeight } })
        set(.allCaps, Self.detectAllCaps(font, lookup: lookup, capitals: capitals.count, lowercase: lowercase.count, ascenderOverX: ascenderOverX))
        let (stencil, outline) = Self.detectTopology(font, lookup: lookup)
        set(.stencil, stencil)
        set(.outline, outline)

        guard values.count(where: { !$0.isNaN }) >= fewest else { return nil }
        return LetterMeasurements(values: values)
    }

    // Symmetric letters have zero x-y covariance when upright, so cov(x,y)/var(y) equals tan(slant) even on curved scripts.
    private static func covarianceSlant(_ font: CTFont, lookup: (Character) -> CGGlyph?) -> CGFloat? {
        var leans: [CGFloat] = []
        let size = 48
        for character in ["o", "O", "H", "x", "X", "n"] as [Character] {
            guard let glyph = lookup(character), let path = CTFontCreatePathForGlyph(font, glyph, nil),
                  let pixels = renderAspect(path, size: size) else { continue }
            var sx: CGFloat = 0, sy: CGFloat = 0, sw: CGFloat = 0
            for y in 0..<size {
                for x in 0..<size {
                    let w = CGFloat(pixels[y * size + x]) / 255
                    if w > 0 {
                        sx += w * CGFloat(x)
                        sy += w * CGFloat(size - 1 - y)
                        sw += w
                    }
                }
            }
            guard sw > 10 else { continue }
            let mx = sx / sw, my = sy / sw
            var cov: CGFloat = 0, vary: CGFloat = 0
            for y in 0..<size {
                for x in 0..<size {
                    let w = CGFloat(pixels[y * size + x]) / 255
                    if w > 0 {
                        let dx = CGFloat(x) - mx, dy = CGFloat(size - 1 - y) - my
                        cov += w * dx * dy
                        vary += w * dy * dy
                    }
                }
            }
            if vary > 1 { leans.append(cov / vary) }
        }
        guard !leans.isEmpty else { return nil }
        leans.sort()
        return leans[leans.count / 2]
    }

    // Heavy condensed bicameral fonts (like Impact) fill most of their box, so raw overlap misfires; mean-centered correlation plus tall lowercase ascenders avoids them.
    private static func detectAllCaps(_ font: CTFont, lookup: (Character) -> CGGlyph?, capitals: Int, lowercase: Int, ascenderOverX: CGFloat?) -> CGFloat? {
        if capitals >= 13 && lowercase < 5 { return 1 }
        if let ascenderOverX, ascenderOverX > 1.08 { return 0 }
        let pairs: [(Character, Character)] = [("A", "a"), ("E", "e"), ("G", "g"), ("H", "h"), ("N", "n"), ("R", "r")]
        var tested = 0, matched = 0
        for (upper, lower) in pairs {
            guard let gu = lookup(upper), let gl = lookup(lower) else { continue }
            if gu == gl {
                tested += 1
                matched += 1
                continue
            }
            guard let pu = CTFontCreatePathForGlyph(font, gu, nil), let pl = CTFontCreatePathForGlyph(font, gl, nil),
                  let bu = renderFit(pu, size: 24), let bl = renderFit(pl, size: 24) else { continue }
            tested += 1
            if pearson(bu, bl) >= 0.72 { matched += 1 }
        }
        guard tested >= 3 else { return nil }
        return CGFloat(matched) / CGFloat(tested) >= 0.66 ? 1 : 0
    }

    // Rasterized connected components merge variable fonts' overlapping contours while catching stencil gaps and hollow outline stems.
    private static func detectTopology(_ font: CTFont, lookup: (Character) -> CGGlyph?) -> (stencil: CGFloat?, outline: CGFloat?) {
        let size = 64
        var rasters: [Character: [UInt8]] = [:]
        func raster(_ character: Character) -> [UInt8]? {
            if let known = rasters[character] { return known }
            guard let glyph = lookup(character), let path = CTFontCreatePathForGlyph(font, glyph, nil),
                  let pixels = renderAspect(path, size: size) else { return nil }
            rasters[character] = pixels
            return pixels
        }

        let stencilChars: [Character] = ["O", "D", "P", "B", "A", "H", "E", "R", "o", "e"]
        let closedChars: Set<Character> = ["O", "D", "P", "B", "o"]
        var split = 0, closedOpen = 0, stencilTested = 0, dotted = 0
        for character in stencilChars {
            guard let pixels = raster(character) else { continue }
            // Low ink threshold keeps ultra-thin Didot/Bodoni hairlines connected so they never read as stencil cuts.
            let info = topology(pixels, size: size, inkThreshold: 20)
            stencilTested += 1
            if info.majorBlobs >= 2 && info.majorBlobs <= 5 { split += 1 }
            if info.majorBlobs >= 6 { dotted += 1 }
            if closedChars.contains(character) && info.holes == 0 && info.majorBlobs >= 2 { closedOpen += 1 }
        }
        let stencil: CGFloat? = stencilTested >= 4 ? (dotted < 2 && split >= 3 && closedOpen >= 2 ? 1 : 0) : nil

        let solidChars: [Character] = ["H", "E", "F", "I", "L", "T", "l", "n"]
        let simpleChars: Set<Character> = ["I", "L", "T", "l", "n"]
        var hollow = 0, simpleHollow = 0, solidTested = 0
        for character in solidChars {
            guard let pixels = raster(character) else { continue }
            let info = topology(pixels, size: size, inkThreshold: 32)
            solidTested += 1
            if info.holes >= 1 {
                hollow += 1
                if simpleChars.contains(character) { simpleHollow += 1 }
            }
        }
        let outline: CGFloat? = solidTested >= 4 ? (CGFloat(hollow) / CGFloat(solidTested) >= 0.6 && simpleHollow >= 2 ? 1 : 0) : nil
        return (stencil, outline)
    }

    private static func renderFit(_ path: CGPath, size: Int) -> [UInt8]? {
        let box = path.boundingBoxOfPath
        guard box.width > 1, box.height > 1 else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        let margin: CGFloat = 2
        let inner = CGFloat(size) - margin * 2
        let sx = inner / box.width, sy = inner / box.height
        var transform = CGAffineTransform(translationX: margin - box.minX * sx, y: margin - box.minY * sy).scaledBy(x: sx, y: sy)
        guard let placed = path.copy(using: &transform) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(placed)
        context.fillPath()
        return pixels
    }

    private static func renderAspect(_ path: CGPath, size: Int) -> [UInt8]? {
        let box = path.boundingBoxOfPath
        guard box.width > 1, box.height > 1 else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        let margin: CGFloat = 3
        let inner = CGFloat(size) - margin * 2
        let scale = min(inner / box.width, inner / box.height)
        let dx = (CGFloat(size) - box.width * scale) / 2 - box.minX * scale
        let dy = (CGFloat(size) - box.height * scale) / 2 - box.minY * scale
        var transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        guard let placed = path.copy(using: &transform) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(placed)
        context.fillPath()
        return pixels
    }

    private static func pearson(_ a: [UInt8], _ b: [UInt8]) -> CGFloat {
        let n = CGFloat(a.count)
        var sa: CGFloat = 0, sb: CGFloat = 0
        for index in 0..<a.count {
            sa += CGFloat(a[index])
            sb += CGFloat(b[index])
        }
        let ma = sa / n, mb = sb / n
        var num: CGFloat = 0, da: CGFloat = 0, db: CGFloat = 0
        for index in 0..<a.count {
            let xa = CGFloat(a[index]) - ma, xb = CGFloat(b[index]) - mb
            num += xa * xb
            da += xa * xa
            db += xb * xb
        }
        let den = sqrt(da * db)
        return den > 1e-6 ? num / den : 0
    }

    private static func topology(_ pixels: [UInt8], size: Int, inkThreshold: UInt8) -> (majorBlobs: Int, holes: Int) {
        let count = size * size
        var ink = [Bool](repeating: false, count: count)
        var totalInk = 0
        for index in 0..<count where pixels[index] >= inkThreshold {
            ink[index] = true
            totalInk += 1
        }
        guard totalInk > 0 else { return (0, 0) }
        var visited = [Bool](repeating: false, count: count)
        var blobSizes: [Int] = []
        var queue: [Int] = []
        queue.reserveCapacity(count)
        for start in 0..<count where ink[start] && !visited[start] {
            visited[start] = true
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                let x = current % size, y = current / size
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < size else { continue }
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        guard nx >= 0, nx < size else { continue }
                        let next = ny * size + nx
                        if ink[next] && !visited[next] {
                            visited[next] = true
                            queue.append(next)
                        }
                    }
                }
            }
            blobSizes.append(queue.count)
        }
        let minimumBlob = max(8, Int(Double(totalInk) * 0.10))
        let majorBlobs = blobSizes.count { $0 >= minimumBlob }

        visited = [Bool](repeating: false, count: count)
        var holes = 0
        for start in 0..<count where !ink[start] && !visited[start] {
            visited[start] = true
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var head = 0, touchesBorder = false
            while head < queue.count {
                let current = queue[head]
                head += 1
                let x = current % size, y = current / size
                if x == 0 || y == 0 || x == size - 1 || y == size - 1 { touchesBorder = true }
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < size, ny >= 0, ny < size else { continue }
                    let next = ny * size + nx
                    if !ink[next] && !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
            if !touchesBorder && queue.count >= 6 { holes += 1 }
        }
        return (majorBlobs, holes)
    }

    private static func positive(_ value: CGFloat) -> CGFloat? { value > 0 ? value : nil }

    private static func mean(_ values: [CGFloat]) -> CGFloat? {
        values.isEmpty ? nil : values.reduce(0, +) / CGFloat(values.count)
    }
}

private struct Letter {
    let box: CGRect
    let advance: CGFloat
    private let horizontal: LetterShapes.Outline
    private let vertical: LetterShapes.Outline
    private let edges: [(CGPoint, CGPoint)]
    private let path: CGPath
    private let polygons: [[CGPoint]]

    init?(_ font: CTFont, _ character: Character, lookup: (Character) -> CGGlyph?) {
        guard let glyph = lookup(character), let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
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
        self.path = flat
        polygons = Self.polygons(of: flat)
    }

    var contours: Int { horizontal.contours }

    func rows(at y: CGFloat) -> [ClosedRange<CGFloat>] { horizontal.runs(at: y) }

    func columns(at x: CGFloat) -> [ClosedRange<CGFloat>] { vertical.runs(at: x) }

    private func y(_ fraction: CGFloat) -> CGFloat { box.minY + box.height * fraction }

    func leftStem(at fractions: [CGFloat]) -> CGFloat? {
        let widths = fractions.compactMap { fraction -> CGFloat? in
            let runs = rows(at: y(fraction))
            return runs.count == 2 ? runs[0].length : nil
        }
        guard widths.count == fractions.count, let width = widths.min(), width > 0, widths.max()! / width < 1.4 else { return nil }
        return widths.reduce(0, +) / CGFloat(widths.count)
    }

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
        var length: CGFloat
        var thickness: CGFloat
    }

    func leftFoot(height: CGFloat, at fractions: [CGFloat]) -> Foot? {
        let at = fractions.map { rows(at: box.minY + height * $0) }
        guard at.allSatisfy({ $0.count == 2 }), at[0][0].length > 0, abs(at[1][0].length / at[0][0].length - 1) < 0.3 else { return nil }
        let lean = (at[1][0].center - at[0][0].center) / (height * (fractions[1] - fractions[0]))
        return foot(of: at[0][0], lean: lean, from: box.minY, height: height, measuredAt: box.minY + height * fractions[0])
    }

    private func foot(of stem: ClosedRange<CGFloat>, lean: CGFloat, from base: CGFloat, height: CGFloat, measuredAt: CGFloat? = nil) -> Foot {
        let middle = measuredAt ?? base + height / 2
        let width = stem.length
        func run(at y: CGFloat) -> ClosedRange<CGFloat>? {
            let shift = (y - middle) * lean
            let here = (stem.lowerBound + shift)...(stem.upperBound + shift)
            return rows(at: y).first { $0.overlaps(here) }
        }
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
        let thickest = atan2(sines, cosines) / 2 * 180 / .pi
        return (thickest, hypot(cosines, sines) / CGFloat(directions / 2) / mean)
    }

    func mostCrossings(at fractions: [CGFloat]) -> Int {
        fractions.map { columns(at: box.minX + box.width * $0).count }.max() ?? 0
    }

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

    // Corners rounded off much less than the stem is thick still count: Adobe Caslon and Garamond Premier round every serif's corners by a few units.
    func sharpCorners(within reach: CGFloat) -> Int {
        var count = 0
        for points in polygons {
            let n = points.count
            var area: CGFloat = 0
            for index in 0..<n { area += points[index].x * points[(index + 1) % n].y - points[(index + 1) % n].x * points[index].y }
            let outward: CGFloat = area > 0 ? 1 : -1
            var turns: [CGFloat] = [], lengths: [CGFloat] = []
            for index in 0..<n {
                let a = points[(index + n - 1) % n], b = points[index], c = points[(index + 1) % n]
                var turn = atan2(c.y - b.y, c.x - b.x) - atan2(b.y - a.y, b.x - a.x)
                if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
                turns.append(turn * outward)
                lengths.append(hypot(c.x - b.x, c.y - b.y))
            }
            var start = 0
            while start < n {
                var turned: CGFloat = 0, length: CGFloat = 0, end = start
                while length <= reach, end < start + n {
                    turned += turns[end % n]
                    length += lengths[end % n]
                    end += 1
                }
                if turned > .pi / 3, !isInside(points[start], by: max(reach * 0.2, 2)) {
                    count += 1
                    start = end
                } else {
                    start += 1
                }
            }
        }
        return count
    }

    // Variable fonts keep their contours overlapping, so a crossbar's corners can sit inside the stems.
    private func isInside(_ point: CGPoint, by distance: CGFloat) -> Bool {
        (0..<8).allSatisfy { step in
            let angle = CGFloat(step) * .pi / 4
            return path.contains(CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance), using: .winding)
        }
    }

    private static func polygons(of path: CGPath) -> [[CGPoint]] {
        var polygons: [[CGPoint]] = [], current: [CGPoint] = []
        func finish() {
            if current.count > 1, current.first == current.last { current.removeLast() }
            if current.count > 2 { polygons.append(current) }
            current = []
        }
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                finish()
                current = [element.points[0]]
            case .addLineToPoint:
                if element.points[0] != current.last { current.append(element.points[0]) }
            case .closeSubpath:
                finish()
            default:
                break
            }
        }
        finish()
        return polygons
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

    private static func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y), s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        return (0...1).contains(t) && (0...1).contains(u) ? t : nil
    }

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
