#!/bin/bash
# clip-screenshot.sh — region screenshot straight to image+path clipboard.
# Captures with grim/slurp, saves under ~/Pictures/Screenshots/, and offers
# both the image bytes and the saved file path in one clipboard offer.
set -euo pipefail

out_dir="${HOME}/Pictures/Screenshots"
mkdir -p "$out_dir"

geom=$(slurp 2>/dev/null) || exit 0
[ -z "$geom" ] && exit 0

stamp=$(date +"Screenshot From %Y-%m-%d %H-%M-%S.png")
out="${out_dir}/${stamp}"

grim -g "$geom" "$out" 2>/dev/null || exit 0
[ -s "$out" ] || exit 0

cliphist store < "$out" 2>/dev/null || true
setsid -f /home/me/niri-setup/scripts/clipboard-offer.py "$out" "$out" 2>/dev/null
notify-send -a niri -i image-x-generic "Screenshot captured" "$out"
