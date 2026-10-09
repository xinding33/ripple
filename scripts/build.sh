#!/bin/bash
# Builds dist/Ripple.app and dist/Ripple.zip for this Mac's architecture.
# Ad-hoc signed by default; set SIGN_IDENTITY to sign with a certificate instead.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="1.0.0"
# Homebrew builds inside its own sandbox, where SwiftPM's nested sandbox is not allowed.
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"

APP="$PWD/dist/Ripple.app"
rm -rf "$APP" "$PWD/dist/Ripple.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Ripple" "$APP/Contents/MacOS/Ripple"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Ripple.zip"
printf 'Built: %s\n' "$APP"
