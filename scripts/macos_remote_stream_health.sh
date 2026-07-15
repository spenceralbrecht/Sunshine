#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${SUNSHINE_CONFIG_PATH:-${SUNSHINE_CONFIG:-$HOME/.config/sunshine/sunshine.conf}}"
PEERS=("$@")

section() {
  printf '\n== %s ==\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

print_config_value() {
  local key="$1"
  if [ -f "$CONFIG_PATH" ]; then
    awk -F '=' -v wanted="$key" '
      $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        print wanted " = " $2
      }
    ' "$CONFIG_PATH"
  fi
}

section "Sunshine Config"
printf 'config: %s\n' "$CONFIG_PATH"
if [ -f "$CONFIG_PATH" ]; then
  for key in upnp origin_web_ui_allowed address_family lan_encryption_mode wan_encryption_mode encoder vt_software vt_realtime minimum_fps_target max_bitrate qp hevc_mode av1_mode; do
    value="$(print_config_value "$key")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
    fi
  done
else
  printf 'missing config file\n'
fi

section "Safety Notes"
lan_mode="$(print_config_value "lan_encryption_mode" | awk -F '= ' '{print $2}')"
upnp_mode="$(print_config_value "upnp" | awk -F '= ' '{print $2}')"
web_origin="$(print_config_value "origin_web_ui_allowed" | awk -F '= ' '{print $2}')"
case "${lan_mode:-0}" in
  1 | 2)
    printf 'OK: LAN stream encryption is not disabled.\n'
    ;;
  0)
    printf 'WARN: LAN stream encryption is disabled or unset (the default). Tailscale addresses are classified as LAN by Sunshine.\n'
    ;;
  *)
    printf 'WARN: LAN stream encryption mode is invalid; Sunshine may use the disabled default.\n'
    ;;
esac
if [ "${upnp_mode:-}" = "enabled" ]; then
  printf 'WARN: UPnP is enabled and can expose ports through the router.\n'
else
  printf 'OK: UPnP is not enabled.\n'
fi
if [ "${web_origin:-}" = "pc" ]; then
  printf 'OK: Web UI is localhost-only.\n'
else
  printf 'WARN: Web UI origin is not localhost-only: %s\n' "${web_origin:-unset}"
fi

section "Tailscale Status"
if have tailscale; then
  tailscale status || printf 'tailscale status failed with exit code %s\n' "$?"
else
  printf 'tailscale command not found\n'
fi

section "Tailscale Peer Ping"
if ! have tailscale; then
  printf 'tailscale command not found\n'
elif [ "${#PEERS[@]}" -eq 0 ]; then
  printf 'no peers supplied; skipping peer ping\n'
else
  for peer in "${PEERS[@]}"; do
    printf '\n-- %s --\n' "$peer"
    tailscale ping --c 3 "$peer" || true
  done
fi

section "Local Interfaces"
if have tailscale; then
  if ts_ip="$(tailscale ip -4 2>/dev/null)"; then
    printf 'tailscale ip: %s\n' "$(printf '%s' "$ts_ip" | tr '\n' ' ')"
  else
    printf 'tailscale ip failed with exit code %s\n' "$?"
  fi
fi
route get default 2>/dev/null | awk '/interface:|gateway:/{gsub(/^[[:space:]]+/, ""); print}' || true
scutil --nwi 2>/dev/null | awk '/Network information|IPv4 network interface information|Reachable|utun|en[0-9]/{print}' || true

section "CPU Snapshot"
if ps_output="$(ps -axo pid,pcpu,rss,comm 2>&1)"; then
  printf "%8s %7s %9s %s\n" "PID" "%CPU" "RSS_MB" "COMMAND"
  printf '%s\n' "$ps_output" | awk '
    NR == 1 {next}
    /Sunshine|sunshine|IPNExtension|Tailscale|WindowServer|VTEncoderXPCService/ {
      label=$4
      if ($4 ~ /WindowServer/) label="WindowServer"
      else if ($4 ~ /VTEncoderXPCService/) label="VTEncoderXPCService"
      else if ($4 ~ /IPNExtension/) label="Tailscale IPNExtension"
      else if ($4 ~ /Tailscale/) label="Tailscale app"
      else if ($4 ~ /Sunshine|sunshine/) label="Sunshine"
      printf "%8s %7s %9.1f %s\n", $1, $2, $3 / 1024.0, label
    }
  ' | sort -k2 -nr
else
  printf 'ps failed: %s\n' "$ps_output"
fi

section "Sunshine Listeners"
if have lsof; then
  lsof -nP -iTCP -iUDP | awk '
    /Sunshine|sunshine/ && /LISTEN|UDP/ { print }
  ' || true
else
  printf 'lsof command not found\n'
fi
