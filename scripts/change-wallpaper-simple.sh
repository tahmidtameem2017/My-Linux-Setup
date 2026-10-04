#!/usr/bin/env bash
# change-wallpaper-simple.sh [next|prev|random|<path>]
#
# Picks a wallpaper from the library and hands it to scripts/wallpaper.sh.
#
# This used to apply the change itself: `cp` into wallpapers/, a *second* magick
# decode just to sample the canvas colour, then `pkill swaybg; swaybg &`. That
# was three problems wearing a trenchcoat:
#
#   * it never ran scripts/wallust-theme.sh, so "Auto: follow wallpaper" did
#     nothing when you switched wallpaper from the menu — the palette you see
#     was still the one extracted from the *previous* wallpaper;
#   * it skipped the downscale, so a 4K wallpaper was copied in full, and the
#     extra decode made a change cost roughly twice what wallpaper.sh costs;
#   * it killed and respawned swaybg behind wallpaper.sh's back, so the
#     fingerprint/state files wallpaper.sh owns stopped describing reality and
#     the next legitimate change could not tell what was already applied.
#
# So this file now only does the one thing it is actually good at — walking the
# sorted library to find next/previous/random — and delegates the applying.
# wallpaper.sh owns: downscale, one magick pass that writes the workspace image
# AND samples the canvas colour, the fingerprint no-op check, swaybg lifecycle,
# the niri KDL rewrite, and the wallust re-theme.

set -uo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
WALLPAPER_DIR="${WALL_DIR:-$HOME/Pictures/Wallpapers}"
WALLPAPER_SH="$NIKI_HOME/scripts/wallpaper.sh"
STATE_FILE="$NIKI_HOME/.state/current_wallpaper"

verb="${1:-next}"

# An explicit path is a legitimate call: pass it straight through.
if [[ "$verb" == /* || "$verb" == *.jpg || "$verb" == *.jpeg || "$verb" == *.png \
   || "$verb" == *.webp || "$verb" == *.avif ]]; then
    exec "$WALLPAPER_SH" "$verb"
fi

case "$verb" in
    next|prev|previous|random) ;;
    *) verb="next" ;;
esac

[[ -d "$WALLPAPER_DIR" ]] || {
    echo "[ERROR] No wallpaper directory: $WALLPAPER_DIR" >&2
    exit 1
}
[[ -x "$WALLPAPER_SH" ]] || {
    echo "[ERROR] Missing $WALLPAPER_SH" >&2
    exit 1
}

mapfile -t wallpapers < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
    -iname "*.webp" -o -iname "*.avif" \) | sort)
count=${#wallpapers[@]}
if [[ $count -eq 0 ]]; then
    echo "[ERROR] No wallpapers in $WALLPAPER_DIR" >&2
    exit 1
fi

current_index=-1
if [[ -f "$STATE_FILE" ]]; then
    current=$(cat "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$current" ]]; then
        for i in "${!wallpapers[@]}"; do
            if [[ "${wallpapers[$i]}" = "$current" ]]; then
                current_index=$i
                break
            fi
        done
    fi
fi

case "$verb" in
    next)   new_index=$(( (current_index + 1) % count )) ;;
    prev|previous) new_index=$(( (current_index - 1 + count) % count )) ;;
    random) new_index=$(( RANDOM % count )) ;;
esac

# ShellCheck: the index is from RANDOM or a modulo over a non-empty array.
exec "$WALLPAPER_SH" "${wallpapers[$new_index]}"