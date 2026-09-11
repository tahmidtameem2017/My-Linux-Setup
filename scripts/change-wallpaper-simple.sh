#!/bin/bash
# Simple wallpaper changer for waybar

wallpaper_dir="$HOME/Pictures/Wallpapers"
workspace_dir="/home/me/niri-setup/wallpapers"
state_file="/home/me/niri-setup/.state/current_wallpaper"

# Get list of wallpapers
if [ ! -d "$wallpaper_dir" ]; then
    exit 1
fi

mapfile -t wallpapers < <(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.avif" \) | sort)
count=${#wallpapers[@]}

if [ $count -eq 0 ]; then
    exit 1
fi

# Find current wallpaper index from state file
current_index=-1
if [ -f "$state_file" ]; then
    current=$(cat "$state_file")
    if [ -n "$current" ]; then
        for i in "${!wallpapers[@]}"; do
            if [ "${wallpapers[$i]}" = "$current" ]; then
                current_index=$i
                break
            fi
        done
    fi
fi

case "$1" in
    next)
        new_index=$(( (current_index + 1) % count ))
        ;;
    prev)
        new_index=$(( (current_index - 1 + count) % count ))
        ;;
    random)
        new_index=$(( RANDOM % count ))
        ;;
    *)
        new_index=$(( (current_index + 1) % count ))
        ;;
esac

new_wallpaper="${wallpapers[$new_index]}"

if [ -f "$new_wallpaper" ]; then
    ext="${new_wallpaper##*.}"
    target="$workspace_dir/workspace.$ext"
    
    # Persist current wallpaper before changing
    mkdir -p "$(dirname "$state_file")"
    echo "$new_wallpaper" > "$state_file"
    
    # Copy to workspace location
    cp "$new_wallpaper" "$target"
    
    # Get canvas color from wallpaper
    canvas_color=$(magick "$target" -crop x1+0+0 -resize 1x1 txt:- 2>/dev/null | grep -oE '#[0-9A-Fa-f]{6}' | head -1)
    canvas_color="${canvas_color:-#0b0b0c}"
    
    # Kill existing swaybg and start new one in background
    pkill swaybg
    sleep 0.2
    swaybg -i "$target" -m fill -c "$canvas_color" &
    disown
fi
