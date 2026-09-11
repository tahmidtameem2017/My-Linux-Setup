#!/bin/bash
choice=$(printf "  Play/Pause\n  Next\n  Previous" | fuzzel --config /home/me/niri-setup/fuzzel/media.ini --dmenu)
case "$choice" in
    *Play/Pause) playerctl play-pause ;;
    *Next) playerctl next ;;
    *Previous) playerctl previous ;;
esac
