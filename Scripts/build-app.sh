#!/bin/bash
# Assembles Scrollwise.app from the SwiftPM build product.
#
# A hand-assembled bundle rather than an Xcode target because this tree builds
# with the Command Line Tools toolchain alone. The layout is identical to what
# Xcode produces, so importing it into an Xcode project later changes nothing
# about the result.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Scrollwise.app"

echo "==> Building ($CONFIG, universal)"
cd "$ROOT"
swift build -c "$CONFIG" --product ScrollwiseApp \
    --arch arm64 --arch x86_64 2>/dev/null \
  || { echo "    universal build unavailable, falling back to host arch"; \
       swift build -c "$CONFIG" --product ScrollwiseApp; }

BIN="$(swift build -c "$CONFIG" --product ScrollwiseApp --show-bin-path)"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ScrollwiseApp" "$APP/Contents/MacOS/ScrollwiseApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The icon is committed rather than generated here: it changes only when someone
# redraws it. Regenerate with Scripts/make-icon.swift, which explains its own
# geometry and why the arrows are not the SF Symbol the UI uses.
if [ -f "$ROOT/Resources/Scrollwise.icns" ]; then
    cp "$ROOT/Resources/Scrollwise.icns" "$APP/Contents/Resources/Scrollwise.icns"
else
    echo "    warning: no Scrollwise.icns — the app will show the generic placeholder"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
# Prefer a stable local identity over an ad-hoc signature.
#
# An ad-hoc signature (`--sign -`) has no certificate, so the designated
# requirement macOS derives from it is `cdhash H"..."` — the hash of one exact
# build. TCC stores that requirement when the user grants Accessibility, so the
# next rebuild produces a different hash, stops matching, and the permission
# silently stops applying even though the toggle still looks switched on.
#
# Signing with a certificate instead yields `identifier "..." and certificate
# root = H"..."`, which is stable across rebuilds, so the grant survives. The
# certificate is self-signed and used only on this machine; it does not need to
# be trusted in Keychain Access for codesign to accept it. Create one with:
#
#   openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 \
#       -nodes -subj "/CN=$SIGN_IDENTITY/O=Local Development" \
#       -addext "basicConstraints=critical,CA:false" \
#       -addext "keyUsage=critical,digitalSignature" \
#       -addext "extendedKeyUsage=critical,codeSigning"
#   openssl pkcs12 -export -inkey key.pem -in cert.pem -out identity.p12 \
#       -passout pass:temp -name "$SIGN_IDENTITY" \
#       -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
#   security import identity.p12 -k "$HOME/Library/Keychains/login.keychain-db" \
#       -P temp -T /usr/bin/codesign -A
#
# (macOS cannot read OpenSSL 3's default PKCS#12 encryption, hence the explicit
# legacy algorithms.) For distribution this must become a Developer ID signature
# followed by notarization — see docs/PRODUCTION-CHECKLIST.md.
SIGN_IDENTITY="${SIGN_IDENTITY:-Scrollwise Local Signing}"

if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "    identity: $SIGN_IDENTITY (stable — Accessibility grant survives rebuilds)"
else
    SIGN_IDENTITY="-"
    echo "    identity: ad-hoc — macOS will drop the Accessibility grant on every rebuild"
fi

codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/Scrollwise.entitlements" \
    --options runtime \
    "$APP" 2>&1 | sed 's/^/    /'

echo "==> Verifying"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
echo "    architectures: $(lipo -archs "$APP/Contents/MacOS/ScrollwiseApp")"
echo
echo "Built: $APP"
