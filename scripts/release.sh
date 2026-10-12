#!/bin/bash
# Builds an Apple silicon, Developer ID–signed, notarized and stapled build/Point-<version>.dmg.
#   ./scripts/release.sh          release the version in Resources/Info.plist
#   ./scripts/release.sh 1.1      set the version (and bump the build number) first
# One-time setup is described in README.md under "Releasing".
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-point-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "No \"Developer ID Application\" certificate in the keychain. See README.md → Releasing." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "No notarytool credentials named \"$PROFILE\". See README.md → Releasing." >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    plutil -replace CFBundleShortVersionString -string "$1" Resources/Info.plist
    BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist) + 1 ))
    plutil -replace CFBundleVersion -string "$BUILD" Resources/Info.plist
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
echo "Releasing Point $VERSION, signed by $IDENTITY"

notarize() {
    local out id
    out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1) || true
    echo "$out"
    if ! grep -q "status: Accepted" <<<"$out"; then
        id=$(sed -n 's/^ *id: //p' <<<"$out" | head -1)
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$PROFILE"
        echo "Notarization of $1 failed." >&2
        exit 1
    fi
}

SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh

# Notarize and staple the app itself, so it also opens offline once copied out of the DMG.
ZIP="$(mktemp -d)/Point.zip"
ditto -c -k --keepParent build/Point.app "$ZIP"
notarize "$ZIP"
xcrun stapler staple build/Point.app

./scripts/make-dmg.sh --no-build
DMG="build/Point-$VERSION.dmg"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

spctl --assess --type execute --verbose build/Point.app
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Ready: $DMG — commit and push, then run ./scripts/publish.sh"
