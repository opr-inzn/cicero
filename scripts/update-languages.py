#!/usr/bin/env python3
"""
Regenerates Resources/Languages.json, Languages-LICENSE.txt and Languages-README.txt from
Rosetta's Hyperglot database (https://github.com/rosettatype/hyperglot). Run by hand when a new
Hyperglot release is out, then commit the three files:

    scripts/update-languages.py                 # newest hyperglot from PyPI
    scripts/update-languages.py --hyperglot 0.8.1
    scripts/update-languages.py --python /opt/homebrew/bin/python3.13

Hyperglot needs Python 3.11 or newer (`brew install python@3.13`). The script makes its own venv
in .build/update-languages-venv, installs hyperglot there and re-runs itself inside it. This is the
only place Point ever touches the network; the app itself reads the bundled JSON and nothing else.

What gets exported, using Hyperglot's own API so the resolution matches its checker exactly:
- every language Hyperglot would consider by default (validity "draft" or better), with the
  orthographies it checks by default: "primary" ones, with `preferred_as_group` orthographies merged
  the way `Language.get_check_orthographies` merges them;
- per orthography the resolved (inheritance expanded, NFC) encoded characters and the marks that
  cannot be derived from them, split the way `check_coverage` uses them:
    base ∪ marks                         -> what "supported" needs (check=base)
    auxiliary ∪ marks ∪ auxiliaryMarks   -> what "fully supported" adds (check=base,auxiliary)
Orthographies with no base characters are left out since nothing can be checked against them.
Shaping checks (mark attachment, Arabic joining, Indic conjuncts) need HarfBuzz and are not part of
this data; Point only checks character coverage.
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(REPO, "Resources")
VENV = os.path.join(REPO, ".build", "update-languages-venv")
HYPERGLOT_URL = "https://github.com/rosettatype/hyperglot"
MIN_PYTHON = (3, 11)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--hyperglot", metavar="VERSION", help="hyperglot version to install (default: newest)")
    parser.add_argument("--python", metavar="PATH", help="Python 3.11+ to build the venv with")
    parser.add_argument("--in-venv", action="store_true", help=argparse.SUPPRESS)
    return parser.parse_args()


# MARK: - Bootstrap

def find_python(preferred):
    candidates = [preferred] if preferred else []
    candidates += ["python3.14", "python3.13", "python3.12", "python3.11", "python3"]
    for candidate in candidates:
        path = shutil.which(candidate) if not os.path.sep in candidate else candidate
        if not path or not os.path.exists(path):
            continue
        try:
            out = subprocess.check_output([path, "-c", "import sys; print(sys.version_info[0], sys.version_info[1])"], text=True)
            major, minor = (int(x) for x in out.split())
        except (subprocess.CalledProcessError, ValueError):
            continue
        if (major, minor) >= MIN_PYTHON:
            return path
    sys.exit("No Python %d.%d or newer found. Install one (brew install python@3.13) or pass --python." % MIN_PYTHON)


def bootstrap(args):
    python = find_python(args.python)
    spec = "hyperglot" + (f"=={args.hyperglot}" if args.hyperglot else "")
    print(f"Creating {VENV} with {python}")
    shutil.rmtree(VENV, ignore_errors=True)
    subprocess.check_call([python, "-m", "venv", VENV])
    pip = os.path.join(VENV, "bin", "python")
    subprocess.check_call([pip, "-m", "pip", "install", "--quiet", "--upgrade", "pip"])
    print(f"Installing {spec}")
    subprocess.check_call([pip, "-m", "pip", "install", "--quiet", "--upgrade", spec])
    os.execv(pip, [pip, os.path.abspath(__file__), "--in-venv"] + sys.argv[1:])


# MARK: - Export

def export():
    import hyperglot
    from hyperglot import Languages, OrthographyStatus
    from hyperglot.parse import list_unique

    # Hyperglot writes a pickle cache into the working directory; keep it out of the repo.
    os.chdir(tempfile.mkdtemp(prefix="update-languages-"))

    languages = Languages()  # Hyperglot's defaults: validity >= draft, Rosetta macrolanguage model
    rows = []
    skipped_empty = 0
    for iso in sorted(languages.keys()):
        lang = languages[iso]
        orthographies = []
        for ort in lang.get_check_orthographies([OrthographyStatus.PRIMARY.value]):
            base = [c for c in ort.base_chars if c]
            if not base:
                skipped_empty += 1
                continue
            base_marks = ort.required_base_marks
            aux_marks = [m for m in ort.required_auxiliary_marks if m not in base_marks]
            row = {"script": ort.script, "scriptCode": ort["script_iso"], "base": "".join(list_unique(base))}
            if base_marks:
                row["marks"] = "".join(base_marks)
            aux = [c for c in ort.auxiliary_chars if c and c not in base]
            if aux:
                row["auxiliary"] = "".join(list_unique(aux))
            if aux_marks:
                row["auxiliaryMarks"] = "".join(aux_marks)
            autonym = (ort["autonym"] or "").strip()
            if autonym and autonym != (lang.autonym or "").strip():
                row["autonym"] = autonym
            orthographies.append(row)
        if not orthographies:
            continue
        row = {"iso": iso, "name": lang.name, "speakers": lang.speakers, "validity": lang.validity, "status": lang.status}
        if lang.autonym:
            row["autonym"] = lang.autonym.strip()
        row["orthographies"] = orthographies
        rows.append(row)

    version = hyperglot.__version__
    today = datetime.date.today().isoformat()
    header = {
        "source": "Hyperglot",
        "version": version,
        "url": HYPERGLOT_URL,
        "license": "Apache-2.0",
        "generated": today,
        "defaults": {"validity": "draft", "orthography": "primary", "check": "base"},
    }
    os.makedirs(RESOURCES, exist_ok=True)
    with open(os.path.join(RESOURCES, "Languages.json"), "w", encoding="utf-8") as f:
        # One language per line keeps diffs between versions readable.
        f.write("{\n")
        for key, value in header.items():
            f.write(f"{json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},\n")
        f.write('"languages": [\n')
        for i, row in enumerate(rows):
            f.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            f.write(",\n" if i < len(rows) - 1 else "\n")
        f.write("]\n}\n")

    license_src = None
    dist = os.path.dirname(hyperglot.__file__)
    for candidate in [
        os.path.join(os.path.dirname(dist), f"hyperglot-{version}.dist-info", "licenses", "LICENSE"),
        os.path.join(os.path.dirname(dist), f"hyperglot-{version}.dist-info", "LICENSE"),
    ]:
        if os.path.exists(candidate):
            license_src = candidate
            break
    if license_src is None:
        sys.exit("Could not find the license text in the installed hyperglot package.")
    shutil.copyfile(license_src, os.path.join(RESOURCES, "Languages-LICENSE.txt"))

    with open(os.path.join(RESOURCES, "Languages-README.txt"), "w", encoding="utf-8") as f:
        f.write(
            f"Languages.json is generated from Hyperglot {version} by Rosetta Type\n"
            f"({HYPERGLOT_URL}), a database of the characters each language's orthography needs.\n"
            f"Hyperglot is licensed under the Apache License 2.0; see Languages-LICENSE.txt.\n"
            f"\n"
            f"Point uses it to work out which languages a font supports, checking character coverage\n"
            f"only (no shaping checks). Generated on {today} by scripts/update-languages.py; do not\n"
            f"edit by hand.\n"
        )

    print(f"Wrote {len(rows)} languages from hyperglot {version} to Resources/Languages.json"
          + (f" ({skipped_empty} empty orthographies skipped)" if skipped_empty else ""))


def main():
    args = parse_args()
    try:
        import hyperglot  # noqa: F401
    except ImportError:
        if args.in_venv:
            sys.exit("hyperglot is not importable inside the venv; delete .build/update-languages-venv and retry.")
        bootstrap(args)
        return
    if args.hyperglot and not args.in_venv:
        import hyperglot
        if hyperglot.__version__ != args.hyperglot:
            sys.exit(f"This interpreter has hyperglot {hyperglot.__version__}, not {args.hyperglot}.")
    export()


if __name__ == "__main__":
    main()
