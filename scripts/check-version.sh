#!/bin/bash
# Checks that the version in Resources/Info.plist can be released: its build number is above the one installed copies
# are offered now (Sparkle goes by build numbers, so one that isn't above would never reach them), and its tag isn't
# taken. release.sh runs this before building, make-appcast.sh before writing the feed.
#   ./scripts/check-version.sh
#   CICERO_SKIP_VERSION_CHECK=1   skip it, when GitHub can't be reached
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${CICERO_SKIP_VERSION_CHECK:-}" ]]; then
    echo "Not checking the version against the published one." >&2
    exit 0
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
FEED=https://github.com/opr-inzn/cicero/releases/latest/download/appcast.xml

[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion is “$BUILD”; Sparkle needs a whole number." >&2; exit 1; }

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null 2>&1 || [[ -n "$(git ls-remote --tags origin "refs/tags/v$VERSION" 2>/dev/null)" ]]; then
    echo "There's a v$VERSION tag already: give this release another version number." >&2
    exit 1
fi

PUBLISHED=$(curl -fsSL --max-time 30 "$FEED" | sed -n 's|.*<sparkle:version>\([0-9][0-9]*\)</sparkle:version>.*|\1|p' | head -1) || true
if [[ -z "$PUBLISHED" ]]; then
    echo "Couldn't read the published build number from $FEED. Check the connection, or set CICERO_SKIP_VERSION_CHECK=1." >&2
    exit 1
fi
if (( BUILD <= PUBLISHED )); then
    echo "Build $BUILD isn't above build $PUBLISHED, the one installed copies are offered now, so they'd never be offered" >&2
    echo "this one. Raise CFBundleVersion in Resources/Info.plist (or pass a version to release.sh, which does)." >&2
    exit 1
fi
echo "Cicero $VERSION, build $BUILD, follows build $PUBLISHED"
