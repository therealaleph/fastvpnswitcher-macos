#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "shell syntax"
bash -n "$ROOT_DIR/build.sh"
bash -n "$ROOT_DIR/package.sh"
bash -n "$ROOT_DIR/install.sh"
bash -n "$ROOT_DIR/scripts/fastvpn-switcher.sh"
bash -n "$ROOT_DIR/scripts/install-watcher.sh"
bash -n "$ROOT_DIR/scripts/uninstall.sh"

echo "plist"
plutil -lint "$ROOT_DIR/menu/Info.plist"

echo "swift compile"
swiftc -framework AppKit "$ROOT_DIR/menu/main.swift" -o "$TMP_DIR/FastVPNSwitcher"

echo "icon assets"
swift "$ROOT_DIR/tools/generate-icon.swift" "$ROOT_DIR" >/dev/null
test -f "$ROOT_DIR/assets/AppIcon.icns"
test -f "$ROOT_DIR/assets/FastVPNSwitcherIcon.png"
sips -g pixelWidth -g pixelHeight "$ROOT_DIR/assets/FastVPNSwitcherIcon.png" 2>/dev/null | grep -q 'pixelWidth: 1024'
sips -g pixelWidth -g pixelHeight "$ROOT_DIR/assets/FastVPNSwitcherIcon.png" 2>/dev/null | grep -q 'pixelHeight: 1024'

echo "provider detection: warp"
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/config" "$TMP_DIR/logs"
cat > "$TMP_DIR/bin/warp-cli" <<'EOF'
#!/bin/bash
case "$*" in
  *status*) echo "Status update: Connected" ;;
  *disconnect*) echo "disconnect" ;;
  *connect*) echo "connect" ;;
esac
EOF
chmod +x "$TMP_DIR/bin/warp-cli"
FASTVPN_EXTRA_PATH="$TMP_DIR/bin" FASTVPN_PROVIDER_IDS="cloudflare_warp" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  "$ROOT_DIR/scripts/fastvpn-switcher.sh" --status | grep -q '^cloudflare_warp|Cloudflare WARP|'

echo "provider detection: pia"
rm -f "$TMP_DIR/bin/warp-cli"
cat > "$TMP_DIR/bin/piactl" <<'EOF'
#!/bin/bash
if [ "$1" = "get" ] && [ "$2" = "connectionstate" ]; then
  echo "Connected"
elif [ "$1" = "disconnect" ] || [ "$1" = "connect" ]; then
  echo "$1"
fi
EOF
chmod +x "$TMP_DIR/bin/piactl"
FASTVPN_EXTRA_PATH="$TMP_DIR/bin" FASTVPN_PROVIDER_IDS="pia" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  "$ROOT_DIR/scripts/fastvpn-switcher.sh" --status | grep -q '^pia|Private Internet Access|'

echo "notifications setting"
FASTVPN_EXTRA_PATH="$TMP_DIR/bin" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  "$ROOT_DIR/scripts/fastvpn-switcher.sh" --notifications off | grep -q '^off$'
FASTVPN_EXTRA_PATH="$TMP_DIR/bin" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  "$ROOT_DIR/scripts/fastvpn-switcher.sh" --notifications-status | grep -q '^off$'

echo "watcher: manual disconnect does not reconnect"
rm -rf "$TMP_DIR/bin" "$TMP_DIR/config" "$TMP_DIR/logs"
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/config" "$TMP_DIR/logs"
printf '%s\n' connected > "$TMP_DIR/vpn-state"
printf '%s\n' Home > "$TMP_DIR/ssid"
printf '%s\n' notifications=0 > "$TMP_DIR/config/config"
cat > "$TMP_DIR/bin/scutil" <<'EOF'
#!/bin/bash
if [ "$1" = "--nwi" ]; then
  cat <<NWI
Network information

IPv4 network interface information
     en0 : flags      : 0x5 (IPv4,DNS)
           address    : 192.168.1.25
           reach      : 0x00000002 (Reachable)

Network interfaces: en0 utun0
NWI
fi
EOF
cat > "$TMP_DIR/bin/networksetup" <<EOF
#!/bin/bash
if [ "\$1" = "-listallhardwareports" ]; then
  cat <<PORTS
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: 00:00:00:00:00:00
PORTS
elif [ "\$1" = "-getairportnetwork" ]; then
  echo "Current Wi-Fi Network: \$(cat "$TMP_DIR/ssid")"
fi
EOF
cat > "$TMP_DIR/bin/warp-cli" <<EOF
#!/bin/bash
case "\$*" in
  *status*)
    if [ "\$(cat "$TMP_DIR/vpn-state")" = connected ]; then
      echo "Status update: Connected"
    else
      echo "Status update: Disconnected"
    fi
    ;;
  *disconnect*) echo disconnect >> "$TMP_DIR/actions" ;;
  *connect*) echo connect >> "$TMP_DIR/actions" ;;
esac
EOF
chmod +x "$TMP_DIR/bin/scutil" "$TMP_DIR/bin/networksetup" "$TMP_DIR/bin/warp-cli"
TMPDIR="$TMP_DIR" FASTVPN_EXTRA_PATH="$TMP_DIR/bin" FASTVPN_PROVIDER_IDS="cloudflare_warp" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  POLL_SECONDS=1 DEBOUNCE_SECONDS=1 "$ROOT_DIR/scripts/fastvpn-switcher.sh" --watch &
watch_pid=$!
sleep 2
printf '%s\n' disconnected > "$TMP_DIR/vpn-state"
sleep 3
kill -TERM "$watch_pid" >/dev/null 2>&1 || true
wait "$watch_pid" 2>/dev/null || true
test ! -s "$TMP_DIR/actions"
rm -rf "$TMP_DIR/fastvpn-switcher.lock"

echo "watcher: network change reconnects active vpn"
rm -rf "$TMP_DIR/config" "$TMP_DIR/logs"
mkdir -p "$TMP_DIR/config" "$TMP_DIR/logs"
rm -f "$TMP_DIR/actions"
printf '%s\n' connected > "$TMP_DIR/vpn-state"
printf '%s\n' Home > "$TMP_DIR/ssid"
printf '%s\n' notifications=0 > "$TMP_DIR/config/config"
TMPDIR="$TMP_DIR" FASTVPN_EXTRA_PATH="$TMP_DIR/bin" FASTVPN_PROVIDER_IDS="cloudflare_warp" CONFIG_DIR="$TMP_DIR/config" LOG_DIR="$TMP_DIR/logs" \
  POLL_SECONDS=1 DEBOUNCE_SECONDS=1 "$ROOT_DIR/scripts/fastvpn-switcher.sh" --watch &
watch_pid=$!
sleep 2
printf '%s\n' Office > "$TMP_DIR/ssid"
for _ in 1 2 3 4 5 6 7 8; do
  if grep -q '^disconnect$' "$TMP_DIR/actions" 2>/dev/null && grep -q '^connect$' "$TMP_DIR/actions" 2>/dev/null; then
    break
  fi
  sleep 1
done
kill -TERM "$watch_pid" >/dev/null 2>&1 || true
wait "$watch_pid" 2>/dev/null || true
if ! grep -q '^disconnect$' "$TMP_DIR/actions" 2>/dev/null || ! grep -q '^connect$' "$TMP_DIR/actions" 2>/dev/null; then
  echo "expected reconnect actions were not recorded"
  echo "--- actions ---"
  cat "$TMP_DIR/actions" 2>/dev/null || true
  echo "--- watcher log ---"
  cat "$TMP_DIR/logs/fastvpn-switcher.log" 2>/dev/null || true
  echo "--- lock ---"
  find "$TMP_DIR/fastvpn-switcher.lock" -maxdepth 2 -type f -print -exec cat {} \; 2>/dev/null || true
  exit 1
fi

echo "ok"
