#!/usr/bin/env python3
"""Draws Cicero's icon: an isometric cube with C, 1 and 6 from AM Gaonkar Display Medium cut into its
left, top and right faces.

Each letter is a hole as deep as DEPTH, its floor the letter moved straight into the cube along the
face's normal, and its walls, the sides of the hole that face the viewer, shaded by the way they face
the light and darkening as they go down. Writes the layers of Resources/AppIcon.icon, whose icon.json colours the faces and floors
(the walls bring their own), and, with --web, the website's icon.svg and Mark.astro too.

    scripts/make-icon.py path/to/AMGaonkar-Display-Medium.otf [--web path/to/cicero-website] [--preview out.svg]

Needs fontTools and pyclipper (pip3 install fonttools pyclipper).
"""

import argparse
import math
from pathlib import Path

import pyclipper
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

ASSETS = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.icon" / "Assets"

# The cube, in a 1024 canvas: the near corner at NEAR, an edge EDGE long, seen corner on.
NEAR = (512.0, 505.0)
EDGE = 345.0
COS30 = math.cos(math.radians(30))


def project(p):
    """World (x, y, z), the cube [0, 1]³ with its near corner at (1, 1, 1), to canvas pixels."""
    x, y, z = p
    return (
        NEAR[0] + EDGE * COS30 * ((1 - x) - (1 - y)),
        NEAR[1] + EDGE * 0.5 * ((x - 1) + (y - 1)) - EDGE * (z - 1),
    )


def add(a, b, s=1.0):
    return tuple(ai + s * bi for ai, bi in zip(a, b))


def dot(a, b):
    return sum(ai * bi for ai, bi in zip(a, b))


def unit(a):
    n = math.sqrt(dot(a, a))
    return tuple(ai / n for ai in a)


TOWARD_VIEWER = unit((1, 1, 1))
LIGHT = unit((1.25, 0.35, 1.6))

# A face: the corner its letter's (0, 0) sits at, the letter's right and up, and its outward normal.
# Right × up is the normal, so no letter is mirrored. The top's letter reads from the left face.
FACES = {
    "left": dict(glyph="C", origin=(1, 0, 0), right=(0, 1, 0), up=(0, 0, 1), normal=(1, 0, 0)),
    "top": dict(glyph="one", origin=(1, 0, 1), right=(0, 1, 0), up=(-1, 0, 0), normal=(0, 0, 1)),
    "right": dict(glyph="six", origin=(1, 1, 0), right=(-1, 0, 0), up=(0, 0, 1), normal=(0, 1, 0)),
}

# Cap height as a share of an edge, and how deep the letters are cut, also as a share of an edge.
CAP = 0.64
DEPTH = 0.04

# How far a wall goes toward its floor's colour at the bottom.
OCCLUSION = 0.7

# Per face: the floor, and the darkest and lightest a wall can be at its top (sRGB).
COLORS = {
    "top": dict(floor="#3D0904", dark=(0x5A, 0x10, 0x08), light=(0xB4, 0x30, 0x1E)),
    "left": dict(floor="#050A3A", dark=(0x0A, 0x14, 0x60), light=(0x22, 0x3A, 0xBC)),
    "right": dict(floor="#06300B", dark=(0x0C, 0x4A, 0x14), light=(0x30, 0x94, 0x38)),
}


class ContourPen(BasePen):
    """Collects a glyph's contours as lists of segments: ("L", p0, p1) or ("C", p0, c1, c2, p1)."""

    def __init__(self, glyphSet):
        super().__init__(glyphSet)
        self.contours = []

    def _moveTo(self, p):
        self.contours.append([])
        self.start = self.last = p

    def _lineTo(self, p):
        self.contours[-1].append(("L", self.last, p))
        self.last = p

    def _curveToOne(self, c1, c2, p):
        self.contours[-1].append(("C", self.last, c1, c2, p))
        self.last = p

    def _closePath(self):
        if self.last != self.start:
            self._lineTo(self.start)

    _endPath = _closePath


def flatten(contour, tolerance, longest):
    """A contour's points, its curves cut into lines no further than tolerance from them nor longer than longest."""
    points = [contour[0][1]]

    def cubic(p0, c1, c2, p1, depth=0):
        # Distance of the control points from the chord bounds the curve's.
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy) or 1e-9
        d1 = abs((c1[0] - p0[0]) * dy - (c1[1] - p0[1]) * dx) / length
        d2 = abs((c2[0] - p0[0]) * dy - (c2[1] - p0[1]) * dx) / length
        if depth > 12 or (max(d1, d2) * 0.75 <= tolerance and length <= longest):
            points.append(p1)
            return
        m = lambda a, b: ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        p01, p12, p23 = m(p0, c1), m(c1, c2), m(c2, p1)
        p012, p123 = m(p01, p12), m(p12, p23)
        mid = m(p012, p123)
        cubic(p0, p01, p012, mid, depth + 1)
        cubic(mid, p123, p23, p1, depth + 1)

    for segment in contour:
        if segment[0] == "L":
            p0, p1 = segment[1], segment[2]
            steps = max(1, math.ceil(math.hypot(p1[0] - p0[0], p1[1] - p0[1]) / longest))
            for i in range(1, steps + 1):
                t = i / steps
                points.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
        else:
            cubic(*segment[1:])
    if points[-1] == points[0]:
        points.pop()
    return points


UNITS = 1000  # pyclipper works in whole numbers: thousandths of a pixel


def clip(operation, subject, clipper=()):
    c = pyclipper.Pyclipper()
    c.AddPaths(subject, pyclipper.PT_SUBJECT, True)
    if clipper:
        c.AddPaths(clipper, pyclipper.PT_CLIP, True)
    return c.Execute(operation, pyclipper.PFT_NONZERO, pyclipper.PFT_NONZERO)


def signed_area(points):
    return sum(points[i - 1][0] * p[1] - p[0] * points[i - 1][1] for i, p in enumerate(points)) / 2


def inside(point, polygon):
    x, y = point
    hit = False
    for i, (x1, y1) in enumerate(polygon):
        x0, y0 = polygon[i - 1]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def fmt(v, places=2):
    s = f"{v:.{places}f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def path_data(contours, to_canvas, offset=(0, 0), places=2):
    """SVG path data for contours of segments, mapped to the canvas and moved by offset."""
    out = []
    for contour in contours:
        p = add(to_canvas(contour[0][1]), offset)
        out.append(f"M{fmt(p[0], places)} {fmt(p[1], places)}")
        for segment in contour:
            pts = [add(to_canvas(q), offset) for q in segment[2:]]
            if segment[0] == "L":
                out.append(f"L{fmt(pts[0][0], places)} {fmt(pts[0][1], places)}")
            else:
                out.append("C" + " ".join(f"{fmt(q[0], places)} {fmt(q[1], places)}" for q in pts))
        out.append("Z")
    return "".join(out)


def hex_color(rgb):
    return "#" + "".join(f"{round(max(0, min(255, c))):02X}" for c in rgb)


def mix(a, b, t):
    # In linear light, so the middle of a wall's range isn't muddy.
    lin = lambda c: ((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92
    srgb = lambda c: 255 * (1.055 * c ** (1 / 2.4) - 0.055 if c > 0.0031308 else 12.92 * c)
    return tuple(srgb(lin(x) + (lin(y) - lin(x)) * t) for x, y in zip(a, b))


def face_corners(face):
    o, r, u = face["origin"], face["right"], face["up"]
    return [project(add(add(o, r, a), u, b)) for a, b in ((0, 0), (1, 0), (1, 1), (0, 1))]


def build(font_path, longest=2.5, places=2, shades=32, bands=12):
    """The layers: walls in pieces no longer than longest pixels, in that many shades and bands of depth, to places decimals."""
    font = TTFont(font_path)
    glyphs = font.getGlyphSet()
    cap = font["OS/2"].sCapHeight
    scale = CAP / cap  # font units to face units
    pixel = scale * EDGE  # roughly, canvas pixels per font unit

    layers = {}
    for name, face in FACES.items():
        pen = ContourPen(glyphs)
        glyphs[face["glyph"]].draw(pen)
        contours = pen.contours
        xs = [q[0] for c in contours for s in c for q in s[1:]]
        # Centred on the face: across on the outline's extremes, up and down on the cap height.
        cx = (min(xs) + max(xs)) / 2
        cy = cap / 2

        def to_world(q, face=face, cx=cx, cy=cy):
            a = 0.5 + (q[0] - cx) * scale
            b = 0.5 + (q[1] - cy) * scale
            return add(add(face["origin"], face["right"], a), face["up"], b)

        to_canvas = lambda q, to_world=to_world: project(to_world(q))
        inward = tuple(-n * DEPTH for n in face["normal"])
        depth = (project(inward)[0] - project((0, 0, 0))[0], project(inward)[1] - project((0, 0, 0))[1])
        along = unit(depth)

        # Flattened outlines, each turned so the letter, the hole, is on its left.
        polygons = [flatten(c, 0.04 / pixel, longest / pixel) for c in contours]
        for i, polygon in enumerate(polygons):
            nesting = sum(inside(polygon[0], other) for j, other in enumerate(polygons) if j != i)
            if (signed_area(polygon) > 0) != (nesting % 2 == 0):
                polygon.reverse()

        edges = []
        colors = COLORS[name]
        for polygon in polygons:
            for i, b in enumerate(polygon):
                a = polygon[i - 1]
                du, dv = b[0] - a[0], b[1] - a[1]
                if du == 0 and dv == 0:
                    continue
                # The wall's normal points into the hole, away from the cube's material.
                normal = unit(add(tuple(-dv * r for r in face["right"]), face["up"], du))
                if dot(normal, TOWARD_VIEWER) <= 1e-6:
                    continue
                pa, pb = to_canvas(a), to_canvas(b)
                light = round((0.18 + 0.82 * max(0.0, dot(normal, LIGHT))) * shades) / shades
                # Of two walls on one line of sight into the hole, the one met first lies further along it.
                key = dot(((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2), along)
                edges.append((key, light, pa, pb))
        # Nearest first, so each wall keeps only what no nearer one hides.
        edges.sort(key=lambda e: -e[0])
        floor_rgb = tuple(int(colors["floor"][i:i + 2], 16) for i in (1, 3, 5))
        wall_paths = []
        # The walls darken as they go down, which tells a wall seen through a narrow gap from the edge in
        # front of it. The walls down to each depth, the deepest first, each band drawn over the one below:
        # a point shows the band of the depth where its line of sight first meets a wall.
        for band in range(bands, 0, -1):
            reach = band / bands
            shadow = OCCLUSION * ((band - 0.5) / bands) ** 1.3
            covered, shaded = [], {}
            for _, light, pa, pb in edges:
                color = hex_color(mix(mix(colors["dark"], colors["light"], light), floor_rgb, shadow))
                quad = [pa, pb, add(pb, depth, reach), add(pa, depth, reach)]
                quad = [(round(x * UNITS), round(y * UNITS)) for x, y in quad]
                shaded.setdefault(color, []).extend(clip(pyclipper.CT_DIFFERENCE, [quad], covered) if covered else [quad])
                covered = clip(pyclipper.CT_UNION, covered + [quad])
            for color, pieces in shaded.items():
                # A little larger, so no seam shows between shades.
                offset = pyclipper.PyclipperOffset()
                offset.AddPaths(clip(pyclipper.CT_UNION, pieces), pyclipper.JT_MITER, pyclipper.ET_CLOSEDPOLYGON)
                region = offset.Execute(0.3 * UNITS)
                if region:
                    wall_paths.append((color, "".join(
                        "M" + "L".join(f"{fmt(x / UNITS, places)} {fmt(y / UNITS, places)}" for x, y in ring) + "Z" for ring in region)))

        corners = face_corners(face)
        outline = "M" + "L".join(f"{fmt(p[0])} {fmt(p[1])}" for p in corners) + "Z"
        letter = path_data(contours, to_canvas, places=places)
        layers[name] = dict(
            face=outline + letter,
            floor=path_data(contours, to_canvas, depth, places),
            walls=wall_paths,
            floor_color=colors["floor"],
        )
    return layers


def svg(body, view="0 0 1024 1024", size=True):
    dims = ' width="1024" height="1024"' if size else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg"{dims} viewBox="{view}">{body}</svg>\n'


GLOSS = {"top": 0.42, "left": 0.32, "right": 0.24}


def gloss_gradient(opacity, id="g"):
    return (f'<radialGradient id="{id}" cx=".2" cy=".15" r=".9"><stop offset="0" stop-color="#fff" stop-opacity="{opacity}"/>'
            f'<stop offset=".6" stop-color="#fff" stop-opacity="0"/></radialGradient>')


EDGES = ('<path d="M810.78 332.50L810.78 677.50L512.00 850.00L213.22 677.50L213.22 332.50" fill="none" stroke="#fff" stroke-opacity=".28" stroke-width="4" stroke-linejoin="round"/>'
         '<path d="M213.22 332.50L512.00 160.00L810.78 332.50M213.22 332.50L512.00 505.00L810.78 332.50M512.00 505.00L512.00 850.00" fill="none" stroke="#fff" stroke-opacity=".8" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>')

SHADOW = ('<defs><radialGradient id="g" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#000" stop-opacity=".34"/>'
          '<stop offset=".55" stop-color="#000" stop-opacity=".16"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient></defs>'
          '<ellipse cx="530" cy="868.00" rx="360" ry="70" fill="url(#g)"/>')


def write_assets(layers):
    for name, layer in layers.items():
        (ASSETS / f"{name}-face.svg").write_text(svg(f'<path d="{layer["face"]}" fill-rule="evenodd"/>'))
        (ASSETS / f"{name}-floor.svg").write_text(svg(f'<path d="{layer["floor"]}"/>'))
        (ASSETS / f"{name}-wall.svg").write_text(svg("".join(f'<path fill="{c}" d="{d}"/>' for c, d in layer["walls"])))
        (ASSETS / f"{name}-gloss.svg").write_text(svg(
            f'<defs>{gloss_gradient(GLOSS[name])}</defs><path d="{layer["face"]}" fill-rule="evenodd" fill="url(#g)"/>'))
    (ASSETS / "edges.svg").write_text(svg(EDGES))
    (ASSETS / "shadow.svg").write_text(svg(SHADOW))


# The faces' gradients, light and dark, as in icon.json.
GRADIENTS = {
    "top": (("#FF8A70", "#E8432C"), ("#F0644C", "#B12A1B"), (160, 505)),
    "left": (("#5B80FF", "#1D36DA"), ("#4060F0", "#16228F"), (332.5, 850)),
    "right": (("#86F271", "#30B142"), ("#52CF48", "#1D7424"), (332.5, 850)),
}


def flat(layers, prefix="", dark_classes=False):
    """The whole cube as one SVG body, as the website draws it."""
    defs, body = [], []
    for name in ("top", "left", "right"):
        (l0, l1), _, (y1, y2) = GRADIENTS[name]
        c0 = f' class="{name}0"' if dark_classes else ""
        c1 = f' class="{name}1"' if dark_classes else ""
        defs.append(f'<linearGradient id="{prefix}{name}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
                    f'<stop offset="0" stop-color="{l0}"{c0}/><stop offset="1" stop-color="{l1}"{c1}/></linearGradient>')
        defs.append(gloss_gradient(GLOSS[name], f"{prefix}{name}-gloss"))
    for name in ("top", "left", "right"):
        layer = layers[name]
        body.append(f'<path fill="{layer["floor_color"]}" d="{layer["floor"]}"/>')
        body.extend(f'<path fill="{c}" d="{d}"/>' for c, d in layer["walls"])
        body.append(f'<path fill="url(#{prefix}{name})" fill-rule="evenodd" d="{layer["face"]}"/>')
        body.append(f'<path fill="url(#{prefix}{name}-gloss)" fill-rule="evenodd" d="{layer["face"]}"/>')
    body.append(EDGES)
    return "\n  <defs>" + "".join(defs) + "</defs>\n  " + "\n  ".join(body) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("font")
    parser.add_argument("--web")
    parser.add_argument("--preview")
    args = parser.parse_args()
    layers = build(args.font)
    write_assets(layers)
    view = "209.2 156 605.6 698"
    if args.preview:
        Path(args.preview).write_text(svg('<rect x="0" y="0" width="1024" height="1024" fill="#fff"/>' + flat(layers)))
    if args.web:
        # Drawn at most a few dozen pixels wide, so in fewer pieces, and the walls in one band.
        layers = build(args.font, longest=8, places=1, shades=8, bands=1)
        web = Path(args.web)
        dark = "".join(f".{n}0{{stop-color:{GRADIENTS[n][1][0]}}}.{n}1{{stop-color:{GRADIENTS[n][1][1]}}}" for n in ("top", "left", "right"))
        (web / "public" / "icon.svg").write_text(svg(
            f"<style>@media (prefers-color-scheme: dark) {{ {dark} }}</style>" + flat(layers, dark_classes=True), view, size=False))
        mark = flat(layers, prefix="mark-")
        (web / "src" / "components" / "Mark.astro").write_text(
            "---\nconst { class: className } = Astro.props;\n---\n"
            f'<svg class={{className}} viewBox="{view}" aria-hidden="true">{mark}</svg>\n')


if __name__ == "__main__":
    main()
