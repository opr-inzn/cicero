#!/bin/bash
# Publishes build/Cicero-<version>.dmg (made by release.sh) as a GitHub release, using that
# version's section of CHANGELOG.md as the notes, with the appcast.xml Sparkle reads for updates
# (see make-appcast.sh). The assets always have these names, so
# https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg stays the latest version
# and .../latest/download/appcast.xml offers it as an update.
#
# A stable version (0.12.0) is published from main and becomes the latest release. A beta (0.12.0b1) is published
# from beta as a pre-release, which GitHub never makes the latest, so the download link stays on the stable version;
# its feed, the stable version and the beta, replaces the one of the latest release, which every copy reads.
# A stable fix published while a beta is out has the higher build number, so beta users get it too, without the
# beta's changes: publish a beta with the fix (merge main into beta) soon after.
#   ./scripts/publish.sh                  publish the version in Resources/Info.plist
#   ./scripts/publish.sh --allow-unsigned publish even if the DMG isn't notarized
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG="build/Cicero-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "Missing $DMG — run ./scripts/release.sh first." >&2; exit 1; }

if [[ "$VERSION" =~ b[0-9]+$ ]]; then BRANCH=beta; else BRANCH=main; fi
CURRENT=$(git rev-parse --abbrev-ref HEAD)
[[ "$CURRENT" == "$BRANCH" ]] ||
    { echo "Cicero $VERSION is published from $BRANCH, and this is $CURRENT." >&2; exit 1; }

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

./scripts/make-appcast.sh "$DMG"

ASSET_DIR=$(mktemp -d)
cp "$DMG" "$ASSET_DIR/Cicero.dmg"
cp build/appcast.xml "$ASSET_DIR/appcast.xml"
if [[ "$BRANCH" == beta ]]; then
    LATEST=$(gh release view --json tagName --jq .tagName)
    # The beta first: if the feed's upload fails, nothing points to a release that isn't there.
    gh release create "v$VERSION" "$ASSET_DIR/Cicero.dmg" \
        --title "Cicero $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)" --prerelease --latest=false
    gh release upload "$LATEST" "$ASSET_DIR/appcast.xml" --clobber
    echo "Published Cicero $VERSION as a pre-release; the feed of $LATEST offers it to beta users."
else
    gh release create "v$VERSION" "$ASSET_DIR/Cicero.dmg" "$ASSET_DIR/appcast.xml" \
        --title "Cicero $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)" --latest
fi
rm -rf "$ASSET_DIR"
