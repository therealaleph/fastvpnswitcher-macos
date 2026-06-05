#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT_DIR/dist/FastVPN Switcher.app"
ZIP="$ROOT_DIR/dist/FastVPN-Switcher.zip"
DMG="$ROOT_DIR/dist/FastVPN-Switcher.dmg"
DMG_ROOT="$ROOT_DIR/dist/dmgroot"

"$ROOT_DIR/test.sh"
"$ROOT_DIR/build.sh"

rm -f "$ZIP" "$DMG"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "FastVPN Switcher" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
rm -rf "$DMG_ROOT"

echo "Packaged:"
echo "  $ZIP"
echo "  $DMG"
