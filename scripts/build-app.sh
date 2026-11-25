#!/bin/bash
# Builds build/Cicero.app. Pass --install to also copy it to /Applications.
#   SIGN_IDENTITY  codesigning identity (default: ad-hoc "-"). A real identity also enables the hardened runtime
#                  and a secure timestamp, as notarization needs. An ad-hoc build is a dev build (-D CICERO_DEV):
#                  there the Delete key neither deactivates nor moves fonts to the Trash
#   MEASURE=1      compiles in the app performance runs' measurements (-D CICERO_MEASURE), for
#                  Tests/E2E/app-perf/build-perf-app.sh only, and keeps the symbols that Instruments shows. Without it,
#                  a binary that has them is refused, and both binaries are stripped, their symbols kept in
#                  build/dSYMs/<version>-<build> for crash reports
# Apple silicon only.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM's build system links without telling clang which SDK it is, so the app would say it was built with the SDK of its deployment target (15), and a newer macOS would give it that release's look and behaviour. Hand the SDK to the link step too.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD=(swift build -c release --arch arm64 -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")
[[ "${MEASURE:-}" == 1 ]] && BUILD+=(-Xswiftc -DCICERO_MEASURE)
[[ "${SIGN_IDENTITY:--}" == "-" ]] && BUILD+=(-Xswiftc -DCICERO_DEV)
"${BUILD[@]}"
BIN_DIR="$("${BUILD[@]}" --show-bin-path)"

APP=build/Cicero.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN_DIR/Cicero" "$APP/Contents/MacOS/Cicero"
# Not in Contents/MacOS: on a disk that ignores case, cicero is Cicero, the app.
cp "$BIN_DIR/cicero-tool" "$APP/Contents/Helpers/cicero"
mkdir -p "$APP/Contents/Resources/zsh" "$APP/Contents/Resources/bash" "$APP/Contents/Resources/fish"
"$BIN_DIR/cicero-tool" --generate-completion-script zsh > "$APP/Contents/Resources/zsh/_cicero"
"$BIN_DIR/cicero-tool" --generate-completion-script bash > "$APP/Contents/Resources/bash/cicero"
"$BIN_DIR/cicero-tool" --generate-completion-script fish > "$APP/Contents/Resources/fish/cicero.fish"
if [[ "$(head -1 "$APP/Contents/Resources/zsh/_cicero")" != "#compdef cicero" ]]; then
    echo "The zsh completion script isn't for the command cicero" >&2
    exit 1
fi
if [[ "$(tail -1 "$APP/Contents/Resources/bash/cicero")" != "complete -o filenames -F _cicero cicero" ]]; then
    echo "The bash completion script isn't for the command cicero" >&2
    exit 1
fi
if ! grep -qx "complete -c 'cicero' -f" "$APP/Contents/Resources/fish/cicero.fish" || grep -q 'cicero-tool' "$APP/Contents/Resources/fish/cicero.fish"; then
    echo "The fish completion script isn't for the command cicero" >&2
    exit 1
fi
# LC_ALL=C and -a, or grep stops at the first bytes that aren't UTF-8.
if [[ "${MEASURE:-}" != 1 ]] && { nm "$APP/Contents/MacOS/Cicero" 2>/dev/null | grep -qE "MeasureRun|12Measurements" \
    || LC_ALL=C grep -aq "CICERO_MEASURE_RUN" "$APP/Contents/MacOS/Cicero"; }; then
    echo "The binary has the app performance runs' measurements in it (CICERO_MEASURE): rebuild without MEASURE=1" >&2
    exit 1
fi
BUILT_SDK="$(otool -l "$APP/Contents/MacOS/Cicero" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "sdk" { print $2; exit }')"
if [[ "$BUILT_SDK" != "$(xcrun --sdk macosx --show-sdk-version)" ]]; then
    echo "Cicero says it was built with the macOS $BUILT_SDK SDK, not $(xcrun --sdk macosx --show-sdk-version)" >&2
    exit 1
fi
if [[ "${MEASURE:-}" != 1 ]]; then
    PLIST=Resources/Info.plist
    DSYMS="build/dSYMs/$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")-$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
    rm -rf "$DSYMS"
    mkdir -p "$DSYMS"
    dsymutil "$APP/Contents/MacOS/Cicero" -o "$DSYMS/Cicero.dSYM"
    # Not cicero.dSYM, which is Cicero.dSYM on a disk that ignores case.
    dsymutil "$APP/Contents/Helpers/cicero" -o "$DSYMS/cicero-cli.dSYM"
    strip -S -x "$APP/Contents/MacOS/Cicero" "$APP/Contents/Helpers/cicero"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Languages.json Resources/Languages-LICENSE.txt Resources/Languages-README.txt "$APP/Contents/Resources/"
cp Resources/CharacterSets.json Resources/CharacterSets-LICENSES.txt "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/"
cp Resources/GlyphsInfo-LICENSE.txt "$APP/Contents/Resources/"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"

xcrun coremlcompiler compile Resources/LetterEmbedding.mlpackage "$APP/Contents/Resources" >/dev/null

# actool runs through a helper process, so it needs absolute paths.
PARTIAL="$(mktemp -d)/partial.plist"
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL" >/dev/null

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    SIGN=(codesign --force --sign -)
else
    SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
fi
# Sign inside out without --deep: helpers, framework, then app.
for CODE in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    "${SIGN[@]}" "$CODE"
done
"${SIGN[@]}" --identifier com.maximilianinzinger.Cicero.cli "$APP/Contents/Helpers/cicero"
"${SIGN[@]}" --entitlements Resources/Cicero.entitlements "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Cicero.app
    cp -R "$APP" /Applications/Cicero.app
    echo "Installed /Applications/Cicero.app"
else
    echo "Built $APP"
fi
