#!/bin/bash
wallpaper_dir="$HOME/Pictures/Wallpapers"
export GUM_CHOOSE_HEADER_FOREGROUND="#d8dadd"
export GUM_CHOOSE_SELECTED_FOREGROUND="#758A9B"
export GUM_CHOOSE_CURSOR_FOREGROUND="#758A9B"

if [ ! -d "$wallpaper_dir" ]; then
  mkdir -p "$wallpaper_dir"
fi
images=$(fd . --base-directory "$wallpaper_dir" | grep -e ".jpg" -e ".png" | sort)
if [ -z "$images" ]; then
  echo "[ERROR] No image file found"
  echo "[INFO] Place your wallpapers in $wallpaper_dir"
  read -n 1 -s -r -p "[INFO] Press any key to finish..."
  exit 1
fi
image="$wallpaper_dir/$(echo "$images" | gum choose --header 'Choose your wallpaper: ')"
if [ $? -eq 1 ]; then
  exit 1
fi
mode=$(echo -e "stretch\nfill\nfit\ncenter\ntile" | gum choose --header "Choose wallpaper mode: ")
if [ $? -eq 1 ]; then
  exit 1
fi

echo "[INFO] New wallpaper: $image"
echo "[INFO] Copying new wallpaper to /home/me/niri-setup..."
cp -f $image "/home/me/niri-setup/wallpapers/workspace.${image##*.}"
canvas_color=$(magick /home/me/niri-setup/wallpapers/workspace.${image##*.} -crop x1+0+0 -resize 1x1 txt:- | grep -o '#[0-9A-Fa-f]\{6\}')
workspace_cmd="swaybg -i /home/me/niri-setup/wallpapers/workspace.${image##*.} -m $mode -c '$canvas_color'"
sed -i "s|^spawn-sh-at-startup \"swaybg.*|spawn-sh-at-startup \"$workspace_cmd\"|" "/home/me/niri-setup/niri/config.kdl"
pkill swaybg
nohup sh -c "$workspace_cmd" >/dev/null 2>&1 &

echo "[INFO] Creating new overview backdrop..."
magick "/home/me/niri-setup/wallpapers/workspace.${image##*.}" -scale 10% -blur 0x2.5 -resize 1000% "/home/me/niri-setup/wallpapers/backdrop.${image##*.}"
backdrop_cmd="swww-daemon \& swww img /home/me/niri-setup/wallpapers/backdrop.${image##*.}"
swww img "/home/me/niri-setup/wallpapers/backdrop.${image##*.}"
sed -i "s|^spawn-sh-at-startup \"swww.*img.*|spawn-sh-at-startup \"$backdrop_cmd\"|" "/home/me/niri-setup/niri/config.kdl"

echo "[INFO] Done!"
read -n 1 -s -r -p "[INFO] Press any key to finish..."
