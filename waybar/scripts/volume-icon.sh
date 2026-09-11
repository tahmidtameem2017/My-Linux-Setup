#!/usr/bin/env bash
# Echo the volume SVG path (+ tooltip) for waybar's image#volume module.
ICON_DIR="$(dirname "$0")/../icons"
VOL="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"

if [[ "$VOL" == *"MUTED"* ]]; then
  echo "$ICON_DIR/volume-muted.svg"
  echo "Muted — right-click text to unmute"
else
  PCT="$(awk '{printf "%d%%", $2 * 100}' <<<"$VOL")"
  echo "$ICON_DIR/volume.svg"
  echo "Volume: ${PCT:-?} — click: mixer"
fi
