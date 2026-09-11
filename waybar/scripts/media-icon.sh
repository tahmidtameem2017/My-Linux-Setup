#!/usr/bin/env bash
# Echo the media SVG path (+ tooltip) for waybar's image#media module.
ICON_DIR="$(dirname "$0")/../icons"

if ! command -v playerctl >/dev/null 2>&1; then
  echo ""
  exit 0
fi

STATUS="$(playerctl status 2>/dev/null)"
case "$STATUS" in
  Playing)
    META="$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null)"
    echo "$ICON_DIR/play.svg"
    echo "${META:-Playing} — click: menu"
    ;;
  Paused)
    META="$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null)"
    echo "$ICON_DIR/pause.svg"
    echo "${META:-Paused} — click: menu"
    ;;
  *)
    echo ""
    echo "No media"
    ;;
esac
