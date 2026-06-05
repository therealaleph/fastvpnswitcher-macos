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

echo "ok"
