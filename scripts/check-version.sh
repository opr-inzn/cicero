#!/bin/bash
# Checks that the version in Resources/Info.plist can be released: it reads like 0.12.0 (stable) or 0.12.0b1 (beta), its
# build number has the right form and is above every one the feed offers now, stable or beta (Sparkle goes by build
# numbers, so one that isn't above would never reach them), and its tag isn't taken. release.sh runs this before
# building, make-appcast.sh before writing the feed.
#
# Stable versions count on in whole numbers (62, 63, …). A beta's build is the latest stable build, a dot and the beta's
# number (0.12.0b1 after stable build 62 is 62.1), so betas fit between two stable builds and never take the next
# stable one. Sparkle compares the parts one by one: 62 < 62.1 < 62.2 < 63.
#   ./scripts/check-version.sh
#   CICERO_SKIP_VERSION_CHECK=1   skip it, when GitHub can't be reached
#   CICERO_FEED_URL               read the published feed from here instead of GitHub (for tests; a file:// URL works)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${CICERO_SKIP_VERSION_CHECK:-}" ]]; then
    echo "Not checking the version against the published one." >&2
    exit 0
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
FEED=${CICERO_FEED_URL:-https://github.com/opr-inzn/cicero/releases/latest/download/appcast.xml}

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}(b[0-9]+)?$ ]] ||
    { echo "The version is “${VERSION}”; it must read like 0.12.0, or 0.12.0b1 for a beta." >&2; exit 1; }

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null 2>&1 || [[ -n "$(git ls-remote --tags origin "refs/tags/v$VERSION" 2>/dev/null)" ]]; then
    echo "There's a v$VERSION tag already: give this release another version number." >&2
    exit 1
fi

FEED_TEXT=$(curl -fsSL --max-time 30 "$FEED") || true
BUILDS=$(sed -n 's|.*<sparkle:version>\([0-9.]*\)</sparkle:version>.*|\1|p' <<<"$FEED_TEXT")
if [[ -z "$BUILDS" ]]; then
    echo "Couldn't read the published build numbers from $FEED. Check the connection, or set CICERO_SKIP_VERSION_CHECK=1." >&2
    exit 1
fi
# The highest of all, and the highest stable one (the items in no channel).
PUBLISHED=$(sort -V <<<"$BUILDS" | tail -1)
STABLE=$(awk '/<item>/{b=""} {b=b $0} /<\/item>/{if (b !~ /<sparkle:channel>/) print b}' <<<"$FEED_TEXT" |
    sed -n 's|.*<sparkle:version>\([0-9.]*\)</sparkle:version>.*|\1|p' | sort -V | tail -1)

if [[ "$VERSION" =~ b([0-9]+)$ ]]; then
    EXPECTED="$STABLE.${BASH_REMATCH[1]}"
    [[ "$BUILD" == "$EXPECTED" ]] || {
        echo "Build $BUILD: a beta's build is the latest stable build, a dot and its beta number, so $EXPECTED for $VERSION." >&2
        echo "Set CFBundleVersion in Resources/Info.plist (or pass the version to release.sh, which does)." >&2
        exit 1
    }
else
    [[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Build $BUILD: a stable version's build is a whole number." >&2; exit 1; }
fi
if [[ "$BUILD" == "$PUBLISHED" || "$(printf '%s\n%s\n' "$PUBLISHED" "$BUILD" | sort -V | tail -1)" != "$BUILD" ]]; then
    echo "Build $BUILD isn't above build $PUBLISHED, the one installed copies are offered now, so they'd never be offered" >&2
    echo "this one. Raise CFBundleVersion in Resources/Info.plist (or pass a version to release.sh, which does)." >&2
    exit 1
fi
echo "Cicero $VERSION, build $BUILD, follows build $PUBLISHED"
