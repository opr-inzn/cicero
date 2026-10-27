#!/usr/bin/env python3
"""Regenerates Sources/CiceroCore/Rendering/LetterOrder.swift, the order a font page's Glyphs lists Latin letters and
Greek and Cyrillic characters in, from GlyphsInfo, the glyph data of Glyphs by Georg Seifert, under the BSD 3-Clause
License (Resources/GlyphsInfo-LICENSE.txt): its glyph names, categories, subcategories, cases and scripts.

Run by hand when GlyphsInfo changes (Cicero itself never goes online):

    scripts/update-letter-order.py                         # downloads GlyphData.xml of the GlyphsInfo commit below
    scripts/update-letter-order.py path/to/GlyphData.xml

Characters go by category, letters, numbers, punctuation, symbols, then marks, the script's own first, then by case,
capitals first, and subcategory. Within those, Latin letters go by glyph name, as Glyphs' font view sorts them: those
with a suffix after the others, each in code point order, so names starting with a capital, like Bsmall for ʙ, come
first; and the letters in LATIN_AFTER after the letter they're read as, like Æ after the A's. Greek and Cyrillic
letters go by alphabet (see greek_place and cyrillic_place), other characters by code point.
"""

import re
import sys
import unicodedata
import urllib.request
from pathlib import Path

COMMIT = "b2a1b29202f7db4a2e70814715cf6c2d5bf489ce"
URL = f"https://raw.githubusercontent.com/schriftgestalt/GlyphsInfo/{COMMIT}/GlyphData.xml"
OUT = Path(__file__).resolve().parent.parent / "Sources" / "CiceroCore" / "Rendering" / "LetterOrder.swift"

CATEGORIES = ["Letter", "Number", "Separator", "Punctuation", "Symbol", "Mark"]
SUBCATEGORIES = {"Letter": ["", "Ligature", "Modifier"], "Number": ["Letter", ""], "Symbol": ["Modifier", "", "Math"],
                 "Mark": ["Nonspacing", "Spacing"]}
CASES = ["upper", "lower", "minor", ""]

# The blocks whose characters without a script in GlyphsInfo go with Greek and Cyrillic, like Cicero's groups, and the
# dotted grave and acute, which Unicode gives Greek.
BLOCKS = {
    "greek": [(0x370, 0x3FF), (0x1F00, 0x1FFF), (0x1DC0, 0x1DC1)],
    "cyrillic": [(0x400, 0x52F), (0x1C80, 0x1C8F), (0x2DE0, 0x2DFF), (0xA640, 0xA69F), (0x1E030, 0x1E08F)],
}

# Latin letters whose names don't say where they go: each run after the letter given, in the run's order, after
# that letter's accented forms and the letters named after it, like Æ Ǽ Ǣ after the A's and Ŋ after the N's.
LATIN_AFTER = [
    ("ÆǼǢ", "A"), ("æǽǣ", "a"), ("Ð", "D"), ("ð", "d"), ("Ə", "E"), ("əɚ", "e"), ("Ȝ", "G"), ("ȝ", "g"),
    ("ĳ", "i"), ("Ŋ", "N"), ("ŋ", "n"), ("Œ", "O"), ("œ", "o"), ("Þ", "P"), ("þ", "p"), ("ẞ", "S"), ("ßſ", "s"),
    ("Ꞌ", "Z"), ("ꞌ", "z"),
]
# Latin letters that go right after a letter, before its accented forms: the dotless i and j, and Ɣ, which looks like
# a V.
LATIN_NEXT = [("ı", "i"), ("ȷ", "j"), ("Ɣ", "V")]
# Names that don't follow the others of their kind: ɪ goes with the small capitals, named like ʙ's Bsmall.
LATIN_NAMES = {"icapitalsmall": "Ismall"}

GREEK_ALPHABET = "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρςστυφχψω"
CYRILLIC_ALPHABET = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя"
# Cyrillic letters that go right after a letter of the alphabet, in this order: Ѓ and Ukrainian's Ґ, then the other
# forms of Г; Ѝ and Ҋ after Й.
CYRILLIC_AFTER = [("ЃҐӶҒҔ", "Г"), ("ѓґӷғҕ", "г"), ("ЍҊ", "Й"), ("ѝҋ", "й")]

LATIN_PLACES = {letter: f"{base}~{index:02}" for run, base in LATIN_AFTER for index, letter in enumerate(run)}
LATIN_PLACES |= {letter: f"{base}\x01" for letter, base in LATIN_NEXT}
CYRILLIC_PLACES = {letter: (base, index) for run, base in CYRILLIC_AFTER for index, letter in enumerate(run)}


def read(argument):
    if argument:
        return Path(argument).read_text(encoding="utf-8")
    with urllib.request.urlopen(URL) as response:
        return response.read().decode("utf-8")


def glyphs(text):
    for line in text.splitlines():
        if "<glyph " in line and ' unicode="' in line:
            yield dict(re.findall(r'(\w+)="([^"]*)"', line))


def letter_base(character):
    """The letter Unicode takes a character apart into, like the Α of Ά, or the character itself."""
    return unicodedata.normalize("NFD", character)[0]


def greek_place(value):
    """Α to Ω, then the other letters of the Greek block with accents, then the block's other letters, like Ϙ and Ϲ,
    then Greek Extended's letter by letter, those with the iota subscript last. Lowercase the same."""
    character = chr(value)
    base = letter_base(character)
    if character in GREEK_ALPHABET:
        return (0, GREEK_ALPHABET.index(character), 0, value)
    if 0x370 <= value <= 0x3FF:
        return (1 if base in GREEK_ALPHABET else 2, 0, 0, value)
    if 0x1F00 <= value <= 0x1FFF and base in GREEK_ALPHABET:
        return (3, GREEK_ALPHABET.index(base), "\u0345" in unicodedata.normalize("NFD", character), value)
    return (4, 0, 0, value)


def cyrillic_place(value):
    """А to Я, each followed by the letters of the basic Cyrillic block that are it with an accent, like Ё after Е, and
    those CYRILLIC_AFTER puts after it; then the block's other letters, like Ђ, Є and Ѕ, then the others."""
    character = chr(value)
    if character in CYRILLIC_ALPHABET:
        return (0, CYRILLIC_ALPHABET.index(character), 0, value)
    if character in CYRILLIC_PLACES:
        base, index = CYRILLIC_PLACES[character]
        return (0, CYRILLIC_ALPHABET.index(base), 1 + index, value)
    base = letter_base(character)
    if 0x400 <= value <= 0x45F:
        return (0, CYRILLIC_ALPHABET.index(base), 99, value) if base in CYRILLIC_ALPHABET else (1, 0, 0, value)
    return (2, 0, 0, value)


def key(glyph, script):
    category, subcategory = glyph.get("category", ""), glyph.get("subCategory", "")
    subcategories = SUBCATEGORIES.get(category, [""])
    value = int(glyph["unicode"], 16)
    if script == "latin":
        name = LATIN_PLACES.get(chr(value)) or LATIN_NAMES.get(glyph["name"], glyph["name"])
        place = ("." in name, name)
    elif category == "Letter":
        place = (greek_place if script == "greek" else cyrillic_place)(value)
    else:
        place = (9, 0, 0, value)
    return (CATEGORIES.index(category) if category in CATEGORIES else len(CATEGORIES), glyph.get("script") != script,
            CASES.index(glyph.get("case", "")), subcategories.index(subcategory) if subcategory in subcategories else 9,
            place)


def members(data, script):
    """Latin's letters, but ligatures, which Cicero groups on their own; every Greek and Cyrillic character."""
    found = []
    for glyph in data:
        value = int(glyph["unicode"], 16)
        character = chr(value)
        if script == "latin":
            if unicodedata.category(character) not in ("Lu", "Ll", "Lt", "Lo") or glyph.get("subCategory") == "Ligature":
                continue
            if glyph.get("script") != "latin" and not unicodedata.name(character, "").startswith("LATIN "):
                continue
        elif glyph.get("script") != script and ("script" in glyph or not any(a <= value <= b for a, b in BLOCKS[script])):
            continue
        found.append(glyph)
    return sorted(found, key=lambda glyph: key(glyph, script))


def literal(glyph):
    character = chr(int(glyph["unicode"], 16))
    # Marks would join the character before them, or the indentation, in the source.
    return f"\\u{{{glyph['unicode'].lstrip('0')}}}" if unicodedata.category(character).startswith("M") else character


def lines(sorted_glyphs, script):
    """A line for each kind of character and, in Latin, first letter of the names, or in Greek and Cyrillic, part of
    the alphabet, at most 40 characters long."""
    out, previous = [], None
    for glyph in sorted_glyphs:
        place = key(glyph, script)
        line = place[:4] + ((place[4][1][0],) if script == "latin" else place[4][:1])
        if line != previous or len(out[-1]) >= 40:
            out.append([])
            previous = line
        out[-1].append(literal(glyph))
    return ["".join(characters) for characters in out]


def main():
    data = list(glyphs(read(sys.argv[1] if len(sys.argv) > 1 else None)))
    constants = [
        ("glyphsLatinOrder", "latin", "Latin letters: capitals, then lowercase letters, then those without case, each by\n"
         "    /// glyph name, so Á Ă Â Ä follow A, and Æ, Ð, Ŋ, Œ, Þ and ß after the letter they're read as."),
        ("glyphsGreekOrder", "greek", "Greek characters: capitals, then lowercase letters, each Α to Ω, then Ά Έ Ή Ί Ό Ύ Ώ Ϊ Ϋ,\n"
         "    /// then the archaic ones, then the polytonic ones letter by letter; then numbers, punctuation, symbols and accents."),
        ("glyphsCyrillicOrder", "cyrillic", "Cyrillic characters: capitals, then lowercase letters, each А to Я with\n"
         "    /// Ѓ Ґ after Г and Ѐ Ё after Е, then Ђ Є Ѕ І Ї Ј Љ Њ Ћ Џ, then the others; then punctuation, symbols and marks."),
    ]
    swift = [
        "// Generated by scripts/update-letter-order.py from GlyphsInfo, the glyph data of Glyphs by Georg Seifert (BSD",
        "// 3-Clause License, Resources/GlyphsInfo-LICENSE.txt). Don't edit by hand.",
        "",
        "extension GlyphSection {",
    ]
    for index, (constant, script, summary) in enumerate(constants):
        sorted_glyphs = members(data, script)
        swift += [
            *([""] if index else []),
            f"    /// {summary}",
            f'    static let {constant} = """',
            *(f"        {line}" for line in lines(sorted_glyphs, script)),
            '        """',
        ]
        print(f"{script}: {len(sorted_glyphs)} characters")
    swift += ["}", ""]
    OUT.write_text("\n".join(swift), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(OUT.parent.parent.parent.parent)}")


if __name__ == "__main__":
    main()
