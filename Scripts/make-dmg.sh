#!/bin/bash
# Packages build/Scrollwise.app as a disk image — the app and an Applications
# shortcut, nothing else — and writes its SHA-256 beside it for the release
# notes. Run Scripts/build-app.sh first.
#
#   Scripts/make-dmg.sh
#
# Releases are signed with the project's self-signed release identity and are
# not notarized; see docs/PRODUCTION-CHECKLIST.md. This script refuses a bundle
# signed any other way, because every user's Accessibility grant is tied to that
# identity: a release signed ad hoc, or with another certificate, silently
# stops working for everyone who installed an earlier one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Scrollwise.app"
RELEASE_IDENTITY="${RELEASE_IDENTITY:-Scrollwise Local Signing}"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found — run Scripts/build-app.sh first" >&2
    exit 1
fi
codesign --verify --strict "$APP"

# The first Authority line is the signing certificate; ad-hoc has none.
AUTHORITY="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')"
if [ "$AUTHORITY" != "$RELEASE_IDENTITY" ]; then
    echo "error: $APP is signed by \"${AUTHORITY:-nothing (ad hoc)}\", not \"$RELEASE_IDENTITY\"." >&2
    echo "       Shipping it would break every existing user's Accessibility grant." >&2
    echo "       Put the release certificate in the keychain and run Scripts/build-app.sh again." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Scrollwise-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# ditto preserves the signature exactly; cp can drop extended metadata.
ditto "$APP" "$STAGE/Scrollwise.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Scrollwise" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"

# Optional: sign the image itself. Only a Developer ID signature can carry the
# secure timestamp notarization needs; any other identity signs without one.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    case "$SIGN_IDENTITY" in
        "Developer ID Application:"*) TIMESTAMP="--timestamp" ;;
        *) TIMESTAMP="--timestamp=none" ;;
    esac
    echo "==> Signing image with $SIGN_IDENTITY"
    codesign --sign "$SIGN_IDENTITY" "$TIMESTAMP" "$DMG"
fi

echo "==> Verifying"
hdiutil verify -quiet "$DMG"

# Written relative to its own directory, so `shasum -c` works wherever the two
# files are downloaded together.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") > "$DMG.sha256"
echo "Built:   $DMG"
echo "SHA-256: $(cut -d ' ' -f 1 "$DMG.sha256")  (also in $(basename "$DMG").sha256)"
