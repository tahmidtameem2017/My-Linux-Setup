#!/bin/bash

# --- CONFIG ---
WALL_DIR="$HOME/Pictures/Wallpapers"
SETTER="$HOME/niri-setup/scripts/wallpaper.sh"
HISTORY_FILE="/tmp/wall_history.txt"
INDEX_FILE="/tmp/wall_index.txt"

# Ensure files exist
touch "$HISTORY_FILE"
[[ ! -s "$INDEX_FILE" ]] && echo "0" > "$INDEX_FILE"

# Get current history state
mapfile -t history < "$HISTORY_FILE"
idx=$(cat "$INDEX_FILE")

apply_wall() {
    local img="$1"
    if [[ -f "$img" ]]; then
        bash "$SETTER" "$img"
        echo "$idx" > "$INDEX_FILE"
    fi
}

case "$1" in
    --next|next|"")
        # If we are at the end of the history, pick a NEW random one
        if [[ $idx -ge $((${#history[@]} - 1)) ]]; then
            new_wall=$(find "$WALL_DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) | shuf -n 1)
            echo "$new_wall" >> "$HISTORY_FILE"
            idx=$((${#history[@]}))
        else
            # Move forward in existing history
            idx=$((idx + 1))
            new_wall="${history[$idx]}"
        fi
        apply_wall "$new_wall"
        ;;

    --prev|prev)
        if [[ $idx -gt 0 ]]; then
            idx=$((idx - 1))
            apply_wall "${history[$idx]}"
        else
            echo "Reached start of history."
        fi
        ;;
esac