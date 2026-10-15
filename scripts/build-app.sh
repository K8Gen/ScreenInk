#!/bin/sh
# Builds an arm64-only ScreenInk.app into build/.
#   scripts/build-app.sh            release build, ad-hoc signed
#   SIGN_ID="Developer ID Application: …" scripts/build-app.sh   signed for distribution
set -eu
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
APP=build/ScreenInk.app

swift build -c "$CONFIG" --arch arm64
BIN=$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/ScreenInk

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenInk"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$APP"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/ScreenInk")
[ "$ARCHS" = "arm64" ] || { echo "expected arm64 only, got: $ARCHS" >&2; exit 1; }
echo "Built $APP ($ARCHS)"
