#!/bin/bash

set -euo pipefail

REPO="therealaleph/fastvpnswitcher-macos"
LABEL_WATCHER="com.shin.fastvpnswitcher.watcher"
LABEL_MENU="com.shin.fastvpnswitcher.menu"
UID_VALUE="$(id -u)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "${FASTVPN_VERSION:-latest}" = "latest" ]; then
  ASSET_URL="https://github.com/$REPO/releases/latest/download/FastVPN-Switcher.zip"
else
  ASSET_URL="https://github.com/$REPO/releases/download/$FASTVPN_VERSION/FastVPN-Switcher.zip"
fi

APP_DIR="/Applications"
if [ ! -w "$APP_DIR" ]; then
  APP_DIR="$HOME/Applications"
  mkdir -p "$APP_DIR"
fi

APP_PATH="$APP_DIR/FastVPN Switcher.app"
WATCHER_SCRIPT="$HOME/Library/Scripts/fastvpn-switcher.sh"
WATCHER_PLIST="$HOME/Library/LaunchAgents/$LABEL_WATCHER.plist"
MENU_PLIST="$HOME/Library/LaunchAgents/$LABEL_MENU.plist"

echo "Downloading FastVPN Switcher..."
curl -fsSL "$ASSET_URL" -o "$TMP_DIR/FastVPN-Switcher.zip"
ditto -x -k "$TMP_DIR/FastVPN-Switcher.zip" "$TMP_DIR"

FOUND_APP="$(find "$TMP_DIR" -name 'FastVPN Switcher.app' -type d -maxdepth 3 | head -n 1)"
if [ -z "$FOUND_APP" ]; then
  echo "Could not find FastVPN Switcher.app in release asset"
  exit 1
fi

echo "Installing app to $APP_PATH"
rm -rf "$APP_PATH"
ditto "$FOUND_APP" "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

mkdir -p "$HOME/Library/Scripts" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 755 "$APP_PATH/Contents/Resources/fastvpn-switcher.sh" "$WATCHER_SCRIPT"

for legacy_label in com.user.vpn-netbounce com.user.vpn-netbounce-menu; do
  legacy_plist="$HOME/Library/LaunchAgents/$legacy_label.plist"
  launchctl bootout "gui/$UID_VALUE" "$legacy_plist" >/dev/null 2>&1 || true
  launchctl bootout "gui/$UID_VALUE/$legacy_label" >/dev/null 2>&1 || true
  rm -f "$legacy_plist"
done
rm -f "$HOME/Library/Scripts/vpn-netbounce.sh"
rm -rf "${TMPDIR:-/tmp}/vpn-netbounce.lock"

cat > "$WATCHER_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL_WATCHER</string>
  <key>ProgramArguments</key>
  <array>
    <string>$WATCHER_SCRIPT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>TAILSCALE_BE_CLI</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/fastvpn-switcher.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/fastvpn-switcher.launchd.err.log</string>
</dict>
</plist>
EOF

cat > "$MENU_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL_MENU</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_PATH/Contents/MacOS/FastVPNSwitcher</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/fastvpn-switcher-menu.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/fastvpn-switcher-menu.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID_VALUE" "$WATCHER_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_VALUE" "$MENU_PLIST" >/dev/null 2>&1 || true
launchctl enable "gui/$UID_VALUE/$LABEL_WATCHER" >/dev/null 2>&1 || true
launchctl enable "gui/$UID_VALUE/$LABEL_MENU" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$WATCHER_PLIST"
launchctl bootstrap "gui/$UID_VALUE" "$MENU_PLIST" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$UID_VALUE/$LABEL_WATCHER"
open "$APP_PATH"

echo "Installed FastVPN Switcher"
