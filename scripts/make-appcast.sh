#!/bin/bash
# Writes build/appcast.xml, the feed Sparkle reads for updates, for build/Cicero-<version>.dmg (made by
# release.sh). The DMG is signed with the EdDSA key whose public half is SUPublicEDKey in Info.plist, and
# that version's section of CHANGELOG.md becomes the release notes. publish.sh runs this and uploads the
# feed with the DMG, so https://github.com/opr-inzn/cicero/releases/latest/download/appcast.xml (SUFeedURL)
# always describes the latest version.
#   ./scripts/make-appcast.sh             the DMG of the version in Resources/Info.plist
#   ./scripts/make-appcast.sh <dmg>       another DMG of that version
#   SPARKLE_KEY_FILE  sign with the private key in this file instead of the keychain's "cicero" account
set -euo pipefail
cd "$(dirname "$0")/.."

plist() { /usr/libexec/PlistBuddy -c "Print $1" Resources/Info.plist; }
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
# Sparkle wants major.minor.patch.
MINIMUM_SYSTEM=$(plist LSMinimumSystemVersion)
[[ "$MINIMUM_SYSTEM" == *.*.* ]] || MINIMUM_SYSTEM="$MINIMUM_SYSTEM.0"
DMG="${1:-build/Cicero-$VERSION.dmg}"
[[ -f "$DMG" ]] || { echo "Missing $DMG — run ./scripts/release.sh first." >&2; exit 1; }
# The feed must name the build the DMG holds, or Sparkle offers the update again and again.
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" build/Cicero.app/Contents/Info.plist 2>/dev/null || true)
[[ "$BUILT" == "$BUILD" ]] ||
    { echo "build/Cicero.app is build ${BUILT:-(missing)}, Info.plist says $BUILD — run ./scripts/release.sh again." >&2; exit 1; }
# A feed naming a build that isn't above the published one would never offer it.
./scripts/check-version.sh

NOTES=$(awk -v v="$VERSION" '$0 == "## " v { found = 1; next } found && /^## / { exit } found' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "Add a \"## $VERSION\" section to CHANGELOG.md first." >&2; exit 1; }

# Prints sparkle:edSignature="…" length="…" for the enclosure. The first time, macOS may ask to let
# sign_update use the key; choose Always Allow.
SIGN_UPDATE=.build/artifacts/sparkle/Sparkle/bin/sign_update
[[ -x "$SIGN_UPDATE" ]] || swift package resolve
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    ENCLOSURE_SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG")
else
    ENCLOSURE_SIGNATURE=$("$SIGN_UPDATE" --account cicero "$DMG")
fi
[[ "$ENCLOSURE_SIGNATURE" =~ ^sparkle:edSignature=\"[^\"]+\"\ length=\"[0-9]+\"$ ]] ||
    { echo "Unexpected output from sign_update: $ENCLOSURE_SIGNATURE" >&2; exit 1; }

# Sparkle (2.9 and later) shows Markdown notes as they are; only "]]>" would end the CDATA section.
APPCAST=build/appcast.xml
cat >"$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Cicero</title>
        <link>https://github.com/opr-inzn/cicero</link>
        <description>Updates for Cicero.</description>
        <language>en</language>
        <item>
            <title>Cicero $VERSION</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
            <description sparkle:format="markdown"><![CDATA[
${NOTES//]]>/]]]]><![CDATA[>}
]]></description>
            <enclosure url="https://github.com/opr-inzn/cicero/releases/download/v$VERSION/Cicero.dmg" $ENCLOSURE_SIGNATURE type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF
xmllint --noout "$APPCAST"
echo "Built $APPCAST"
