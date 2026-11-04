#if canImport(CiceroCore)
import CiceroCore
#endif
import SwiftUI

/// Where Overlay puts its samples, and the baseline Stacked gives its first row too, so that switching between them
/// leaves the first font at its height, and so that changing the order moves no font in Overlay: right under the
/// tallest of what Overlay draws. The lines start right of the column for Overlay's line names.
struct CompareFrame {
    let guides: CompareGuides
    /// From the top to the baseline: right under the tallest of what's drawn, any font's glyphs, the ascender lines a
    /// point above the ascenders, and the labels. Not under the first font's ascent, which kept Overlay's baseline
    /// where Stacked had its first row's (from the version after 0.11.0 up to 0.12.0b8): fonts keep different room
    /// above their glyphs for accents, so changing which font came first moved them all up or down, by 16 pt at 288 pt.
    let ascent: CGFloat
    /// Overlay's below the baseline: a point more for the lowest descender line, under its depth, and room for the
    /// labels.
    let descent: CGFloat
    /// The line names' column, and the gap after it.
    let left: CGFloat
    /// Room for glyphs reaching left of their line's start, between the names and the samples.
    let overhang: CGFloat
    /// Where each line starts in Overlay, from `origin`: the one whose stem is furthest from its start at 0, the
    /// others further in, so their stems stand on its. Started together, a serif font's stem stood right of a sans one's.
    let starts: [CGFloat]
    /// Overlay's samples', from `origin`, with a point to spare.
    let width: CGFloat

    /// Where Overlay's lines that start at 0 start, and its legend.
    var origin: CGFloat { left + overhang }

    init(lines: [TextLine], guides: [GuideHeights], tints: [Color], scale: CGFloat) {
        let names = CompareGuides(Array(zip(guides, tints)).map { (guides: $0.0, tint: $0.1) })
        self.guides = names
        ascent = Self.onPixel(max(lines.map(\.inkAscent).max() ?? 0, (guides.compactMap(\.ascender).max() ?? 0).rounded(.up) + 1,
                                  names.labelsAbove.rounded(.up)), scale: scale)
        descent = max(lines.map(\.descent).max() ?? 0, (guides.compactMap(\.descender).max() ?? 0).rounded(.up) + 1,
                      names.labelsBelow.rounded(.up))
        left = names.nameWidth + CompareGuides.gap
        let stems = lines.map { FirstStem.x(in: $0.line) ?? 0 }
        starts = stems.map { (stems.max() ?? 0) - $0 }
        overhang = zip(lines, starts).map { max(0, $0.overhang - $1) }.max() ?? 0
        width = (zip(lines, starts).map { $0.width + $1 }.max() ?? 0) + 2
    }

    /// A baseline this far down, moved down to a whole device pixel. CoreText moves text between pixels to one of them
    /// itself, up or down depending on where it draws, so lines measured from the baseline stood a pixel off the glyphs.
    static func onPixel(_ ascent: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return (ascent * scale).rounded(.up) / scale
    }
}
