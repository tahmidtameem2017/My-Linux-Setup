#!/bin/bash
# ocr-latest.sh — OCR the newest screenshot, else a clipboard image.
set -uo pipefail

OUT_DIR="$HOME/Pictures/Screenshots"
newest=$(find "$OUT_DIR" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.webp' \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -n "$newest" ] && [ "$(( $(date +%s) - $(stat -c %Y "$newest") ))" -le 3600 ]; then
  exec "$(dirname "$0")/ocr.sh" "$newest"
fi

# Fall back to a clipboard image.
if wl-paste --list-types 2>/dev/null | grep -qi '^image/'; then
  tmp=$(mktemp --suffix=.png)
  wl-paste --type image/png > "$tmp" 2>/dev/null || wl-paste > "$tmp"
  "$(dirname "$0")/ocr.sh" "$tmp"
  rm -f "$tmp"
  exit 0
fi

notify-send -a niri -t 3000 "OCR" "No recent screenshot or clipboard image"
exit 1
