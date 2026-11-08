#!/bin/bash
# Writes help/version-history.md, which Help → Version History opens on GitHub: the released versions' sections of
# CHANGELOG.md, newest first, as one page of text. Not "## Unreleased", nor the note above the first version. Links
# relative to CHANGELOG.md are made relative to help/: help/privacy.md → privacy.md, docs/SPEC.md → ../docs/SPEC.md.
# release.sh runs it; run it by hand after changing an earlier version's notes.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=help/version-history.md
{
    echo "# Version History"
    echo
    echo "What changed in each version of Cicero, newest first. To download a version, see the [releases page](https://github.com/opr-inzn/cicero/releases)."
    echo
    echo "<!-- Written by scripts/make-version-history.sh from CHANGELOG.md. Change CHANGELOG.md, not this file. -->"
    echo
    awk '
        /^## / { keep = ($2 ~ /^[0-9]/) }
        keep {
            line = $0
            out = ""
            # Each link target: as it is when it is a web address or an anchor, else relative to help/.
            while (match(line, /\]\([^)]+\)/)) {
                target = substr(line, RSTART + 2, RLENGTH - 3)
                if (target !~ /^[a-z]+:/ && target !~ /^#/) {
                    if (target ~ /^help\//) target = substr(target, 6)
                    else target = "../" target
                }
                out = out substr(line, 1, RSTART - 1) "](" target ")"
                line = substr(line, RSTART + RLENGTH)
            }
            print out line
        }
    ' CHANGELOG.md
} | cat -s > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "Wrote $OUT: $(grep -c '^## ' "$OUT") versions, the newest $(grep -m1 '^## ' "$OUT" | cut -c4-)"
