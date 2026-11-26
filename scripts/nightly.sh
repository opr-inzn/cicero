#!/bin/bash
# Builds and publishes a nightly of main with release.sh and publish.sh. The nightly workflow (.github/workflows/nightly.yml)
# runs it every 2 hours on the Mac that releases, and it works by hand too. It does nothing when main has no commits since the last
# release or nightly, or when the last nightly is newer than CICERO_NIGHTLY_GAP_HOURS.
# The version is the next one with -nightly.<n>: 0.14.0-nightly.3 after v0.13.0 and two nightlies of 0.14.0, or the version in
# Resources/Info.plist when that isn't released yet. The notes are the "## Unreleased" section of CHANGELOG.md, else the subjects of
# the commits since the last release. The version, the notes and help/version-history.md change in this copy only, for the build,
# and are put back after it, so nothing is committed: the nightly's tag is main's commit.
#   ./scripts/nightly.sh            build and publish a nightly
#   ./scripts/nightly.sh --dry-run  say which version and notes it would publish, and stop
#   SPARKLE_KEY_FILE                sign the update with the key in this file, not the keychain's (see make-appcast.sh)
#   CICERO_NIGHTLY_GAP_HOURS        do nothing when the last nightly was published less than this many hours ago (default 0)
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || { echo "Nightlies are built from main." >&2; exit 1; }
git fetch -q --force --tags origin main
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "This main isn't origin/main: pull or push first." >&2; exit 1; }

TAGGED=$(git tag --points-at HEAD 'v[0-9]*' | head -1)
if [[ -n "$TAGGED" ]]; then
    echo "No nightly: main is $TAGGED, with no commits since."
    exit 0
fi
LAST_NIGHTLY=$(gh release list --limit 100 --json tagName,publishedAt,isDraft --jq \
    '[.[] | select((.isDraft | not) and (.tagName | test("-nightly\\.[0-9]+$")))] | max_by(.publishedAt) // empty | [.tagName, .publishedAt] | @tsv')
if [[ -n "$LAST_NIGHTLY" ]]; then
    IFS=$'\t' read -r NIGHTLY_TAG NIGHTLY_AT <<<"$LAST_NIGHTLY"
    if [[ "$(gh api "repos/{owner}/{repo}/commits/$NIGHTLY_TAG" --jq .sha)" == "$(git rev-parse HEAD)" ]]; then
        echo "No nightly: main is $NIGHTLY_TAG, with no commits since."
        exit 0
    fi
    AGE=$(( $(date -u +%s) - $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$NIGHTLY_AT" +%s) ))
    if (( AGE < ${CICERO_NIGHTLY_GAP_HOURS:-0} * 3600 )); then
        echo "No nightly: $NIGHTLY_TAG was published $(( AGE / 60 )) minutes ago, less than $CICERO_NIGHTLY_GAP_HOURS hours."
        exit 0
    fi
fi
LAST=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)

BASE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
BASE=${BASE%%-nightly.*}
if git rev-parse -q --verify "refs/tags/v$BASE" >/dev/null; then
    IFS=. read -r MAJOR MINOR _ <<<"$BASE"
    BASE="$MAJOR.$((MINOR + 1)).0"
fi
LAST_N=$(git tag -l "v$BASE-nightly.*" | sed -n "s/^v${BASE//./\\.}-nightly\.\([0-9][0-9]*\)$/\1/p" | sort -n | tail -1)
VERSION="$BASE-nightly.$(( ${LAST_N:-0} + 1 ))"

NOTES=$(awk '$0 == "## Unreleased" { found = 1; next } found && /^## / { exit } found' CHANGELOG.md | sed '/./,$!d')
[[ -n "${NOTES//[[:space:]]/}" ]] || NOTES=$(git log --no-merges --reverse --format='- %s' "$LAST..HEAD")

echo "Cicero $VERSION, from $(git rev-parse --short HEAD) on main, $(git rev-list --count "$LAST..HEAD") commits after $LAST. Its notes:"
echo "$NOTES"
[[ -z "$DRY_RUN" ]] || exit 0

trap 'git checkout -q -- Resources/Info.plist CHANGELOG.md help/version-history.md' EXIT
WITH_NOTES=$(mktemp -t cicero-changelog)
NOTES="$NOTES" VERSION="$VERSION" awk '!done && /^## [0-9]/ { print "## " ENVIRON["VERSION"] "\n\n" ENVIRON["NOTES"] "\n"; done = 1 } { print }' \
    CHANGELOG.md > "$WITH_NOTES"
cat "$WITH_NOTES" > CHANGELOG.md
rm "$WITH_NOTES"

./scripts/release.sh "$VERSION"
CICERO_NIGHTLY_BUILD=1 ./scripts/publish.sh
