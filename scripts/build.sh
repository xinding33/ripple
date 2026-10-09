#!/bin/bash
# Builds a universal (Apple silicon and Intel) dist/Ripple.app and dist/Ripple.zip.
# Ad-hoc signed by default; set SIGN_IDENTITY to sign with a certificate instead.
# scripts/release.sh signs with a Developer ID for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
# Releases pass RIPPLE_VERSION from the tag; local builds use the latest tag.
VERSION="${RIPPLE_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
IDENTITY="${SIGN_IDENTITY:--}"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf dist
APP="$PWD/dist/Ripple.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Ripple" "$APP/Contents/MacOS/Ripple"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Ripple.zip"
printf 'Built: %s\n' "$APP"
