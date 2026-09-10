#!/bin/bash
# Assembles Scrollwise.app from the SwiftPM build product.
#
# A hand-assembled bundle rather than an Xcode target because this tree builds
# with the Command Line Tools toolchain alone. The layout is identical to what
# Xcode produces, so importing it into an Xcode project later changes nothing
# about the result.
#
#   Scripts/build-app.sh                # universal (arm64 + x86_64), release
#   ARCHS=arm64 Scripts/build-app.sh    # one slice, for a quicker local build
#   SIGN_IDENTITY="Developer ID Application: …" Scripts/build-app.sh
set -euo pipefail

CONFIG="${1:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="26.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Scrollwise.app"

cd "$ROOT"

# One slice per architecture, then lipo. `swift build --arch a --arch b` would
# do this in one step but needs XCBuild, which ships only with Xcode; building
# each triple separately works with Command Line Tools too. Each slice gets its
# own scratch directory so the two never share intermediate products.
echo "==> Building ($CONFIG: $ARCHS)"
SLICES=()
for arch in $ARCHS; do
    scratch="$ROOT/.build/arch-$arch"
    triple="$arch-apple-macosx$MIN_MACOS"
    swift build -c "$CONFIG" --product ScrollwiseApp --triple "$triple" --scratch-path "$scratch"
    SLICES+=("$(swift build -c "$CONFIG" --product ScrollwiseApp --triple "$triple" \
        --scratch-path "$scratch" --show-bin-path)/ScrollwiseApp")
done

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/ScrollwiseApp"
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

# Nothing but the executable, Info.plist, PkgInfo and the icon belongs in the
# bundle; extended attributes from the build tree would break the seal.
# (macOS's xattr has no recursive flag, hence find.)
find "$APP" -exec xattr -c {} +

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
    echo "    identity: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    echo "    identity: ad-hoc — macOS will drop the Accessibility grant on every rebuild"
fi

# Notarization requires a secure timestamp; a local or ad-hoc signature cannot
# obtain one, and asking would fail the build for no benefit.
case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) TIMESTAMP="--timestamp" ;;
    *) TIMESTAMP="--timestamp=none" ;;
esac

# No --deep: the bundle holds no nested code, and --deep is deprecated for
# signing because it applies one set of options to everything it finds.
codesign --force \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/Scrollwise.entitlements" \
    --options runtime \
    "$TIMESTAMP" \
    "$APP" 2>&1 | sed 's/^/    /'

echo "==> Verifying"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
BUILT_ARCHS="$(lipo -archs "$APP/Contents/MacOS/ScrollwiseApp")"
echo "    architectures: $BUILT_ARCHS"
for arch in $ARCHS; do
    case " $BUILT_ARCHS " in
        *" $arch "*) ;;
        *) echo "    error: $arch slice missing"; exit 1 ;;
    esac
done
echo
echo "Built: $APP"
