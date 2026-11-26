#!/bin/bash
# Publishes build/Cicero-<version>.dmg (made by release.sh) as a GitHub release, using that
# version's section of CHANGELOG.md as the notes, with the appcast.xml Sparkle reads for updates
# (see make-appcast.sh) and Cicero-<version>-<build>.dmg, the copy the feed names. The other two assets always have these names, so
# https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg stays the latest version
# and .../latest/download/appcast.xml offers it as an update. If that version's release exists, its files
# are replaced in place, and the replaced files' download counts are added to docs/downloads.tsv first (local only, in .gitignore).
#
# A stable version (0.14.0) is published from main and becomes the latest release. A nightly (0.14.0-nightly.1) is
# published from nightly as a pre-release, so the latest download link stays on the stable version, and its feed
# (stable + nightly) replaces appcast.xml on the latest stable release.
#   ./scripts/publish.sh                  publish the version in Resources/Info.plist
#   CICERO_SKIP_VERSION_CHECK=1 ./scripts/publish.sh   replace a published version in place: move its tag to HEAD and push it first
#   ./scripts/publish.sh --allow-unsigned publish even if the DMG isn't notarized
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG="build/Cicero-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "Missing $DMG — run ./scripts/release.sh first." >&2; exit 1; }

if [[ "$VERSION" =~ -nightly\.[0-9]+$ ]]; then BRANCH=nightly; else BRANCH=main; fi
CURRENT=$(git rev-parse --abbrev-ref HEAD)
[[ "$CURRENT" == "$BRANCH" ]] ||
    { echo "Cicero $VERSION is published from $BRANCH, and this is $CURRENT." >&2; exit 1; }

if [[ "${1:-}" != "--allow-unsigned" ]] && ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "$DMG isn't notarized. Run ./scripts/release.sh, or pass --allow-unsigned." >&2
    exit 1
fi

NOTES=$(awk -v v="$VERSION" '$0 == "## " v { found = 1; next } found && /^## / { exit } found' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "Add a \"## $VERSION\" section to CHANGELOG.md first." >&2; exit 1; }
grep -qx "## $VERSION" help/version-history.md || { echo "help/version-history.md doesn't have $VERSION: run scripts/make-version-history.sh and commit it." >&2; exit 1; }

if [[ -n "$(git status --porcelain)" ]] || [[ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]]; then
    echo "Commit and push your changes first, so the release tag matches the published code." >&2
    exit 1
fi

IN_PLACE=
if gh release view "v$VERSION" >/dev/null 2>&1; then
    IN_PLACE=1
    [[ "$(git rev-parse "v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] ||
        { echo "v$VERSION is published. To replace it in place, move the tag v$VERSION to HEAD and push it first." >&2; exit 1; }
fi

./scripts/make-appcast.sh "$DMG"

ASSET_DIR=$(mktemp -d)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
cp "$DMG" "$ASSET_DIR/Cicero.dmg"
cp "$DMG" "$ASSET_DIR/Cicero-$VERSION-$BUILD.dmg"
cp build/appcast.xml "$ASSET_DIR/appcast.xml"
COUNTS=docs/downloads.tsv
if [[ "$BRANCH" == nightly ]]; then
    LATEST=$(gh release view --json tagName --jq .tagName)
    NIGHTLY_ASSETS=("$ASSET_DIR/Cicero.dmg" "$ASSET_DIR/Cicero-$VERSION-$BUILD.dmg")
    SAVED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    REPLACED_FEED=$(gh release view "$LATEST" --json assets --jq '.assets[] | [.name, .downloadCount] | @tsv' |
        awk -F '\t' -v saved="$SAVED" -v release="$LATEST" '$1 == "appcast.xml" { print saved "\t" release "\t" $1 "\t" $2 }')
    if [[ -n "$IN_PLACE" ]]; then
        REPLACED=$(gh release view "v$VERSION" --json assets --jq '.assets[] | [.name, .downloadCount] | @tsv' |
            awk -F '\t' -v saved="$SAVED" -v release="v$VERSION" -v build="$BUILD" -v version="$VERSION" \
                '$1 == "Cicero.dmg" || $1 == "Cicero-" version "-" build ".dmg" { print saved "\t" release "\t" $1 "\t" $2 }')
        gh release upload "v$VERSION" "${NIGHTLY_ASSETS[@]}" --clobber
        gh release upload "$LATEST" "$ASSET_DIR/appcast.xml" --clobber
        [[ -f "$COUNTS" ]] || printf 'saved\trelease\tfile\tdownloads\n' > "$COUNTS"
        [[ -z "$REPLACED" ]] || printf '%s\n' "$REPLACED" >> "$COUNTS"
        [[ -z "$REPLACED_FEED" ]] || printf '%s\n' "$REPLACED_FEED" >> "$COUNTS"
        echo "Replaced nightly v$VERSION in place and updated $LATEST's feed. The old download counts are in $COUNTS."
    else
        # Upload the nightly release first so the feed never points to a missing release.
        gh release create "v$VERSION" "${NIGHTLY_ASSETS[@]}" \
            --title "Cicero $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)" --prerelease --latest=false
        gh release upload "$LATEST" "$ASSET_DIR/appcast.xml" --clobber
        [[ -f "$COUNTS" ]] || printf 'saved\trelease\tfile\tdownloads\n' > "$COUNTS"
        [[ -z "$REPLACED_FEED" ]] || printf '%s\n' "$REPLACED_FEED" >> "$COUNTS"
        echo "Published Cicero $VERSION as a pre-release; the feed of $LATEST offers it to nightly users."
    fi
else
    ASSETS=("$ASSET_DIR/Cicero.dmg" "$ASSET_DIR/Cicero-$VERSION-$BUILD.dmg" "$ASSET_DIR/appcast.xml")
    if [[ -n "$IN_PLACE" ]]; then
        # GitHub starts a replaced file's download count again at 0, so the old count is saved here or lost for good.
        SAVED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        REPLACED=$(gh release view "v$VERSION" --json assets --jq '.assets[] | [.name, .downloadCount] | @tsv' |
            awk -F '\t' -v saved="$SAVED" -v release="v$VERSION" -v build="$BUILD" -v version="$VERSION" \
                '$1 == "Cicero.dmg" || $1 == "appcast.xml" || $1 == "Cicero-" version "-" build ".dmg" { print saved "\t" release "\t" $1 "\t" $2 }')
        gh release upload "v$VERSION" "${ASSETS[@]}" --clobber
        [[ -f "$COUNTS" ]] || printf 'saved\trelease\tfile\tdownloads\n' > "$COUNTS"
        [[ -z "$REPLACED" ]] || printf '%s\n' "$REPLACED" >> "$COUNTS"
        echo "Replaced v$VERSION in place. The old download counts are in $COUNTS."
    else
        gh release create "v$VERSION" "${ASSETS[@]}" \
            --title "Cicero $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)" --latest
    fi
fi
rm -rf "$ASSET_DIR"
