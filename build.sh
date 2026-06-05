#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT_DIR/dist/FastVPN Switcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT_DIR/menu/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT_DIR/scripts/fastvpn-switcher.sh" "$APP/Contents/Resources/fastvpn-switcher.sh"
chmod +x "$APP/Contents/Resources/fastvpn-switcher.sh"

swiftc -framework AppKit "$ROOT_DIR/menu/main.swift" -o "$APP/Contents/MacOS/FastVPNSwitcher"
chmod +x "$APP/Contents/MacOS/FastVPNSwitcher"

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none --identifier com.shin.fastvpnswitcher.menu "$APP" >/dev/null 2>&1 || true
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true

echo "Built: $APP"
