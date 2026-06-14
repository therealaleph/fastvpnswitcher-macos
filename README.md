# fastvpnswitcher-macos

Menu bar helper for macOS. When Ethernet/Wi-Fi changes, it reconnects the VPN that was already active.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/therealaleph/fastvpnswitcher-macos/main/install.sh | bash
```

Releases also include a `.dmg`: open it, drag `FastVPN Switcher.app` to `Applications`, then open the app.

## Build

```sh
./test.sh
./build.sh
./package.sh
```

## Supported adapters

- Apple VPN Service: `scutil --nc`
- Cisco Secure Client: requires `FASTVPN_CISCO_SERVER`
- Cloudflare WARP: `warp-cli`
- CyberGhost CLI: requires `FASTVPN_CYBERGHOST_CONNECT_ARGS`
- ExpressVPN: `expressvpnctl`
- GlobalProtect: `globalprotect`
- IVPN: `ivpn`
- Mullvad: `mullvad`
- NordVPN: `nordvpn`
- OpenVPN Connect: requires `FASTVPN_OPENVPN_PROFILE_ID`
- Private Internet Access: `piactl`
- Pritunl: `pritunl-client`
- Proton VPN CLI: `protonvpn` or `protonvpn-cli`
- Tailscale: `tailscale`
- Windscribe: `windscribe-cli`
- WireGuard: `wg` and `wg-quick`

## Not automated

- hide.me macOS app
- Hotspot Shield macOS app
- Mozilla VPN macOS app
- PureVPN macOS app
- Surfshark macOS app
- TunnelBear macOS app
- VyprVPN macOS app

These do not currently expose a reliable macOS CLI path that can disconnect and reconnect the active tunnel without UI scripting.

## Menu

- Start/stop watcher
- Start watcher at login
- Show menu icon at login
- Reconnect current VPN
- Notifications on/off
- About links: GitHub, website, donation

## Logs

```sh
tail -f "$HOME/Library/Logs/fastvpn-switcher.log"
```

## Power behavior

The watcher uses a slow physical-network fingerprint check by default. It checks the physical network at most every 30 seconds and refreshes VPN status every 120 seconds while the network is stable.

Advanced launchd environment overrides:

- `POLL_SECONDS`: maximum seconds between physical network fingerprint checks
- `VPN_HEARTBEAT_SECONDS`: seconds between VPN status refreshes when the network is unchanged
- `FASTVPN_USE_ROUTE_MONITOR=1`: opt in to routing-socket events for faster reaction; noisier on some systems
- `FASTVPN_PROVIDER_IDS`: comma/space-separated provider IDs to scan, useful if you only use one VPN client

Credit: Shin (x.com/hey_itsmyturn)
