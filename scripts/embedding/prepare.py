#!/usr/bin/env python3
"""Lists the Google Fonts families to learn letter embeddings from, and the styles of each to draw.

    python3 -I scripts/embedding/prepare.py ~/Downloads/cicero-training/google-fonts ~/Downloads/cicero-training/work [--other-scripts]

Takes a family only when its license file says OFL, Apache or UFL, and only families for Latin (no primary script
of another, unless --other-scripts: many draw Latin letters of their own, and train.py takes those that borrow
another family's as that family), without symbol fonts and Playwrite's Guides, which draw lines with the letters. Of each it draws the upright styles from Light to Bold, a variable font at 300, 400, 500, 600 and 700
as far as its weight axis goes, and one italic, the nearest to 400; a family with none of those in its range, the
nearest to 400 of what it has. Writes manifest.json, the styles to draw (see render-letters.swift), and
families.json: each family's name, category, Google's tags and its entries in the manifest.
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


def instances(fonts, axes, italic):
    """(file, variations, weight) for the styles to draw."""
    fonts = [font for font in fonts if (first(font, "style") == "italic") == italic]
    if not fonts:
        return []
    weight_axis = next((axis for axis in axes if first(axis, "tag") == "wght"), None)
    variable = [font for font in fonts if "[" in first(font, "filename", "")]
    if variable:
        file = first(variable[0], "filename")
        if weight_axis is None:
            return [(file, {}, first(variable[0], "weight", 400))]
        low, high = first(weight_axis, "min_value"), first(weight_axis, "max_value")
        weights = [weight for weight in WEIGHTS if low <= weight <= high] or [min(max(400, low), high)]
        if italic:
            weights = [min(weights, key=lambda weight: abs(weight - 400))]
        return [(file, {"wght": weight}, weight) for weight in weights]
    statics = [(first(font, "filename"), {}, first(font, "weight", 400)) for font in fonts]
    chosen = [entry for entry in statics if 300 <= entry[2] <= 700]
    if italic or not chosen:
        chosen = [min(chosen or statics, key=lambda entry: abs(entry[2] - 400))]
    return chosen


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
                for file, variations, weight in instances(fonts, axes, italic):
                    path = directory / file
                    if not path.exists():
                        continue
                    entries.append({"row": len(manifest), "weight": weight, "italic": italic})
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
