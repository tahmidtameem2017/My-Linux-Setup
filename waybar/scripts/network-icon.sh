#!/usr/bin/env bash
# Echo the network SVG path (+ tooltip) for waybar's image#network module.
ICON_DIR="$(dirname "$0")/../icons"

if ! command -v nmcli >/dev/null 2>&1; then
  echo "$ICON_DIR/empty.svg"
  echo "nmcli not found"
  exit 0
fi

WIFI_STATE="$(nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^wifi:' | cut -d: -f2)"
if [[ "$WIFI_STATE" == "connected" ]]; then
  SSID="$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2-)"
  echo "$ICON_DIR/wifi.svg"
  echo "${SSID:-Connected} — click: nmtui"
else
  ETH_STATE="$(nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^ethernet:' | cut -d: -f2)"
  if [[ "$ETH_STATE" == "connected" ]]; then
    echo "$ICON_DIR/wifi.svg"
    echo "Wired — click: nmtui"
  else
    echo "$ICON_DIR/wifi-off.svg"
    echo "Disconnected — click: nmtui"
  fi
fi
