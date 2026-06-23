#!/bin/bash

# Configuration - UPDATED PATH
WALL_DIR="/home/me/Pictures/Wallpapers"
INTERVAL="15m" 

while true; do
    # Pick a random image from your custom Pictures folder
    RANDOM_WALL=$(find "$WALL_DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) | shuf -n 1)

    # Apply it using the niri-setup transition script
    if [ -f "$RANDOM_WALL" ]; then
        bash "$HOME/niri-setup/scripts/wallpaper.sh" "$RANDOM_WALL"
    fi

    sleep $INTERVAL
done