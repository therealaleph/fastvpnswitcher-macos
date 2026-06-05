#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/fastvpn-switcher.sh"
INSTALL_DIR="$HOME/Library/Scripts"
INSTALL_SCRIPT="$INSTALL_DIR/fastvpn-switcher.sh"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENT_DIR/com.shin.fastvpnswitcher.watcher.plist"
LABEL="com.shin.fastvpnswitcher.watcher"
UID_VALUE="$(id -u)"

if [ ! -f "$SOURCE_SCRIPT" ]; then
  echo "Missing $SOURCE_SCRIPT"
  exit 1
fi

stop_legacy_draft() {
  local legacy_label
  local legacy_plist

  for legacy_label in com.user.vpn-netbounce com.user.vpn-netbounce-menu; do
    legacy_plist="$HOME/Library/LaunchAgents/$legacy_label.plist"
    launchctl bootout "gui/$UID_VALUE" "$legacy_plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$UID_VALUE/$legacy_label" >/dev/null 2>&1 || true
    rm -f "$legacy_plist"
  done

  rm -f "$HOME/Library/Scripts/vpn-netbounce.sh"
  rm -rf "${TMPDIR:-/tmp}/vpn-netbounce.lock"
  pkill -f "VPN Netbounce.app/Contents/MacOS/VPNNetbounceMenu" >/dev/null 2>&1 || true
}

stop_legacy_draft

mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCH_AGENT_DIR"
install -m 755 "$SOURCE_SCRIPT" "$INSTALL_SCRIPT"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_SCRIPT</string>
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

launchctl bootout "gui/$UID_VALUE" "$PLIST" >/dev/null 2>&1 || true
launchctl enable "gui/$UID_VALUE/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

echo "Installed and started $LABEL"
echo "Watcher: $INSTALL_SCRIPT"
echo "LaunchAgent: $PLIST"
echo "Log: $HOME/Library/Logs/fastvpn-switcher.log"
