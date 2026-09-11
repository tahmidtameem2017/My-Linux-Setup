#!/usr/bin/env bash
# Echo the battery SVG path (+ tooltip) for waybar's image#battery module.
# Desktops without a battery get a blank icon so the bar stays clean.
ICON_DIR="$(dirname "$0")/../icons"
BAT="$(echo /sys/class/power_supply/BAT* 2>/dev/null | awk '{print $1}')"

if [[ ! -f "$BAT/capacity" ]]; then
  echo ""
  echo "No battery"
  exit 0
fi

CAP="$(cat "$BAT/capacity" 2>/dev/null)"
STATUS="$(cat "$BAT/status" 2>/dev/null)"
if [[ "$STATUS" == "Charging" ]]; then
  echo "$ICON_DIR/battery-charging.svg"
  echo "Charging: ${CAP}%"
else
  echo "$ICON_DIR/battery.svg"
  echo "Battery: ${CAP}%${STATUS:+ ($STATUS)}"
fi
