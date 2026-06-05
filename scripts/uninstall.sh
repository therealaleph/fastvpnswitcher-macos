#!/bin/bash

set -euo pipefail

UID_VALUE="$(id -u)"

remove_job() {
  local label="$1"
  local plist="$HOME/Library/LaunchAgents/$label.plist"

  launchctl bootout "gui/$UID_VALUE" "$plist" >/dev/null 2>&1 || true
  launchctl bootout "gui/$UID_VALUE/$label" >/dev/null 2>&1 || true
  rm -f "$plist"
}

remove_job com.shin.fastvpnswitcher.watcher
remove_job com.shin.fastvpnswitcher.menu
remove_job com.user.vpn-netbounce
remove_job com.user.vpn-netbounce-menu

rm -f "$HOME/Library/Scripts/fastvpn-switcher.sh"
rm -f "$HOME/Library/Scripts/vpn-netbounce.sh"
rm -rf "${TMPDIR:-/tmp}/fastvpn-switcher.lock"
rm -rf "${TMPDIR:-/tmp}/vpn-netbounce.lock"
pkill -f "FastVPN Switcher.app/Contents/MacOS/FastVPNSwitcher" >/dev/null 2>&1 || true
pkill -f "VPN Netbounce.app/Contents/MacOS/VPNNetbounceMenu" >/dev/null 2>&1 || true

echo "Uninstalled FastVPN Switcher"
