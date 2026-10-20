#!/bin/bash
# Builds build/Cicero-<version>.dmg: Cicero and a link to Applications on the picture from
# make-dmg-background.mjs, laid out by dmg-settings.py. Needs dmgbuild (pip3 install dmgbuild).
# Pass --no-build to package the existing build/Cicero.app.
set -euo pipefail
cd "$(dirname "$0")/.."

DMGBUILD=$(command -v dmgbuild || echo "$(python3 -m site --user-base)/bin/dmgbuild")
[[ -x "$DMGBUILD" ]] || { echo "Missing dmgbuild — pip3 install dmgbuild" >&2; exit 1; }

[[ "${1:-}" == "--no-build" ]] || ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Cicero.app/Contents/Info.plist)
DMG="build/Cicero-$VERSION.dmg"

rm -f "$DMG"
"$DMGBUILD" -s scripts/dmg-settings.py -D app=build/Cicero.app -D background=Resources/DMG/background.png \
    Cicero "$DMG" >/dev/null
echo "Built $DMG"
