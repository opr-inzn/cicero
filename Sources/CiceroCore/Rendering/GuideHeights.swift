import CoreText

/// Where a font's letters reach above and below the baseline, at the font's size, for lines drawn under its sample:
/// measured from the letters themselves where the font has them, as a type designer reads them, rather than from the
/// font's line metrics, which leave room for accents. A font without the letters, like an emoji font, gets no line.
public struct GuideHeights: Equatable, Sendable {
    /// The top of H.
    public let capHeight: CGFloat?
    /// The top of x.
    public let xHeight: CGFloat?
    /// The top of the tallest of b, d, h, k and l.
    public let ascender: CGFloat?
    /// How far the lowest of p and q goes below the baseline, as a positive distance.
    public let descender: CGFloat?
    /// The font's units to the point at its size, for the heights in the units the font was drawn in.
    public let unitsPerPoint: CGFloat

    public init(_ font: CTFont) {
        func box(_ character: Character) -> CGRect? {
            guard let glyph = font.glyph(for: character), let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
            let box = path.boundingBoxOfPath
            return box.isNull || box.height <= 0 ? nil : box
        }
        capHeight = box("H").map(\.maxY)
        xHeight = box("x").map(\.maxY)
        ascender = ["b", "d", "h", "k", "l"].compactMap { box($0)?.maxY }.max()
        descender = ["p", "q"].compactMap { box($0).map { -$0.minY } }.filter { $0 > 0 }.max()
        unitsPerPoint = CGFloat(CTFontGetUnitsPerEm(font)) / max(CTFontGetSize(font), 0.01)
    }

    /// A height in the font's units, like 480 for an x-height at 1,000 units to the em.
    public func units(_ height: CGFloat) -> Int { Int((height * unitsPerPoint).rounded()) }
}
