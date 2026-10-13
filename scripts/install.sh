#!/bin/bash
# Puts "build/Yaseen Screenshot.app" in /Applications and opens it.
#
# USAGE:
#   scripts/bundle.sh       First make the signed app.
#   scripts/install.sh      Then install it.
#
# The script quits the app that runs, replaces the app in /Applications, and
# opens the new one. It keeps no copy of the old app. The old versions are on
# the GitHub releases page.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Yaseen Screenshot"
SOURCE="$ROOT/build/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"

[ -d "$SOURCE" ] || { echo "error: $SOURCE is missing. Run scripts/bundle.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"

if pgrep -f "$TARGET/Contents/MacOS" >/dev/null; then
    echo "Quitting the app that runs."
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    # Wait until the old app is gone. A file write of the old app can still run.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$TARGET/Contents/MacOS" >/dev/null || break
        sleep 0.5
    done
fi

rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"
open "$TARGET"
echo "Done. $APP_NAME $VERSION is in /Applications and is open."
