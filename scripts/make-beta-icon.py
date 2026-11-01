#!/usr/bin/env python3
"""Makes the beta icon, Resources/AppIconBeta.icon: Cicero's cube as a blueprint. White lines on blue: the cube's
edges, its hidden edges dashed, the C, 1 and 6 on its faces, flat, over a drawing's guides (circles, the cube's axes, a
grid and a border); no line but the edges goes across a letter. build-app.sh uses this icon when the version is a beta (like
0.12.0b1).

    scripts/make-beta-icon.py

The letters come from Resources/AppIcon.icon, so run it again after make-icon.py changes the cube. It needs only
Python's standard library.
"""

import json
import math
import re
import shutil
from pathlib import Path

RESOURCES = Path(__file__).resolve().parent.parent / "Resources"
SOURCE = RESOURCES / "AppIcon.icon" / "Assets"
TARGET = RESOURCES / "AppIconBeta.icon"

# make-icon.py's cube: its near corner in the middle of the 1024 canvas, its edge, seen corner on.
NEAR = (512.0, 512.0)
EDGE = 400.0
COS30 = math.cos(math.radians(30))

# The background, top to bottom, light and dark.
BLUE = (("#58A9F5", "#2F6BDC"), ("#2D6FC4", "#173C8C"))


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def line(points, closed=False):
    return "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in points) + ("Z" if closed else "")


def letter(name):
    """A face's letter, as path data: the face layer's path after its first subpath, the face's outline."""
    d = re.search(r'<path d="([^"]*)"', (SOURCE / f"{name}-face.svg").read_text()).group(1)
    return d.split("Z", 1)[1]


def polygons(d, step=0.05):
    """Path data of M, L, C and Z, all absolute, as polygons, the curves cut into lines."""
    tokens = re.findall(r"[MLCZ]|-?\d+(?:\.\d+)?", d)
    out, i, command = [], 0, None
    while i < len(tokens):
        if tokens[i] in "MLCZ":
            command = tokens[i]
            i += 1
            if command == "Z":
                continue
        n = 6 if command == "C" else 2
        v = [float(t) for t in tokens[i:i + n]]
        i += n
        if command == "M":
            out.append([(v[0], v[1])])
        elif command == "L":
            out[-1].append((v[0], v[1]))
        else:
            p0 = out[-1][-1]
            for k in range(1, int(1 / step) + 1):
                t = k * step
                a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
                out[-1].append((a * p0[0] + b * v[0] + c * v[2] + e * v[4], a * p0[1] + b * v[1] + c * v[3] + e * v[5]))
    return out


def outside(p0, p1, shapes, gap):
    """The pieces of the line from p0 to p1 that are outside the shapes (even-odd, as the letters are filled), each
    stopping gap pixels short of them."""
    length = math.dist(p0, p1)
    hits = []
    for shape in shapes:
        for k, q1 in enumerate(shape):
            q0 = shape[k - 1]
            # Where the line meets the edge q0 to q1, as a share t of the line.
            r = (p1[0] - p0[0], p1[1] - p0[1])
            s = (q1[0] - q0[0], q1[1] - q0[1])
            cross = r[0] * s[1] - r[1] * s[0]
            if abs(cross) < 1e-9:
                continue
            w = (q0[0] - p0[0], q0[1] - p0[1])
            t = (w[0] * s[1] - w[1] * s[0]) / cross
            u = (w[0] * r[1] - w[1] * r[0]) / cross
            if 0 <= t <= 1 and 0 <= u < 1:
                hits.append(t)
    hits.sort()
    # Between the first hit and the second the line is inside a letter, and so on.
    pieces, start = [], 0.0
    for enter, leave in zip(hits[::2], hits[1::2]):
        end = enter - gap / length
        if end > start:
            pieces.append((start, end))
        start = leave + gap / length
    if start < 1:
        pieces.append((start, 1.0))
    at = lambda t: (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
    return [(at(a), at(b)) for a, b in pieces]


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n  '
            + "\n  ".join(body) + "\n</svg>\n")


# The border, BORDER in from the icon's edge, the same distance all the way round. macOS's icon shape has straight sides
# and corners that curve smoothly out of them; each corner is close to a quarter of a superellipse,
# |x|^n + |y|^n = 1, of this n, CORNER (of the 1024) along each side. Measured from the shape macOS 26 draws the icon in.
BORDER = 56
CORNER = 312
SQUIRCLE = 2.42
# The cube's edges, the letters and the border are all lines this wide.
LINE = 8


def icon_shape(steps=90):
    """The icon's shape, clockwise from the top right corner's start."""
    lo, hi = 0, 1024
    points = []
    for (cx, cy), start in (((hi - CORNER, lo + CORNER), -90), ((hi - CORNER, hi - CORNER), 0),
                            ((lo + CORNER, hi - CORNER), 90), ((lo + CORNER, lo + CORNER), 180)):
        for k in range(steps + 1):
            t = math.radians(start + 90 * k / steps)
            c, s = math.cos(t), math.sin(t)
            points.append((cx + CORNER * math.copysign(abs(c) ** (2 / SQUIRCLE), c),
                           cy + CORNER * math.copysign(abs(s) ** (2 / SQUIRCLE), s)))
    return points


def inset(points, distance):
    """A clockwise closed line moved in by distance, each point along the line's normal there."""
    out = []
    for i, p in enumerate(points):
        a, b = points[i - 1], points[(i + 1) % len(points)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        # Clockwise on the screen (y down), the inside is to the right of the way the line goes.
        out.append((p[0] - dy / length * distance, p[1] + dx / length * distance))
    return out


def letter_shapes():
    return [shape for name in ("top", "left", "right") for shape in polygons(letter(name))]


def cut(points, shapes, gap, closed=False):
    """Path data for a line through points, with what is on or near the shapes left out."""
    pairs = list(zip(points, points[1:] + points[:1] if closed else points[1:]))
    return "".join(line([a, b]) for p0, p1 in pairs for a, b in outside(p0, p1, shapes, gap))


def guides():
    """The drawing's guides, faint: a grid, the cube's axes, circles round it, all stopping short of the letters, and a
    border."""
    letters = letter_shapes()
    body = []
    grid = [((k, 0), (k, 1024)) for k in range(64, 1024, 64)] + [((0, k), (1024, k)) for k in range(64, 1024, 64)]
    body.append(f'<path d="{"".join(cut([a, b], letters, 6) for a, b in grid)}" stroke="#fff" stroke-opacity=".07" stroke-width="2"/>')
    # The cube's three axes through its middle, at 30° and upright, to the canvas's edges.
    dx = 512 / COS30 * 0.5
    axes = [((0, 512 + dx), (1024, 512 - dx)), ((0, 512 - dx), (1024, 512 + dx)), ((512, 0), (512, 1024))]
    body.append(f'<path d="{"".join(cut([a, b], letters, 8) for a, b in axes)}" stroke="#fff" stroke-opacity=".18" stroke-width="3"/>')
    for r, opacity in ((EDGE, 0.32), (EDGE * COS30, 0.22), (EDGE / 2, 0.16)):
        circle = [(512 + r * math.cos(2 * math.pi * k / 240), 512 + r * math.sin(2 * math.pi * k / 240)) for k in range(240)]
        body.append(f'<path d="{cut(circle, letters, 8, closed=True)}" fill="none" stroke="#fff" stroke-opacity="{opacity}" stroke-width="3"/>')
    border = inset(icon_shape(), BORDER)
    body.append(f'<path d="{line(border, closed=True)}" fill="none" stroke="#fff" stroke-opacity=".9" stroke-width="{LINE}" stroke-linejoin="round"/>')
    return body


def cube():
    """The cube's lines: hidden edges dashed, the letters, then the edges over them."""
    corner = lambda k: (NEAR[0] + EDGE * math.cos(math.radians(90 + 60 * k)), NEAR[1] - EDGE * math.sin(math.radians(90 + 60 * k)))
    hexagon = [corner(k) for k in range(6)]  # from the top, round to the left
    body = []
    letters = letter_shapes()
    # The edges behind, from the far corner (which the near one hides) to the top and the two bottom corners, not
    # across the letters.
    for k in (0, 2, 4):
        for a, b in outside(NEAR, hexagon[k], letters, gap=14):
            body.append(f'<path d="{line([a, b])}" stroke="#fff" stroke-opacity=".55" stroke-width="5" '
                        'stroke-dasharray="18 14" stroke-linecap="round"/>')
    for name in ("top", "left", "right"):
        body.append(f'<path d="{letter(name)}" fill="#fff" fill-opacity=".12" stroke="#fff" stroke-width="{LINE}" stroke-linejoin="round"/>')
    # The edges in front: the outline, and from the near corner to the three others.
    body.append(f'<path d="{line(hexagon, closed=True)}" fill="none" stroke="#fff" stroke-width="{LINE}" stroke-linejoin="round"/>')
    for k in (1, 3, 5):
        body.append(f'<path d="{line([NEAR, hexagon[k]])}" stroke="#fff" stroke-width="{LINE}" stroke-linecap="round"/>')
    return body


def gradient(colors):
    srgb = lambda c: "srgb:" + ",".join(f"{v:.5f}" for v in (*(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5)), 1))
    return {"linear-gradient": [srgb(c) for c in colors],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def main():
    shutil.rmtree(TARGET, ignore_errors=True)
    (TARGET / "Assets").mkdir(parents=True)
    (TARGET / "Assets" / "beta-cube.svg").write_text(svg(cube()))
    (TARGET / "Assets" / "beta-guides.svg").write_text(svg(guides()))
    doc = {
        "fill-specializations": [{"value": gradient(BLUE[0])}, {"appearance": "dark", "value": gradient(BLUE[1])}],
        "groups": [
            {"name": "Cube", "layers": [{"name": "Cube", "image-name": "beta-cube.svg", "glass": True}],
             "shadow": {"kind": "neutral", "opacity": 0.35}, "specular": True,
             "translucency": {"enabled": False, "value": 0.5}},
            {"name": "Guides", "layers": [{"name": "Guides", "image-name": "beta-guides.svg", "glass": False}],
             "shadow": {"kind": "none", "opacity": 0.5}, "specular": False,
             "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (TARGET / "icon.json").write_text(json.dumps(doc, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
