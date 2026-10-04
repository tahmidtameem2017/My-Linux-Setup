#!/bin/bash
# screenshot.sh [region|window|screen] — capture, then pop the action bar.
# region: flameshot gui (default). window/screen: niri built-ins.
set -uo pipefail

mode="${1:-region}"
OUT_DIR="$HOME/Pictures/Screenshots"
start=$(date +%s)

case "$mode" in
  region) QT_QPA_PLATFORM=wayland flameshot gui || true ;;
  window) niri msg action screenshot-window || true ;;
  screen) niri msg action screenshot-screen || true ;;
  *) echo "usage: screenshot.sh [region|window|screen]" >&2; exit 2 ;;
esac

# Pick the newest file in the save dir that this run could have produced
# (modified after start); bail out on cancel.
newest=""
for _ in $(seq 1 20); do
  newest=$(find "$OUT_DIR" -maxdepth 1 -type f -mmin -1 -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [ -n "$newest" ] && [ "$(stat -c %Y "$newest")" -ge "$start" ]; then
    break
  fi
  sleep 0.5
done
[ -n "$newest" ] || exit 0
[ "$(stat -c %Y "$newest")" -ge "$start" ] || exit 0

wl-copy < "$newest" 2>/dev/null || true
qs -c sunset ipc call screenshots open "$newest"
