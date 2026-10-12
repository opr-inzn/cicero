#!/bin/bash
# Publishes build/Cicero-<version>.dmg (made by release.sh) as a GitHub release, using that
# version's section of CHANGELOG.md as the notes. The asset is always named Cicero.dmg so
# https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg stays the latest version.
#   ./scripts/publish.sh                  publish the version in Resources/Info.plist
#   ./scripts/publish.sh --allow-unsigned publish even if the DMG isn't notarized
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG="build/Cicero-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "Missing $DMG — run ./scripts/release.sh first." >&2; exit 1; }

if [[ "${1:-}" != "--allow-unsigned" ]] && ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "$DMG isn't notarized. Run ./scripts/release.sh, or pass --allow-unsigned." >&2
    exit 1
fi

NOTES=$(awk -v v="$VERSION" '$0 == "## " v { found = 1; next } found && /^## / { exit } found' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "Add a \"## $VERSION\" section to CHANGELOG.md first." >&2; exit 1; }

if [[ -n "$(git status --porcelain)" ]] || [[ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]]; then
    echo "Commit and push your changes first, so the release tag matches the published code." >&2
    exit 1
fi

ASSET_DIR=$(mktemp -d)
cp "$DMG" "$ASSET_DIR/Cicero.dmg"
gh release create "v$VERSION" "$ASSET_DIR/Cicero.dmg" \
    --title "Cicero $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)" --latest
rm -rf "$ASSET_DIR"
