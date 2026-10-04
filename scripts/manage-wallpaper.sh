#!/usr/bin/env bash
# manage-wallpaper.sh — Delete and rename wallpapers in ~/Pictures/Wallpapers.
#
# Usage:
#   manage-wallpaper.sh delete [path]        Move to trash (gio; recoverable).
#                                            No path => current wallpaper
#                                            (from .state/current_wallpaper).
#   manage-wallpaper.sh rename <path> <new-name>
#                                            Rename inside the wallpaper dir.
#                                            <new-name> is a bare file name
#                                            (no slashes); the old extension
#                                            is kept when none is given.
#
# Notes:
#   - Targets must resolve inside WALL_DIR (refuses ../ escapes).
#   - Never permanently deletes: gio trash, falling back to
#     ~/.local/share/niri-setup/wallpaper-trash/ when gio is missing.
#   - Deleting the current wallpaper auto-sets a successor (first sorted
#     remaining file) via wallpaper.sh; renaming it updates the state file.
#   - Stale cached thumbnails (~/.cache/niri-wallpaper/thumbs/) are removed.
#
# Environment:
#   WALL_DIR         Wallpaper directory (default: $HOME/Pictures/Wallpapers)
#   NIRI_SETUP_HOME  Path to niri-setup repo (default: $HOME/niri-setup)

set -euo pipefail

WALL_DIR="${WALL_DIR:-$HOME/Pictures/Wallpapers}"
NIRI_SETUP_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
WALLPAPER_SH="$NIRI_SETUP_HOME/scripts/wallpaper.sh"
STATE_FILE="$NIRI_SETUP_HOME/.state/current_wallpaper"
THUMB_DIR="${NIRI_WALLPAPER_DIR:-$HOME/.cache/niri-wallpaper}/thumbs"
TRASH_FALLBACK="$HOME/.local/share/niri-setup/wallpaper-trash"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit "${1:-0}"
}

# Print the canonical target path, or fail. Defaults to current wallpaper.
resolve_target() {
    local given="${1:-}"
    local target="$given"
    if [[ -z "$target" ]]; then
        [[ -f "$STATE_FILE" ]] || { echo "[ERROR] No path given and no current wallpaper recorded." >&2; return 1; }
        target=$(cat "$STATE_FILE")
    fi
    [[ -e "$target" ]] || { echo "[ERROR] File not found: $target" >&2; return 1; }
    target=$(realpath -m "$target")
    local wall_dir
    wall_dir=$(realpath -m "$WALL_DIR")
    [[ "$target" == "$wall_dir/"* ]] || { echo "[ERROR] Refusing: $target is outside $wall_dir" >&2; return 1; }
    case "${target##*.}" in
        jpg|jpeg|png|webp|avif|JPG|JPEG|PNG|WEBP|AVIF) ;;
        *) echo "[ERROR] Not a wallpaper image: $target" >&2; return 1 ;;
    esac
    printf '%s\n' "$target"
}

is_current() {
    [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$1" ]]
}

# Remove the cached thumbnail for a wallpaper basename (disk name is
# url-encoded basename + ".jpg"; python3 computes the encoding).
drop_thumb() {
    local name="$1" encoded=""
    if command -v python3 &>/dev/null; then
        encoded=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$name" 2>/dev/null || true)
    fi
    [[ -n "$encoded" ]] && rm -f "$THUMB_DIR/$encoded.jpg"
}

first_remaining() {
    find "$WALL_DIR" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o \
        -iname "*.jpeg" -o \
        -iname "*.png" -o \
        -iname "*.webp" -o \
        -iname "*.avif" \
    \) | sort | head -n 1
}

cmd_delete() {
    local target
    target=$(resolve_target "${1:-}") || exit 1
    local name
    name=$(basename "$target")
    local was_current=0
    is_current "$target" && was_current=1

    # gio trash can fail (tmpfs mounts, permissions) — fall back to a
    # backup dir rather than erroring out. Never permanently deletes.
    if command -v gio &>/dev/null && gio trash -- "$target" 2>/dev/null; then
        :
    else
        mkdir -p "$TRASH_FALLBACK"
        mv -n -- "$target" "$TRASH_FALLBACK/$name" || { echo "[ERROR] Could not move $target to $TRASH_FALLBACK" >&2; exit 1; }
        echo "[WARN] System trash unavailable; moved to $TRASH_FALLBACK/$name"
    fi
    drop_thumb "$name"

    if [[ $was_current -eq 1 ]]; then
        local next
        next=$(first_remaining)
        if [[ -n "$next" ]]; then
            bash "$WALLPAPER_SH" "$next"
        else
            rm -f "$STATE_FILE"
            echo "[WARN] Deleted the last wallpaper; nothing to fall back to."
        fi
    fi
    echo "[OK] Deleted (trashed): $name"
}

cmd_rename() {
    [[ $# -ge 2 ]] || { echo "[ERROR] Usage: $0 rename <path> <new-name>" >&2; exit 1; }
    local target
    target=$(resolve_target "$1") || exit 1
    local raw_new="$2"
    # Bare file name only — strip any directory components.
    local new
    new=$(basename "$raw_new")
    [[ -n "$new" && "$new" != "." ]] || { echo "[ERROR] Invalid new name." >&2; exit 1; }
    # Keep the old extension when none is given.
    if [[ "$new" != *.* ]]; then
        new="$new.${target##*.}"
    fi
    case "${new##*.}" in
        jpg|jpeg|png|webp|avif|JPG|JPEG|PNG|WEBP|AVIF) ;;
        *) echo "[ERROR] New name needs an image extension (jpg/jpeg/png/webp/avif)." >&2; exit 1 ;;
    esac
    local dest
    dest="$(dirname "$target")/$new"
    [[ -e "$dest" ]] && { echo "[ERROR] Already exists: $dest" >&2; exit 1; }

    mv -n -- "$target" "$dest" || { echo "[ERROR] Could not rename $target" >&2; exit 1; }
    drop_thumb "$(basename "$target")"

    if is_current "$target"; then
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "$dest" > "$STATE_FILE"
    fi
    echo "[OK] Renamed: $(basename "$target") -> $new"
    echo "$dest"
}

case "${1:-}" in
    delete) shift; cmd_delete "${1:-}" ;;
    rename) shift; cmd_rename "$@" ;;
    -h|--help|help|"") usage 0 ;;
    *) echo "[ERROR] Unknown command: $1" >&2; usage 1 ;;
esac
