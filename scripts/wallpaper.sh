#!/usr/bin/env bash
# wallpaper.sh <path>
# Sets the given image as wallpaper, updates the backdrop,
# persists the change in niri config, and logs the event.

set -euo pipefail

image="${1:-}"
[[ -n "$image" ]] || { echo "[ERROR] Usage: $0 <path-to-image>" >&2; exit 1; }
[[ -f "$image" ]]   || { echo "[ERROR] Image not found: $image" >&2; exit 1; }

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
WALLPAPER_DIR="$NIKI_HOME/wallpapers"
WALLPAPERS_KDL="$NIKI_HOME/niri/wallpapers.kdl"
STATE_FILE="$NIKI_HOME/.state/current_wallpaper"
mkdir -p "$WALLPAPER_DIR"

ext="${image##*.}"
workspace="$WALLPAPER_DIR/workspace.$ext"
backdrop="$WALLPAPER_DIR/backdrop.$ext"

# Copy to workspace
cp -f "$image" "$workspace"

# Extract canvas color (top-left pixel, fallback #010102)
canvas_color=""
if command -v magick &>/dev/null; then
    canvas_color="$(magick "$workspace" -crop x1+0+0 -resize 1x1 txt:- 2>/dev/null | grep -oE '#[0-9A-Fa-f]{6}' | head -1 || true)"
fi
canvas_color="${canvas_color:-#010102}"

# Persist current wallpaper
mkdir -p "$(dirname "$STATE_FILE")"
echo "$image" > "$STATE_FILE"

# Kill old swaybg
pkill -x swaybg 2>/dev/null || true

# Start new swaybg
swaybg -i "$workspace" -m fill -c "$canvas_color" &
disown

# Generate blurred backdrop
if command -v magick &>/dev/null; then
    magick "$workspace" -scale 10% -blur 0x2.5 -resize 1000% "$backdrop" 2>/dev/null || true
fi

# Persist in niri config
if [[ -f "$WALLPAPERS_KDL" ]]; then
    local_tmp="${WALLPAPERS_KDL}.$$"
    (
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == 'spawn-sh-at-startup "swaybg'* ]]; then
                printf "spawn-sh-at-startup \"swaybg -i %s -m fill -c '%s'\"\n" "$workspace" "$canvas_color"
            elif [[ "$line" == 'spawn-sh-at-startup "swww-daemon'* ]]; then
                printf "spawn-sh-at-startup \"swww-daemon & swww img %s\"\n" "$backdrop"
            else
                printf '%s\n' "$line"
            fi
        done < "$WALLPAPERS_KDL" > "$local_tmp"
        mv "$local_tmp" "$WALLPAPERS_KDL"
    )
fi

echo "[OK] Wallpaper set: $workspace (color: $canvas_color)"
