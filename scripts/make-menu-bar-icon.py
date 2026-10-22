#!/usr/bin/env python3
"""Writes Sources/Cicero/App/MenuBarIcon.swift: the app icon's cube (see make-icon.py), with C, 1 and 6 from AM
Gaonkar Display Medium cut out of its faces, as the outline of Cicero's icon in the menu bar. The menu bar draws it
in one colour, black or white, and the faces meet without a gap: the cube is a solid hexagon with the letters in it.

    scripts/make-menu-bar-icon.py path/to/AMGaonkar-Display-Medium.otf

Needs fontTools and pyclipper, as make-icon.py does.
"""

import argparse
import importlib.util
from pathlib import Path

from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Sources" / "Cicero" / "App" / "MenuBarIcon.swift"

spec = importlib.util.spec_from_file_location("make_icon", HERE / "make-icon.py")
icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("font")
    args = parser.parse_args()
    glyphs = TTFont(args.font).getGlyphSet()
    cap = TTFont(args.font)["OS/2"].sCapHeight
    scale = icon.CAP / cap

    # The cube's outline on the icon's canvas, whose y goes down.
    corners = [p for face in icon.FACES.values() for p in icon.face_corners(face)]
    x0, y0 = min(p[0] for p in corners), min(p[1] for p in corners)
    width, height = max(p[0] for p in corners) - x0, max(p[1] for p in corners) - y0

    def point(p):
        return f"NSPoint(x: {p[0] - x0:.1f}, y: {p[1] - y0:.1f})"

    faces = []
    for name in ("top", "left", "right"):
        face = icon.FACES[name]
        pen = icon.ContourPen(glyphs)
        glyphs[face["glyph"]].draw(pen)
        xs = [q[0] for c in pen.contours for s in c for q in s[1:]]
        # Placed as make-icon.py places it: centred across on the outline's extremes, up and down on the cap height.
        cx, cy = (min(xs) + max(xs)) / 2, cap / 2

        def canvas(q, face=face, cx=cx, cy=cy):
            a, b = 0.5 + (q[0] - cx) * scale, 0.5 + (q[1] - cy) * scale
            return icon.project(icon.add(icon.add(face["origin"], face["right"], a), face["up"], b))

        lines = [f"path.move(to: {point(icon.face_corners(face)[0])})"]
        lines += [f"path.line(to: {point(p)})" for p in icon.face_corners(face)[1:]]
        lines.append("path.close()")
        # The projection is affine, so a curve's control points carry over.
        for contour in pen.contours:
            lines.append(f"path.move(to: {point(canvas(contour[0][1]))})")
            for segment in contour:
                pts = [canvas(q) for q in segment[2:]]
                if segment[0] == "L":
                    lines.append(f"path.line(to: {point(pts[0])})")
                else:
                    lines.append(f"path.curve(to: {point(pts[2])}, controlPoint1: {point(pts[0])}, controlPoint2: {point(pts[1])})")
            lines.append("path.close()")
        body = "\n".join(f"        {line}" for line in lines)
        faces.append(f"""    /// The {name} face, with its {face["glyph"]} cut out.
    private static func {name}() -> NSBezierPath {{
        let path = NSBezierPath()
{body}
        return path
    }}""")

    OUT.write_text(f"""import AppKit

// Written by scripts/make-menu-bar-icon.py from the app icon's cube and font. Don't edit.
enum MenuBarIcon {{
    /// The cube, `height` points high, as a template image, which the menu bar draws in its own colour, black or white:
    /// the letters cut out, the faces meeting without a gap.
    static func image(height: CGFloat) -> NSImage {{
        let scale = height / {height:.1f}
        let image = NSImage(size: NSSize(width: ({width:.1f} * scale).rounded(.up), height: height), flipped: true) {{ _ in
            // One path, so no seam of half-covered pixels shows where two faces meet.
            let cube = NSBezierPath()
            for face in [top(), left(), right()] {{ cube.append(face) }}
            cube.transform(using: AffineTransform(scale: scale))
            cube.windingRule = .evenOdd
            NSColor.black.set()
            cube.fill()
            return true
        }}
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }}

{chr(10).join(chr(10).join([f, ""]) for f in faces).rstrip()}
}}
""")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
