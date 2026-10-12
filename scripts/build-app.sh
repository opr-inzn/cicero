#!/bin/bash
# Builds build/Point.app. Pass --install to also copy it to /Applications.
#   SIGN_IDENTITY  codesigning identity (default: ad-hoc "-"); a real identity also enables the hardened runtime
# Apple silicon only.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Point"

APP=build/Point.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Point"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Language data from Hyperglot (see scripts/update-languages.py) and its license.
cp Resources/Languages.json Resources/Languages-LICENSE.txt Resources/Languages-README.txt "$APP/Contents/Resources/"

# Compile the Icon Composer icon into Assets.car plus an AppIcon.icns fallback.
# actool runs through a helper process, so it needs absolute paths.
PARTIAL="$(mktemp -d)/partial.plist"
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL" >/dev/null

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP" >/dev/null
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Point.app
    cp -R "$APP" /Applications/Point.app
    echo "Installed /Applications/Point.app"
else
    echo "Built $APP"
fi
