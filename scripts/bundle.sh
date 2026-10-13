#!/bin/bash
# Builds the release binary, makes "build/Yaseen Screenshot.app", and signs it.
#
# USAGE:
#   scripts/bundle.sh          Make the signed .app.
#   scripts/bundle.sh --dmg    Make the signed .app and the .dmg.
#
# ENVIRONMENT:
#   SIGN_IDENTITY           The name of the code signing certificate.
#                           Default: "Yaseen Local Signing".
#   REQUIRE_SIGN_IDENTITY   Set to 1 to fail if the keychain does not have the
#                           certificate. The default is an ad-hoc signature
#                           with a warning.
#
# The version comes from Support/Info.plist (CFBundleShortVersionString).
# All output goes to build/. The script removes its earlier output first.
set -euo pipefail

MAKE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg) MAKE_DMG=1 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument: $arg (use --dmg or --help)" >&2
            exit 2
            ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Yaseen Screenshot"
EXECUTABLE="YaseenScreenshot"
ARCH="arm64"
INFO_PLIST="$ROOT/Support/Info.plist"
ICON="$ROOT/Support/AppIcon.icns"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Yaseen Local Signing}"

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

[ -f "$INFO_PLIST" ] || { echo "error: $INFO_PLIST is missing" >&2; exit 1; }
[ -f "$ICON" ] || { echo "error: $ICON is missing. Run: swift scripts/make-icon.swift" >&2; exit 1; }

VERSION="$(plist_value CFBundleShortVersionString)"
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
ICON_NAME="$(plist_value CFBundleIconFile)"
DMG="$BUILD_DIR/Yaseen-Screenshot-$VERSION-$ARCH.dmg"
STAGING="$BUILD_DIR/dmg-staging"

echo "==> Build $EXECUTABLE $VERSION ($ARCH, release)"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
BINARY="$BIN_DIR/$EXECUTABLE"
[ -f "$BINARY" ] || { echo "error: the binary is not at $BINARY" >&2; exit 1; }

echo "==> Assemble $APP"
# Remove only the output of this script. Other files in build/ stay.
rm -rf "$APP" "$STAGING"
rm -f "$BUILD_DIR"/Yaseen-Screenshot-*-"$ARCH".dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
chmod 755 "$APP/Contents/MacOS/$EXECUTABLE"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/${ICON_NAME%.icns}.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Sign"
# This only reads the keychain. A self-signed certificate is not in the
# "valid" list of `security`, so the check uses the full list (no -v).
if security find-identity -p codesigning 2>/dev/null | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    SIGN_WITH="$SIGN_IDENTITY"
    echo "Signing with the certificate \"$SIGN_IDENTITY\"."
elif [ "${REQUIRE_SIGN_IDENTITY:-0}" = "1" ]; then
    echo "error: the keychain does not have the certificate \"$SIGN_IDENTITY\"." >&2
    exit 1
else
    SIGN_WITH="-"
    echo "WARNING: ad-hoc signature. macOS will not keep the Screen Recording permission after the next build."
fi
codesign --force --timestamp=none --identifier "$BUNDLE_ID" --sign "$SIGN_WITH" "$APP"

echo "==> Verify the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -E '^(designated|# designated)' || true

if [ "$MAKE_DMG" = "1" ]; then
    echo "==> Make $DMG"
    mkdir -p "$STAGING"
    # ditto keeps the signature and the extended attributes of the bundle.
    ditto "$APP" "$STAGING/$APP_NAME.app"
    ln -s /Applications "$STAGING/Applications"

    # hdiutil sometimes fails with "Resource busy" on a GitHub runner. Try again.
    attempt=1
    until hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
        -fs HFS+ -format UDZO -ov "$DMG" >/dev/null; do
        if [ "$attempt" -ge 3 ]; then
            echo "error: hdiutil create failed $attempt times" >&2
            exit 1
        fi
        attempt=$((attempt + 1))
        echo "hdiutil create failed. Attempt $attempt of 3."
        sleep 3
    done
    rm -rf "$STAGING"

    echo "==> Verify the .dmg"
    hdiutil verify "$DMG"
fi

echo "==> Done"
echo "App: $APP ($(du -sh "$APP" | cut -f1))"
if [ "$MAKE_DMG" = "1" ]; then
    echo "Dmg: $DMG ($(du -h "$DMG" | cut -f1))"
fi
