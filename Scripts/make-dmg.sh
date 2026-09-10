#!/bin/bash
# Packages build/Scrollwise.app as a disk image: the app and an Applications
# shortcut, nothing else. Run Scripts/build-app.sh first.
#
#   Scripts/make-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: …" Scripts/make-dmg.sh
#
# For distribution the app inside must already carry a Developer ID signature
# and the image must then be notarized and stapled — see
# docs/PRODUCTION-CHECKLIST.md. This script does not notarize.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Scrollwise.app"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found — run Scripts/build-app.sh first" >&2
    exit 1
fi
codesign --verify --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Scrollwise-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# ditto preserves the signature exactly; cp can drop extended metadata.
ditto "$APP" "$STAGE/Scrollwise.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Scrollwise" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing image with $SIGN_IDENTITY"
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "==> Verifying"
hdiutil verify -quiet "$DMG"
echo "Built: $DMG"
