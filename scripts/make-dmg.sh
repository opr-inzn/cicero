#!/bin/bash
# Builds build/Point-<version>.dmg with the usual drag-to-Applications layout.
# Pass --no-build to package the existing build/Point.app.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--no-build" ]] || ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Point.app/Contents/Info.plist)
DMG="build/Point-$VERSION.dmg"

STAGE=$(mktemp -d)
cp -R build/Point.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Point" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
