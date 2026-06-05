#!/bin/bash

set -u

APP_NAME="FastVPN Switcher"
export PATH="${FASTVPN_EXTRA_PATH:+$FASTVPN_EXTRA_PATH:}/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export TAILSCALE_BE_CLI="${TAILSCALE_BE_CLI:-1}"

POLL_SECONDS="${POLL_SECONDS:-1}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-2}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-10}"
LAST_VPN_WINDOW_SECONDS="${LAST_VPN_WINDOW_SECONDS:-90}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/Library/Application Support/FastVPN Switcher}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/config}"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/fastvpn-switcher.log}"
LOCK_DIR="${TMPDIR:-/tmp}/fastvpn-switcher.lock"

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

now() {
  date +%s
}

usage() {
  cat <<'EOF'
FastVPN Switcher

Usage:
  fastvpn-switcher.sh                 Watch network changes
  fastvpn-switcher.sh --watch         Watch network changes
  fastvpn-switcher.sh --status        Print active provider as id|name|detail
  fastvpn-switcher.sh --status-human  Print human-readable VPN status
  fastvpn-switcher.sh --reconnect-current
  fastvpn-switcher.sh --reconnect-provider <id> [detail]
  fastvpn-switcher.sh --list-providers
  fastvpn-switcher.sh --notifications-status
  fastvpn-switcher.sh --notifications on|off
EOF
}

config_get() {
  local key="$1"
  local default_value="$2"

  if [ -f "$CONFIG_FILE" ]; then
    awk -F= -v key="$key" '
      $1 == key {
        sub(/^[^=]*=/, "")
        print
        found=1
        exit
      }
      END {
        if (!found) exit 1
      }
    ' "$CONFIG_FILE" 2>/dev/null || printf '%s\n' "$default_value"
  else
    printf '%s\n' "$default_value"
  fi
}

config_set() {
  local key="$1"
  local value="$2"
  local tmp="$CONFIG_FILE.tmp.$$"

  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    awk -F= -v key="$key" '$1 != key { print }' "$CONFIG_FILE" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

notifications_enabled() {
  [ "$(config_get notifications 1)" = "1" ]
}

notifier_path() {
  local candidate

  for candidate in \
    "${FASTVPN_NOTIFIER:-}" \
    "/Applications/FastVPN Switcher.app/Contents/MacOS/FastVPNSwitcher" \
    "$HOME/Applications/FastVPN Switcher.app/Contents/MacOS/FastVPNSwitcher"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

app_bundle_path() {
  local candidate

  for candidate in \
    "${FASTVPN_APP_BUNDLE:-}" \
    "/Applications/FastVPN Switcher.app" \
    "$HOME/Applications/FastVPN Switcher.app"; do
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

menu_app_running() {
  pgrep -x FastVPNSwitcher >/dev/null 2>&1
}

notify() {
  local title="$1"
  local body="$2"
  local notifier
  local app_bundle

  notifications_enabled || return 0

  notifier="$(notifier_path || true)"
  if [ -n "$notifier" ] && menu_app_running; then
    "$notifier" --post-notification "$title" "$body" >> "$LOG_FILE" 2>&1 && return 0
  fi

  app_bundle="$(app_bundle_path || true)"
  if [ -n "$app_bundle" ]; then
    /usr/bin/open -g "$app_bundle" --args --notify "$title" "$body" >> "$LOG_FILE" 2>&1 && return 0
  fi

  if [ -n "$notifier" ]; then
    "$notifier" --notify "$title" "$body" >> "$LOG_FILE" 2>&1 && return 0
  fi

  command -v osascript >/dev/null 2>&1 || return 0

  /usr/bin/osascript >/dev/null 2>&1 <<EOF || true
display notification "$(printf '%s' "$body" | sed 's/"/\\"/g')" with title "$APP_NAME" subtitle "$(printf '%s' "$title" | sed 's/"/\\"/g')"
EOF
}

find_cmd() {
  local candidate

  for candidate in "$@"; do
    if [ -z "$candidate" ]; then
      continue
    fi
    if printf '%s' "$candidate" | grep -q '/'; then
      if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    elif command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  return 1
}

is_positive_connected() {
  grep -Eiq '(^|[^[:alpha:]])connected([^[:alpha:]]|$)|connection state:[[:space:]]*connected|status:[[:space:]]*connected|connect state:[[:space:]]*connected'
}

is_negative_connection() {
  grep -Eiq 'disconnected|not connected|not running|logged out|stopped|unable|error'
}

emit_status() {
  printf '%s|%s|%s\n' "$1" "$2" "$3"
}

provider_name() {
  case "$1" in
    apple) printf '%s\n' "Apple VPN Service" ;;
    cisco) printf '%s\n' "Cisco Secure Client" ;;
    cloudflare_warp) printf '%s\n' "Cloudflare WARP" ;;
    cyberghost) printf '%s\n' "CyberGhost CLI" ;;
    expressvpn) printf '%s\n' "ExpressVPN" ;;
    globalprotect) printf '%s\n' "GlobalProtect" ;;
    ivpn) printf '%s\n' "IVPN" ;;
    mullvad) printf '%s\n' "Mullvad" ;;
    nordvpn) printf '%s\n' "NordVPN" ;;
    openvpn_connect) printf '%s\n' "OpenVPN Connect" ;;
    pia) printf '%s\n' "Private Internet Access" ;;
    pritunl) printf '%s\n' "Pritunl" ;;
    protonvpn) printf '%s\n' "Proton VPN CLI" ;;
    tailscale) printf '%s\n' "Tailscale" ;;
    windscribe) printf '%s\n' "Windscribe" ;;
    wireguard) printf '%s\n' "WireGuard" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

provider_ids() {
  if [ -n "${FASTVPN_PROVIDER_IDS:-}" ]; then
    printf '%s\n' "$FASTVPN_PROVIDER_IDS" | tr ', ' '\n\n' | awk 'NF'
    return 0
  fi

  printf '%s\n' \
    apple \
    cisco \
    cloudflare_warp \
    cyberghost \
    expressvpn \
    globalprotect \
    ivpn \
    mullvad \
    nordvpn \
    openvpn_connect \
    pia \
    pritunl \
    protonvpn \
    tailscale \
    windscribe \
    wireguard
}

network_fingerprint() {
  {
    networksetup -listallhardwareports 2>/dev/null | awk '
      /^Hardware Port:/ {
        port=$0
        sub(/^Hardware Port:[[:space:]]*/, "", port)
        next
      }
      /^Device:[[:space:]]*en[0-9]+$/ {
        print $2 "|" port
      }
    ' | while IFS='|' read -r device port; do
      [ -n "$device" ] || continue

      printf 'iface=%s port=%s\n' "$device" "$port"

      ifconfig "$device" 2>/dev/null | awk -v device="$device" '
        /^[[:space:]]*status:/ {
          print "iface=" device " status=" $2
          exit
        }
      '

      ipconfig getifaddr "$device" 2>/dev/null | awk -v device="$device" '
        NF {
          print "iface=" device " ipv4=" $0
          exit
        }
      '

      case "$port" in
        Wi-Fi|AirPort)
          wifi_line="$(networksetup -getairportnetwork "$device" 2>/dev/null || true)"
          case "$wifi_line" in
            "Current Wi-Fi Network: "*)
              printf 'wifi=%s ssid=%s\n' "$device" "${wifi_line#Current Wi-Fi Network: }"
              ;;
            *"not associated"*)
              printf 'wifi=%s ssid=\n' "$device"
              ;;
            *)
              [ -n "$wifi_line" ] && printf 'wifi=%s raw=%s\n' "$device" "$wifi_line"
              ;;
          esac
          ;;
      esac
    done
  } | LC_ALL=C sort | shasum | awk '{print $1}'
}

status_apple() {
  local service

  service="$(scutil --nc list 2>/dev/null | awk -F'"' '/\(Connected\)/ && NF >= 2 { print $2; exit }')"
  if [ -n "$service" ]; then
    emit_status apple "$(provider_name apple)" "$service"
    return 0
  fi

  return 1
}

reconnect_apple() {
  local service="$1"

  [ -n "$service" ] || return 1
  scutil --nc stop "$service" >> "$LOG_FILE" 2>&1 || true
  sleep 1
  scutil --nc start "$service" >> "$LOG_FILE" 2>&1
}

status_cisco() {
  local vpn out

  [ -n "${FASTVPN_CISCO_SERVER:-}" ] || return 1
  vpn="$(find_cmd /opt/cisco/secureclient/bin/vpn /opt/cisco/anyconnect/bin/vpn vpn)" || return 1
  out="$("$vpn" state 2>&1 || true)"
  if printf '%s\n' "$out" | is_positive_connected && ! printf '%s\n' "$out" | is_negative_connection; then
    emit_status cisco "$(provider_name cisco)" "$FASTVPN_CISCO_SERVER"
    return 0
  fi

  return 1
}

reconnect_cisco() {
  local vpn server="$1"

  server="${server:-${FASTVPN_CISCO_SERVER:-}}"
  [ -n "$server" ] || return 1
  vpn="$(find_cmd /opt/cisco/secureclient/bin/vpn /opt/cisco/anyconnect/bin/vpn vpn)" || return 1
  "$vpn" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$vpn" connect "$server" >> "$LOG_FILE" 2>&1
}

status_cloudflare_warp() {
  local warp out

  warp="$(find_cmd warp-cli)" || return 1
  out="$("$warp" --no-ansi status 2>&1 || "$warp" status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq 'Status update:[[:space:]]*Connected|^Connected$'; then
    emit_status cloudflare_warp "$(provider_name cloudflare_warp)" ""
    return 0
  fi

  return 1
}

reconnect_cloudflare_warp() {
  local warp

  warp="$(find_cmd warp-cli)" || return 1
  "$warp" --no-ansi disconnect >> "$LOG_FILE" 2>&1 || "$warp" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$warp" --no-ansi connect >> "$LOG_FILE" 2>&1 || "$warp" connect >> "$LOG_FILE" 2>&1
}

status_cyberghost() {
  local cyberghost out

  [ -n "${FASTVPN_CYBERGHOST_CONNECT_ARGS:-}" ] || return 1
  cyberghost="$(find_cmd cyberghostvpn)" || return 1
  out="$("$cyberghost" --status 2>&1 || true)"
  if printf '%s\n' "$out" | is_positive_connected && ! printf '%s\n' "$out" | is_negative_connection; then
    emit_status cyberghost "$(provider_name cyberghost)" "$FASTVPN_CYBERGHOST_CONNECT_ARGS"
    return 0
  fi

  return 1
}

reconnect_cyberghost() {
  local cyberghost args_string

  cyberghost="$(find_cmd cyberghostvpn)" || return 1
  args_string="${1:-${FASTVPN_CYBERGHOST_CONNECT_ARGS:-}}"
  [ -n "$args_string" ] || return 1
  "$cyberghost" --stop >> "$LOG_FILE" 2>&1 || true
  sleep 1
  # shellcheck disable=SC2086
  "$cyberghost" $args_string >> "$LOG_FILE" 2>&1
}

status_expressvpn() {
  local express out

  express="$(find_cmd expressvpnctl /Applications/ExpressVPN.app/Contents/MacOS/expressvpnctl /Applications/ExpressVPN.app/Contents/Resources/expressvpnctl)" || return 1
  out="$("$express" status 2>&1 || true)"
  if printf '%s\n' "$out" | is_positive_connected && ! printf '%s\n' "$out" | is_negative_connection; then
    emit_status expressvpn "$(provider_name expressvpn)" ""
    return 0
  fi

  return 1
}

reconnect_expressvpn() {
  local express

  express="$(find_cmd expressvpnctl /Applications/ExpressVPN.app/Contents/MacOS/expressvpnctl /Applications/ExpressVPN.app/Contents/Resources/expressvpnctl)" || return 1
  "$express" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$express" connect >> "$LOG_FILE" 2>&1
}

status_globalprotect() {
  local gp out

  gp="$(find_cmd globalprotect /Applications/GlobalProtect.app/Contents/Resources/globalprotect)" || return 1
  out="$("$gp" show --status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq 'GlobalProtect status:[[:space:]]*Connected|Status:[[:space:]]*Connected'; then
    emit_status globalprotect "$(provider_name globalprotect)" ""
    return 0
  fi

  return 1
}

reconnect_globalprotect() {
  local gp

  gp="$(find_cmd globalprotect /Applications/GlobalProtect.app/Contents/Resources/globalprotect)" || return 1
  "$gp" rediscover-network >> "$LOG_FILE" 2>&1 || {
    "$gp" disconnect >> "$LOG_FILE" 2>&1 || true
    sleep 1
    "$gp" connect >> "$LOG_FILE" 2>&1
  }
}

status_ivpn() {
  local ivpn out

  ivpn="$(find_cmd ivpn /Applications/IVPN.app/Contents/MacOS/ivpn)" || return 1
  out="$("$ivpn" status 2>&1 || true)"
  if printf '%s\n' "$out" | is_positive_connected && ! printf '%s\n' "$out" | is_negative_connection; then
    emit_status ivpn "$(provider_name ivpn)" "${FASTVPN_IVPN_CONNECT_ARGS:--fastest}"
    return 0
  fi

  return 1
}

reconnect_ivpn() {
  local ivpn args_string

  ivpn="$(find_cmd ivpn /Applications/IVPN.app/Contents/MacOS/ivpn)" || return 1
  args_string="${1:-${FASTVPN_IVPN_CONNECT_ARGS:--fastest}}"
  "$ivpn" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  # shellcheck disable=SC2086
  "$ivpn" connect $args_string >> "$LOG_FILE" 2>&1
}

status_mullvad() {
  local mullvad out

  mullvad="$(find_cmd mullvad)" || return 1
  out="$("$mullvad" status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq '^Connected($|[[:space:]])'; then
    emit_status mullvad "$(provider_name mullvad)" ""
    return 0
  fi

  return 1
}

reconnect_mullvad() {
  local mullvad

  mullvad="$(find_cmd mullvad)" || return 1
  "$mullvad" reconnect >> "$LOG_FILE" 2>&1 || {
    "$mullvad" disconnect >> "$LOG_FILE" 2>&1 || true
    sleep 1
    "$mullvad" connect >> "$LOG_FILE" 2>&1
  }
}

status_nordvpn() {
  local nord out

  nord="$(find_cmd nordvpn)" || return 1
  out="$("$nord" status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq 'Status:[[:space:]]*Connected|^Connected$'; then
    emit_status nordvpn "$(provider_name nordvpn)" ""
    return 0
  fi

  return 1
}

reconnect_nordvpn() {
  local nord

  nord="$(find_cmd nordvpn)" || return 1
  "$nord" disconnect >> "$LOG_FILE" 2>&1 || "$nord" d >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$nord" connect >> "$LOG_FILE" 2>&1 || "$nord" c >> "$LOG_FILE" 2>&1
}

status_openvpn_connect() {
  local ovpn

  [ -n "${FASTVPN_OPENVPN_PROFILE_ID:-}" ] || return 1
  [ "${FASTVPN_OPENVPN_AUTODETECT:-0}" = "1" ] || return 1
  ovpn="$(find_cmd "/Applications/OpenVPN Connect.app/Contents/MacOS/OpenVPN Connect" "/Applications/OpenVPN Connect/OpenVPN Connect.app/Contents/MacOS/OpenVPN Connect")" || return 1
  pgrep -f "$ovpn" >/dev/null 2>&1 || return 1
  emit_status openvpn_connect "$(provider_name openvpn_connect)" "$FASTVPN_OPENVPN_PROFILE_ID"
}

reconnect_openvpn_connect() {
  local ovpn profile_id="$1"

  profile_id="${profile_id:-${FASTVPN_OPENVPN_PROFILE_ID:-}}"
  [ -n "$profile_id" ] || return 1
  ovpn="$(find_cmd "/Applications/OpenVPN Connect.app/Contents/MacOS/OpenVPN Connect" "/Applications/OpenVPN Connect/OpenVPN Connect.app/Contents/MacOS/OpenVPN Connect")" || return 1
  "$ovpn" "--disconnect-shortcut=$profile_id" >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$ovpn" "--connect-shortcut=$profile_id" >> "$LOG_FILE" 2>&1
}

status_pia() {
  local pia out

  pia="$(find_cmd piactl "/Applications/Private Internet Access.app/Contents/MacOS/piactl")" || return 1
  out="$("$pia" get connectionstate 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq '^Connected$|^StillConnected$|^Still Connected$'; then
    emit_status pia "$(provider_name pia)" ""
    return 0
  fi

  return 1
}

reconnect_pia() {
  local pia

  pia="$(find_cmd piactl "/Applications/Private Internet Access.app/Contents/MacOS/piactl")" || return 1
  "$pia" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$pia" connect >> "$LOG_FILE" 2>&1
}

status_pritunl() {
  local pritunl out profile_id

  pritunl="$(find_cmd pritunl-client /Applications/Pritunl.app/Contents/Resources/pritunl-client)" || return 1
  out="$("$pritunl" list 2>&1 || true)"
  printf '%s\n' "$out" | is_positive_connected || return 1
  profile_id="${FASTVPN_PRITUNL_PROFILE_ID:-$(printf '%s\n' "$out" | awk 'tolower($0) ~ /connected/ { print $1; exit }')}"
  [ -n "$profile_id" ] || return 1
  emit_status pritunl "$(provider_name pritunl)" "$profile_id"
}

reconnect_pritunl() {
  local pritunl profile_id="$1"

  profile_id="${profile_id:-${FASTVPN_PRITUNL_PROFILE_ID:-}}"
  [ -n "$profile_id" ] || return 1
  pritunl="$(find_cmd pritunl-client /Applications/Pritunl.app/Contents/Resources/pritunl-client)" || return 1
  "$pritunl" stop "$profile_id" >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$pritunl" start "$profile_id" >> "$LOG_FILE" 2>&1
}

status_protonvpn() {
  local proton out base

  proton="$(find_cmd protonvpn protonvpn-cli)" || return 1
  base="$(basename "$proton")"
  out="$("$proton" status 2>&1 || true)"
  if printf '%s\n' "$out" | is_positive_connected && ! printf '%s\n' "$out" | is_negative_connection; then
    emit_status protonvpn "$(provider_name protonvpn)" "$base"
    return 0
  fi

  return 1
}

reconnect_protonvpn() {
  local proton base

  proton="$(find_cmd protonvpn protonvpn-cli)" || return 1
  base="$(basename "$proton")"
  if [ "$base" = "protonvpn-cli" ]; then
    "$proton" d >> "$LOG_FILE" 2>&1 || true
    sleep 1
    "$proton" c -f >> "$LOG_FILE" 2>&1
  else
    "$proton" disconnect >> "$LOG_FILE" 2>&1 || true
    sleep 1
    "$proton" connect >> "$LOG_FILE" 2>&1
  fi
}

status_tailscale() {
  local tailscale out

  tailscale="$(find_cmd tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale)" || return 1
  out="$("$tailscale" status --json 2>&1 || "$tailscale" status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq '"BackendState"[[:space:]]*:[[:space:]]*"Running"|^100\.'; then
    emit_status tailscale "$(provider_name tailscale)" ""
    return 0
  fi

  return 1
}

reconnect_tailscale() {
  local tailscale

  tailscale="$(find_cmd tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale)" || return 1
  "$tailscale" down >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$tailscale" up >> "$LOG_FILE" 2>&1
}

status_windscribe() {
  local windscribe out

  windscribe="$(find_cmd windscribe-cli /Applications/Windscribe.app/Contents/MacOS/windscribe-cli)" || return 1
  out="$("$windscribe" status 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eiq 'Connect state:[[:space:]]*Connected|^Connected($|:)'; then
    emit_status windscribe "$(provider_name windscribe)" ""
    return 0
  fi

  return 1
}

reconnect_windscribe() {
  local windscribe

  windscribe="$(find_cmd windscribe-cli /Applications/Windscribe.app/Contents/MacOS/windscribe-cli)" || return 1
  "$windscribe" disconnect >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$windscribe" connect >> "$LOG_FILE" 2>&1
}

wireguard_config_for_interface() {
  local iface="$1"
  local cfg

  for cfg in \
    "/usr/local/etc/wireguard/$iface.conf" \
    "/opt/homebrew/etc/wireguard/$iface.conf" \
    "/etc/wireguard/$iface.conf"; do
    if [ -f "$cfg" ]; then
      printf '%s\n' "$cfg"
      return 0
    fi
  done

  return 1
}

status_wireguard() {
  local wg iface cfg

  wg="$(find_cmd wg)" || return 1
  find_cmd wg-quick >/dev/null 2>&1 || return 1

  for iface in $("$wg" show interfaces 2>/dev/null); do
    cfg="$(wireguard_config_for_interface "$iface" || true)"
    if [ -n "$cfg" ]; then
      emit_status wireguard "$(provider_name wireguard)" "$iface"
      return 0
    fi
  done

  return 1
}

reconnect_wireguard() {
  local iface="$1"
  local wgquick cfg

  [ -n "$iface" ] || return 1
  wgquick="$(find_cmd wg-quick)" || return 1
  cfg="$(wireguard_config_for_interface "$iface")" || return 1
  "$wgquick" down "$cfg" >> "$LOG_FILE" 2>&1 || true
  sleep 1
  "$wgquick" up "$cfg" >> "$LOG_FILE" 2>&1
}

detect_connected_vpn() {
  local id

  for id in $(provider_ids); do
    "status_$id" && return 0
  done

  return 1
}

status_human() {
  local status id name detail

  status="$(detect_connected_vpn || true)"
  if [ -z "$status" ]; then
    printf '%s\n' "VPN: none connected"
    return 1
  fi

  id="$(printf '%s' "$status" | cut -d'|' -f1)"
  name="$(printf '%s' "$status" | cut -d'|' -f2)"
  detail="$(printf '%s' "$status" | cut -d'|' -f3-)"

  if [ -n "$detail" ]; then
    printf 'VPN: %s connected (%s)\n' "$name" "$detail"
  else
    printf 'VPN: %s connected\n' "$name"
  fi
  [ -n "$id" ]
}

reconnect_provider() {
  local id="$1"
  local detail="${2:-}"
  local name

  name="$(provider_name "$id")"
  log "reconnecting $name"
  notify "Network changed" "Reconnecting $name"
  if "reconnect_$id" "$detail"; then
    log "reconnect command completed for $name"
    notify "VPN reconnect" "$name reconnect command completed"
    return 0
  fi

  log "reconnect failed for $name"
  notify "VPN reconnect failed" "$name could not be reconnected automatically"
  return 1
}

reconnect_current() {
  local status id detail

  status="$(detect_connected_vpn || true)"
  [ -n "$status" ] || return 1
  id="$(printf '%s' "$status" | cut -d'|' -f1)"
  detail="$(printf '%s' "$status" | cut -d'|' -f3-)"
  reconnect_provider "$id" "$detail"
}

list_providers() {
  local id name detected status

  for id in $(provider_ids); do
    name="$(provider_name "$id")"
    detected="no"
    if "status_$id" >/dev/null 2>&1; then
      detected="connected"
    fi
    printf '%s|%s|%s\n' "$id" "$name" "$detected"
  done
}

cleanup() {
  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

shutdown() {
  cleanup
  exit 0
}

acquire_lock() {
  local old_pid

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return 0
  fi

  if [ -f "$LOCK_DIR/pid" ]; then
    old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log "another fastvpn-switcher instance is already running with pid=$old_pid"
      exit 0
    fi
  fi

  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return 0
  fi

  log "could not acquire lock at $LOCK_DIR"
  exit 1
}

watch_loop() {
  local last_fingerprint last_vpn last_vpn_detail last_vpn_seen_at last_reconnect_at
  local current_vpn current_id current_detail current_fingerprint current_time
  local vpn_to_reconnect vpn_detail_to_reconnect

  acquire_lock
  trap cleanup EXIT
  trap shutdown INT TERM HUP

  last_fingerprint="$(network_fingerprint)"
  last_vpn=""
  last_vpn_detail=""
  last_vpn_seen_at=0
  last_reconnect_at=0

  log "started; initial network fingerprint=$last_fingerprint"

  while true; do
    sleep "$POLL_SECONDS"

    current_vpn="$(detect_connected_vpn || true)"
    if [ -n "$current_vpn" ]; then
      current_id="$(printf '%s' "$current_vpn" | cut -d'|' -f1)"
      current_detail="$(printf '%s' "$current_vpn" | cut -d'|' -f3-)"
      last_vpn="$current_id"
      last_vpn_detail="$current_detail"
      last_vpn_seen_at="$(now)"
    fi

    current_fingerprint="$(network_fingerprint)"
    if [ "$current_fingerprint" = "$last_fingerprint" ]; then
      if [ -z "$current_vpn" ] && [ -n "$last_vpn" ]; then
        log "vpn disconnected while physical network stayed the same; treating as intentional"
        last_vpn=""
        last_vpn_detail=""
        last_vpn_seen_at=0
      fi
      continue
    fi

    log "physical network fingerprint changed: $last_fingerprint -> $current_fingerprint"
    notify "Network changed" "Physical network changed"
    sleep "$DEBOUNCE_SECONDS"
    last_fingerprint="$(network_fingerprint)"

    current_time="$(now)"
    if [ $((current_time - last_reconnect_at)) -lt "$COOLDOWN_SECONDS" ]; then
      log "skipping reconnect; cooldown is active"
      continue
    fi

    current_vpn="$(detect_connected_vpn || true)"
    if [ -n "$current_vpn" ]; then
      vpn_to_reconnect="$(printf '%s' "$current_vpn" | cut -d'|' -f1)"
      vpn_detail_to_reconnect="$(printf '%s' "$current_vpn" | cut -d'|' -f3-)"
    else
      vpn_to_reconnect=""
      vpn_detail_to_reconnect=""
    fi

    if [ -z "$vpn_to_reconnect" ] && [ -n "$last_vpn" ]; then
      if [ $((current_time - last_vpn_seen_at)) -le "$LAST_VPN_WINDOW_SECONDS" ]; then
        vpn_to_reconnect="$last_vpn"
        vpn_detail_to_reconnect="$last_vpn_detail"
        log "vpn is not currently reporting connected; using recently seen vpn=$vpn_to_reconnect"
      fi
    fi

    if [ -z "$vpn_to_reconnect" ]; then
      log "network changed, but no connected or recently connected vpn was detected"
      notify "Network changed" "No connected VPN detected"
      continue
    fi

    reconnect_provider "$vpn_to_reconnect" "$vpn_detail_to_reconnect" || true
    last_reconnect_at="$(now)"
    last_vpn="$vpn_to_reconnect"
    last_vpn_detail="$vpn_detail_to_reconnect"
    last_vpn_seen_at="$last_reconnect_at"
    last_fingerprint="$(network_fingerprint)"
  done
}

case "${1:---watch}" in
  --watch)
    watch_loop
    ;;
  --status)
    detect_connected_vpn
    ;;
  --status-human)
    status_human
    ;;
  --reconnect-current)
    reconnect_current
    ;;
  --reconnect-provider)
    if [ -z "${2:-}" ]; then
      usage
      exit 2
    fi
    reconnect_provider "$2" "${3:-}"
    ;;
  --list-providers)
    list_providers
    ;;
  --notifications-status)
    if notifications_enabled; then
      printf '%s\n' "on"
    else
      printf '%s\n' "off"
    fi
    ;;
  --notifications)
    case "${2:-}" in
      on)
        config_set notifications 1
        printf '%s\n' "on"
        ;;
      off)
        config_set notifications 0
        printf '%s\n' "off"
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
