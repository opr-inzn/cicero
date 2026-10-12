#!/bin/bash
# Builds build/Cicero-<version>.dmg with the usual drag-to-Applications layout.
# Pass --no-build to package the existing build/Cicero.app.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--no-build" ]] || ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Cicero.app/Contents/Info.plist)
DMG="build/Cicero-$VERSION.dmg"

STAGE=$(mktemp -d)
cp -R build/Cicero.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Cicero" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
