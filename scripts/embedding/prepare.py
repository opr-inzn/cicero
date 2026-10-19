#!/usr/bin/env python3
"""Lists the Google Fonts families to learn letter embeddings from, and the styles of each to draw.

    python3 -I scripts/embedding/prepare.py ~/Downloads/cicero-training/google-fonts ~/Downloads/cicero-training/work [--other-scripts]

Takes a family only when its license file says OFL, Apache or UFL, and only families for Latin (no primary script
of another, unless --other-scripts: many draw Latin letters of their own, and train.py takes those that borrow
another family's as that family), without symbol fonts and Playwrite's Guides, which draw lines with the letters.

Of each it draws the upright and the italic styles from Light to Bold, a variable font at 300, 400, 500, 600 and 700
as far as its weight axis goes and at the normal width, whatever its default; a family with none of those weights,
the nearest to 400 it has. A variable font with a width axis is drawn narrower and wider too, at 300, 400 and 500:
extra condensed and condensed (62.5 and 75, or as narrow as it goes past 87.5) and expanded and extra expanded (125
and 150, or as wide as it goes past 112.5). One with an optical size axis is drawn at its own (its default) and,
also at 300, 400 and 500, at a small and a large one, 8 and 96 as far as the axis goes, when those are at least
twice apart. Writes manifest.json, the styles to draw (see render-letters.swift), and families.json: each family's
name, category, Google's tags and its entries in the manifest, with their weight, width, optical size (nil for its
own) and whether they're italic.
"""

import argparse
import csv
import json
import re
from pathlib import Path

LICENSES = {
    "ofl": ("OFL.txt", "SIL Open Font License"),
    "apache": ("LICENSE.txt", "Apache License"),
    "ufl": ("UFL.txt", "UBUNTU FONT LICENCE"),
}
WEIGHTS = [300, 400, 500, 600, 700]
NARROW, WIDE = [62.5, 75], [125, 150]
SMALL, LARGE = 8, 96


def parse_metadata(text):
    """A text-format protobuf as nested dicts; repeated fields as lists."""
    root, stack = {}, []
    current = root
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith("{"):
            child = {}
            current.setdefault(line[:-1].strip(), []).append(child)
            stack.append(current)
            current = child
        elif line == "}":
            current = stack.pop()
        else:
            match = re.match(r'(\w+):\s*(.*)$', line)
            if not match:
                continue
            key, value = match.groups()
            if value.startswith('"'):
                value = re.sub(r'\\(.)', r'\1', value[1:-1])
            else:
                try:
                    value = float(value) if "." in value else int(value)
                except ValueError:
                    pass
            current.setdefault(key, []).append(value)
    return root


def first(meta, key, default=None):
    values = meta.get(key)
    return values[0] if values else default


def licensed(directory, kind):
    name, says = LICENSES[kind]
    candidates = [directory / name] + ([directory / "LICENCE.txt"] if kind == "ufl" else [])
    return any(path.exists() and says.lower() in path.read_text(errors="ignore").lower() for path in candidates)


def axis_range(axes, tag):
    axis = next((axis for axis in axes if first(axis, "tag") == tag), None)
    return (first(axis, "min_value"), first(axis, "max_value")) if axis else None


def widths(axes):
    """The widths besides the normal one to draw a variable font at."""
    found = axis_range(axes, "wdth")
    if not found:
        return []
    low, high = found
    narrow = [width for width in NARROW if width >= low] or ([low] if low <= 87.5 else [])
    wide = [width for width in WIDE if width <= high] or ([high] if high >= 112.5 else [])
    return narrow + wide


def optical_sizes(axes):
    """The optical sizes besides its own to draw a variable font at."""
    found = axis_range(axes, "opsz")
    if not found:
        return []
    small, large = max(SMALL, found[0]), min(LARGE, found[1])
    return [small, large] if large >= small * 2 else []


def instances(fonts, axes, italic):
    """(file, variations, weight, width, optical size) for the styles to draw."""
    fonts = [font for font in fonts if (first(font, "style") == "italic") == italic]
    if not fonts:
        return []
    variable = [font for font in fonts if "[" in first(font, "filename", "")]
    if variable:
        file = first(variable[0], "filename")
        weight_range, width_range = axis_range(axes, "wght"), axis_range(axes, "wdth")
        normal = {"wdth": min(max(100, width_range[0]), width_range[1])} if width_range else {}
        if weight_range is None:
            return [(file, normal, first(variable[0], "weight", 400), 100, None)]
        low, high = weight_range
        weights = [weight for weight in WEIGHTS if low <= weight <= high] or [min(max(400, low), high)]
        found = [(file, {"wght": weight, **normal}, weight, 100, None) for weight in weights]
        if not italic:
            for width in widths(axes):
                found += [(file, {"wght": weight, "wdth": width}, weight, width, None) for weight in weights if weight <= 500]
            for size in optical_sizes(axes):
                found += [(file, {"wght": weight, "opsz": size, **normal}, weight, 100, size) for weight in weights if weight <= 500]
        return found
    statics = [(first(font, "filename"), {}, first(font, "weight", 400), 100, None) for font in fonts]
    return [entry for entry in statics if 300 <= entry[2] <= 700] or [min(statics, key=lambda entry: abs(entry[2] - 400))]


def tags(root):
    """Google's tags for each family, 0 to 1."""
    found = {}
    path = root / "tags" / "all" / "families.csv"
    with path.open(newline="") as file:
        for row in csv.reader(file):
            if len(row) != 4 or row[1]:
                continue
            family, _, tag, score = row
            try:
                found.setdefault(family, {})[tag] = float(score) / 100
            except ValueError:
                pass
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fonts")
    parser.add_argument("work")
    parser.add_argument("--other-scripts", action="store_true")
    arguments = parser.parse_args()
    root, out = Path(arguments.fonts).expanduser(), Path(arguments.work).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    tagged = tags(root)
    manifest, families, skipped = [], [], {}
    for kind in LICENSES:
        for directory in sorted((root / kind).iterdir()):
            meta_path = directory / "METADATA.pb"
            if not directory.is_dir() or not meta_path.exists():
                continue
            if not licensed(directory, kind):
                skipped["license"] = skipped.get("license", 0) + 1
                continue
            meta = parse_metadata(meta_path.read_text())
            script = first(meta, "primary_script")
            if script and script != "Latn" and not arguments.other_scripts:
                skipped["script"] = skipped.get("script", 0) + 1
                continue
            name = first(meta, "name")
            if "SYMBOLS" in meta.get("classifications", []) or name.endswith(" Guides"):
                skipped["symbols"] = skipped.get("symbols", 0) + 1
                continue
            fonts, axes = meta.get("fonts", []), meta.get("axes", [])
            entries = []
            for italic in (False, True):
                for file, variations, weight, width, size in instances(fonts, axes, italic):
                    path = directory / file
                    if not path.exists():
                        continue
                    entries.append({"row": len(manifest), "weight": weight, "width": width, "opsz": size, "italic": italic})
                    manifest.append({"file": str(path), "variations": variations})
            if not entries:
                continue
            families.append({
                "name": name,
                "directory": f"{kind}/{directory.name}",
                "category": first(meta, "category"),
                "classifications": meta.get("classifications", []),
                "stroke": first(meta, "stroke"),
                "tags": tagged.get(name, {}),
                "entries": entries,
            })
    (out / "manifest.json").write_text(json.dumps(manifest))
    (out / "families.json").write_text(json.dumps(families, indent=1))
    print(f"{len(families)} families, {len(manifest)} styles to draw; skipped {skipped}")


if __name__ == "__main__":
    main()
