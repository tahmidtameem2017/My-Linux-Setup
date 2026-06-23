#!/bin/bash
options="power-saver\nbalanced\nperformance"
choice=$(echo -e "$options" | fuzzel --dmenu --config /home/me/niri-setup/fuzzel/power-profile.ini)
if [ ! -z "$choice" ]; then
  powerprofilesctl set $choice
fi
