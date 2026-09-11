#!/bin/bash
choice=$(printf "󰁔  Next\n󰁈  Previous\n󰁒  Random\n󰸉  Pick...\n󰋉  Download\n󰑓  Auto: Start\n󰓛  Auto: Stop\n󰄲  Auto: Status" | fuzzel --config /home/me/niri-setup/fuzzel/wallpaper.ini --dmenu)
case "$choice" in
    *Next) /home/me/niri-setup/scripts/change-wallpaper-simple.sh next ;;
    *Previous) /home/me/niri-setup/scripts/change-wallpaper-simple.sh prev ;;
    *Random) /home/me/niri-setup/scripts/change-wallpaper-simple.sh random ;;
    *Pick*) /home/me/niri-setup/waybar/scripts/wallpaper-gallery.sh ;;
    *Download) alacritty --config-file /home/me/niri-setup/alacritty/float.toml -e /home/me/niri-setup/scripts/wallhaven-fetch.sh ;;
    *Start) /home/me/niri-setup/scripts/auto-wallpaper.sh ;;
    *Stop) /home/me/niri-setup/scripts/auto-wallpaper.sh --stop ;;
    *Status) /home/me/niri-setup/scripts/auto-wallpaper.sh --status ;;
esac
