#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT_DIR/dist/FastVPN Switcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift "$ROOT_DIR/tools/generate-icon.swift" "$ROOT_DIR" >/dev/null
cp "$ROOT_DIR/menu/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT_DIR/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/assets/FastVPNSwitcherIcon.png" "$APP/Contents/Resources/FastVPNSwitcherIcon.png"
cp "$ROOT_DIR/scripts/fastvpn-switcher.sh" "$APP/Contents/Resources/fastvpn-switcher.sh"
chmod +x "$APP/Contents/Resources/fastvpn-switcher.sh"

swiftc -framework AppKit "$ROOT_DIR/menu/main.swift" -o "$APP/Contents/MacOS/FastVPNSwitcher"
chmod +x "$APP/Contents/MacOS/FastVPNSwitcher"

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none --identifier com.shin.fastvpnswitcher.menu "$APP" >/dev/null 2>&1 || true
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true

echo "Built: $APP"
