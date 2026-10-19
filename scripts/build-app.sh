#!/bin/bash
# Builds build/Cicero.app. Pass --install to also copy it to /Applications.
#   SIGN_IDENTITY  codesigning identity (default: ad-hoc "-"); a real identity also enables the hardened runtime
#                  and a secure timestamp, as notarization needs
# Apple silicon only.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM's build system links without telling clang which SDK it is, so the app would say it was built
# with the SDK of its deployment target (26), and a newer macOS would give it that release's look and
# behaviour. Hand the SDK to the link step too.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD=(swift build -c release --arch arm64 -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")
"${BUILD[@]}"
BIN_DIR="$("${BUILD[@]}" --show-bin-path)"

APP=build/Cicero.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Cicero" "$APP/Contents/MacOS/Cicero"
BUILT_SDK="$(otool -l "$APP/Contents/MacOS/Cicero" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "sdk" { print $2; exit }')"
if [[ "$BUILT_SDK" != "$(xcrun --sdk macosx --show-sdk-version)" ]]; then
    echo "Cicero says it was built with the macOS $BUILT_SDK SDK, not $(xcrun --sdk macosx --show-sdk-version)" >&2
    exit 1
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Language data from Hyperglot (see scripts/update-languages.py) and its license.
cp Resources/Languages.json Resources/Languages-LICENSE.txt Resources/Languages-README.txt "$APP/Contents/Resources/"
# Built-in character sets (see scripts/update-character-sets.py) and their licenses.
cp Resources/CharacterSets.json Resources/CharacterSets-LICENSES.txt "$APP/Contents/Resources/"

# Sparkle, for updates, and its license. The binary finds it through the @executable_path/../Frameworks
# rpath set in Package.swift. Cicero isn't sandboxed, so Sparkle starts its installer itself and the
# XPC services it ships for sandboxed apps aren't needed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"

# The model of letters' embeddings for similar fonts (see scripts/embedding).
xcrun coremlcompiler compile Resources/LetterEmbedding.mlpackage "$APP/Contents/Resources" >/dev/null

# Compile the Icon Composer icon into Assets.car plus an AppIcon.icns fallback.
# actool runs through a helper process, so it needs absolute paths.
PARTIAL="$(mktemp -d)/partial.plist"
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL" >/dev/null

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    SIGN=(codesign --force --sign -)
else
    SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
fi
# Inside out and without --deep, as Sparkle's documentation says: its helpers, the framework, the app.
for CODE in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    "${SIGN[@]}" "$CODE"
done
"${SIGN[@]}" --entitlements Resources/Cicero.entitlements "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Cicero.app
    cp -R "$APP" /Applications/Cicero.app
    echo "Installed /Applications/Cicero.app"
else
    echo "Built $APP"
fi
