#!/usr/bin/env python3
"""Writes Sources/Cicero/App/MenuBarIcon.swift: the C of AM Gaonkar Display Medium, the app icon's font (see
make-icon.py), as the outline of Cicero's icon in the menu bar.

    scripts/make-menu-bar-icon.py path/to/AMGaonkar-Display-Medium.otf

Needs fontTools (pip3 install fonttools).
"""

import argparse
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

OUT = Path(__file__).resolve().parent.parent / "Sources" / "Cicero" / "App" / "MenuBarIcon.swift"


class SwiftPen(BasePen):
    """The glyph as NSBezierPath calls, in font units from the bottom left of its bounds."""

    def __init__(self, glyphSet, origin):
        super().__init__(glyphSet)
        self.origin = origin
        self.lines = []

    def point(self, p):
        return f"NSPoint(x: {p[0] - self.origin[0]:g}, y: {p[1] - self.origin[1]:g})"

    def _moveTo(self, p):
        self.lines.append(f"path.move(to: {self.point(p)})")

    def _lineTo(self, p):
        self.lines.append(f"path.line(to: {self.point(p)})")

    def _curveToOne(self, c1, c2, p):
        self.lines.append(f"path.curve(to: {self.point(p)}, controlPoint1: {self.point(c1)}, controlPoint2: {self.point(c2)})")

    def _closePath(self):
        self.lines.append("path.close()")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("font")
    args = parser.parse_args()
    glyphs = TTFont(args.font).getGlyphSet()
    bounds = BoundsPen(glyphs)
    glyphs["C"].draw(bounds)
    x_min, y_min, x_max, y_max = bounds.bounds
    pen = SwiftPen(glyphs, (x_min, y_min))
    glyphs["C"].draw(pen)
    body = "\n".join(f"        {line}" for line in pen.lines)
    OUT.write_text(f"""import AppKit

// Written by scripts/make-menu-bar-icon.py from the C of the app icon's font. Don't edit.
enum MenuBarIcon {{
    /// The C, `height` points high, as a template image, which the menu bar draws in its own colour.
    static func image(height: CGFloat) -> NSImage {{
        let scale = height / {y_max - y_min:g}
        let image = NSImage(size: NSSize(width: ({x_max - x_min:g} * scale).rounded(.up), height: height), flipped: false) {{ _ in
            let path = outline()
            path.transform(using: AffineTransform(scale: scale))
            NSColor.black.setFill()
            path.fill()
            return true
        }}
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }}

    private static func outline() -> NSBezierPath {{
        let path = NSBezierPath()
{body}
        return path
    }}
}}
""")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
