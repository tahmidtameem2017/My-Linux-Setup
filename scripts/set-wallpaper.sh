#!/bin/bash
# Wallpaper changer with previous/next/random options

wallpaper_dir="$HOME/Pictures/Wallpapers"
history_file="$HOME/.config/niri/wallpaper_history"

# Get all wallpapers sorted
get_wallpapers() {
  find "$wallpaper_dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.avif" \) | sort
}

# Largest 6-digit prime: 999983
readonly HASH_PRIME=999983

# Get current wallpaper from running swaybg
get_current() {
  pgrep -a swaybg | grep -oP '(?<=-i )[^ ]+' | head -1
}

# Save to history
save_history() {
  echo "$1" > "$history_file"
}

# Get previous from history
get_previous() {
  if [ -f "$history_file" ]; then
    cat "$history_file"
  fi
}

set_wallpaper() {
  local image="$1"
  echo "Setting wallpaper: $image"
  pkill swaybg
  swaybg -i "$image" -m fill &
  save_history "$image"
  echo "[INFO] Wallpaper changed successfully"
}

case "${1:-random}" in
  random)
    mapfile -t wallpapers < <(get_wallpapers)
    count=${#wallpapers[@]}
    if [ "$count" -eq 0 ]; then
      echo "[ERROR] No wallpapers found"
      exit 1
    fi
    hash=$(( $(date +%s%N) * HASH_PRIME ))
    idx=$(( hash % count ))
    image="${wallpapers[$idx]}"
    set_wallpaper "$image"
    ;;
  next)
    current=$(get_current)
    mapfile -t wallpapers < <(get_wallpapers)
    count=${#wallpapers[@]}
    for i in "${!wallpapers[@]}"; do
      if [ "${wallpapers[$i]}" == "$current" ]; then
        next_idx=$(( (i + 1) % count ))
        set_wallpaper "${wallpapers[$next_idx]}"
        exit 0
      fi
    done
    # If current not found, pick first
    set_wallpaper "${wallpapers[0]}"
    ;;
  prev|previous)
    prev=$(get_previous)
    if [ -n "$prev" ] && [ -f "$prev" ]; then
      set_wallpaper "$prev"
    else
      echo "[ERROR] No previous wallpaper found"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [random|next|prev]"
    exit 1
    ;;
esac
