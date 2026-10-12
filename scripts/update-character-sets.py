#!/usr/bin/env python3
"""Regenerates Resources/CharacterSets.json, the built-in character sets Cicero checks fonts against.

Run by hand when a source changes: ./scripts/update-character-sets.py (Python 3.13 or later, whose
Unicode data matches the block list it downloads). It downloads the sources at the commits and
versions pinned below (Cicero itself never goes online), resolves sets that build on each other into
complete lists, and drops whitespace and invisible characters, which aren't what people mean by
character set support.

Sources:
- Latin S–XL by Christoph Koeberlin, MIT: https://github.com/koeberlin/Latin-Character-Sets
- Adobe Latin 1–5 by Adobe, MIT: https://github.com/adobe-type-tools/adobe-latin-charsets
- Google Fonts glyph sets, Apache 2.0: https://github.com/googlefonts/glyphsets
- Unicode blocks (the assigned, visible characters of each block), Unicode License v3:
  https://www.unicode.org/Public/<version>/ucd/Blocks.txt
"""

import json
import re
import unicodedata
import urllib.request
from datetime import date
from pathlib import Path

KOEBERLIN = "https://raw.githubusercontent.com/koeberlin/Latin-Character-Sets/78ba1aa04919f2409b7a35ea1526ac1f1cb59c92"
ADOBE = "https://raw.githubusercontent.com/adobe-type-tools/adobe-latin-charsets/3b8b7fc2d0cbc6cb56c55d68634ea6ac4a7ac8ac"
GOOGLE = "https://raw.githubusercontent.com/googlefonts/glyphsets/432104e3ecb119c44b3cc29d7209d7b54bf41017"
UNICODE = f"https://www.unicode.org/Public/{unicodedata.unidata_version}/ucd/Blocks.txt"

# Blocks type designers check coverage of. Ideograph blocks, private use and the like aren't useful
# as "has every character" filters.
BLOCKS = [
    "Basic Latin", "Latin-1 Supplement", "Latin Extended-A", "Latin Extended-B", "Latin Extended Additional",
    "Latin Extended-C", "Latin Extended-D", "Latin Extended-E", "IPA Extensions", "Spacing Modifier Letters",
    "Combining Diacritical Marks", "Greek and Coptic", "Greek Extended", "Cyrillic", "Cyrillic Supplement",
    "Cyrillic Extended-A", "Cyrillic Extended-B", "Armenian", "Hebrew", "Arabic", "Devanagari", "Thai", "Georgian",
    "General Punctuation", "Superscripts and Subscripts", "Currency Symbols", "Letterlike Symbols", "Number Forms",
    "Arrows", "Mathematical Operators", "Miscellaneous Technical", "Enclosed Alphanumerics", "Box Drawing",
    "Block Elements", "Geometric Shapes", "Miscellaneous Symbols", "Dingbats", "Alphabetic Presentation Forms",
]

ROOT = Path(__file__).resolve().parent.parent


def fetch(url):
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")


def koeberlin(name):
    return {int(token, 16) for token in fetch(f"{KOEBERLIN}/CharacterSets/Universal/{name}_hex.txt").split()}


def adobe(name):
    rows = fetch(f"{ADOBE}/{name}.txt").splitlines()[1:]
    return {int(row.split("\t")[0], 16) for row in rows if re.match(r"^[0-9A-Fa-f]{4,6}\t", row)}


def google(name):
    text = fetch(f"{GOOGLE}/Lib/glyphsets/results/nam/{name}.nam")
    return {int(match, 16) for match in re.findall(r"^0x([0-9A-Fa-f]+)", text, re.M)}


def unicode_blocks():
    ranges = {}
    for line in fetch(UNICODE).splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        span, name = (part.strip() for part in line.split(";"))
        low, high = (int(bound, 16) for bound in span.split(".."))
        ranges[name] = range(low, high + 1)
    missing = [name for name in BLOCKS if name not in ranges]
    assert not missing, f"Unknown blocks: {missing}"
    def assigned(block):
        return {value for value in ranges[block] if unicodedata.category(chr(value)) not in ("Cn", "Co", "Cs")}
    return [(slug(name), name, f"Every character in the {name} block (U+{ranges[name].start:04X}–U+{ranges[name].stop - 1:04X}).", assigned(name)) for name in BLOCKS]


def slug(name):
    return "unicode-" + re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def visible(scalars):
    def keep(value):
        char = chr(value)
        return not char.isspace() and unicodedata.category(char) not in ("Cc", "Cf", "Zs", "Zl", "Zp")
    return sorted(filter(keep, scalars))


def main():
    latin_s = koeberlin("LatinS")
    latin_m = latin_s | koeberlin("LatinM")
    latin_l = latin_m | koeberlin("LatinL")
    latin_xl = latin_l | koeberlin("LatinXL")

    gf_core = google("GF_Latin_Core")  # already includes Kernel
    gf_greek_core = google("GF_Greek_Core")
    gf_greek_plus = gf_greek_core | google("GF_Greek_Plus")

    groups = [
        {
            "id": "koeberlin",
            "name": "Latin S–XL",
            "credit": "Latin Character Sets by Christoph Koeberlin",
            "url": "https://github.com/koeberlin/Latin-Character-Sets",
            "sets": [
                ("latin-s", "Latin S", "A global Latin minimum: Europe plus about 100 more languages, including the Pan-Nigerian alphabet.", latin_s),
                ("latin-m", "Latin M", "Latin S plus Vietnamese and DIN 91379.", latin_m),
                ("latin-l", "Latin L", "Latin M plus Pan-African Latin and indigenous languages of the Americas.", latin_l),
                ("latin-xl", "Latin XL", "Latin L plus IPA and Americanist phonetic notation.", latin_xl),
            ],
        },
        {
            "id": "adobe",
            "name": "Adobe Latin",
            "credit": "Adobe Latin Character Sets by Adobe",
            "url": "https://github.com/adobe-type-tools/adobe-latin-charsets",
            "sets": [
                ("adobe-latin-1", "Adobe Latin 1", "Western European languages.", adobe("adobe-latin-1")),
                ("adobe-latin-2", "Adobe Latin 2", "Adobe Latin 1 plus common symbols; the minimum for Std fonts.", adobe("adobe-latin-2")),
                ("adobe-latin-3", "Adobe Latin 3", "Adds Central European languages; the minimum for Pro fonts.", adobe("adobe-latin-3")),
                ("adobe-latin-4", "Adobe Latin 4", "Adds Vietnamese and many more European, African and Pacific languages.", adobe("adobe-latin-4-precomposed")),
                ("adobe-latin-5", "Adobe Latin 5", "Adds more African and Berber languages, Navajo and others.", adobe("adobe-latin-5-precomposed")),
            ],
        },
        {
            "id": "google",
            "name": "Google Fonts",
            "credit": "Google Fonts glyph sets",
            "url": "https://github.com/googlefonts/glyphsets",
            "sets": [
                ("gf-latin-kernel", "GF Latin Kernel", "Basic Latin letters, figures and punctuation.", google("GF_Latin_Kernel")),
                ("gf-latin-core", "GF Latin Core", "Latin languages of Europe and the Americas with more than 5 million speakers.", gf_core),
                ("gf-latin-plus", "GF Latin Plus", "Latin Core and Vietnamese plus currencies, math and fractions.", gf_core | google("GF_Latin_Vietnamese") | google("GF_Latin_Plus")),
                ("gf-latin-african", "GF Latin African", "Latin Core plus African languages.", gf_core | google("GF_Latin_African")),
                ("gf-cyrillic-core", "GF Cyrillic Core", "Cyrillic languages with more than 3 million speakers.", google("GF_Cyrillic_Core")),
                ("gf-cyrillic-plus", "GF Cyrillic Plus", "Adds Cyrillic languages with 240,000 to 3 million speakers.", google("GF_Cyrillic_Plus")),
                ("gf-cyrillic-pro", "GF Cyrillic Pro", "Adds non-Slavic Cyrillic languages.", google("GF_Cyrillic_Pro")),
                ("gf-greek-core", "GF Greek Core", "Monotonic Modern Greek.", gf_greek_core),
                ("gf-greek-plus", "GF Greek Plus", "Adds polytonic Greek.", gf_greek_plus),
                ("gf-greek-pro", "GF Greek Pro", "Adds extended polytonic Greek for scholarly editions.", gf_greek_plus | google("GF_Greek_Pro")),
            ],
        },
    ]

    groups.append({
        "id": "unicode",
        "name": "Unicode Blocks",
        "credit": f"Unicode {unicodedata.unidata_version} block list by the Unicode Consortium",
        "url": "https://www.unicode.org/charts/",
        "sets": unicode_blocks(),
    })

    lines = ["{", f'  "generated": "{date.today().isoformat()}",', '  "groups": [']
    for g, group in enumerate(groups):
        lines.append("    {")
        for key in ("id", "name", "credit", "url"):
            lines.append(f"      {json.dumps(key)}: {json.dumps(group[key], ensure_ascii=False)},")
        lines.append('      "sets": [')
        for s, (set_id, name, summary, scalars) in enumerate(group["sets"]):
            entry = {"id": set_id, "name": name, "summary": summary, "scalars": visible(scalars)}
            comma = "," if s < len(group["sets"]) - 1 else ""
            lines.append(f"        {json.dumps(entry, ensure_ascii=False, separators=(',', ':'))}{comma}")
        lines.append("      ]")
        lines.append("    }" + ("," if g < len(groups) - 1 else ""))
    lines += ["  ]", "}", ""]
    out = ROOT / "Resources" / "CharacterSets.json"
    out.write_text("\n".join(lines), encoding="utf-8")
    for group in groups:
        for set_id, name, _, scalars in group["sets"]:
            print(f"{name}: {len(visible(scalars))} characters")
    print(f"Wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
