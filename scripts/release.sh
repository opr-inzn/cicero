#!/bin/bash
# Builds an Apple silicon, Developer ID–signed, notarized and stapled build/Cicero-<version>.dmg.
#   ./scripts/release.sh          release the version in Resources/Info.plist
#   ./scripts/release.sh 1.1      set the version (and bump the build number) first
#
# One-time setup on the Mac that releases:
#   1. A "Developer ID Application" certificate in the login keychain (Xcode → Settings → Accounts →
#      Manage Certificates, or developer.apple.com). Allow codesign to use its key ("Always Allow").
#   2. Notarization credentials stored for notarytool, using an app-specific password from
#      account.apple.com:
#        xcrun notarytool store-credentials cicero-notary --apple-id <id> --team-id <team>
#   3. The EdDSA key that signs updates (SUPublicEDKey is its public half) in the login keychain, under
#      the account "cicero", for publish.sh. To bring it from a backup after `swift package resolve`:
#        .build/artifacts/sparkle/Sparkle/bin/generate_keys --account cicero -f <file>
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-cicero-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "No \"Developer ID Application\" certificate in the keychain. See the setup notes at the top of this script." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "No notarytool credentials named \"$PROFILE\". See the setup notes at the top of this script." >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    plutil -replace CFBundleShortVersionString -string "$1" Resources/Info.plist
    BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist) + 1 ))
    plutil -replace CFBundleVersion -string "$BUILD" Resources/Info.plist
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
echo "Releasing Cicero $VERSION, signed by $IDENTITY"

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
ZIP="$(mktemp -d)/Cicero.zip"
ditto -c -k --keepParent build/Cicero.app "$ZIP"
notarize "$ZIP"
xcrun stapler staple build/Cicero.app

./scripts/make-dmg.sh --no-build
DMG="build/Cicero-$VERSION.dmg"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

spctl --assess --type execute --verbose build/Cicero.app
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Ready: $DMG — commit and push, then run ./scripts/publish.sh"
