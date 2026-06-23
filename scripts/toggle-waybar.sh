#!/bin/bash
if [ -z $(pidof waybar) ]; then
  waybar -c /home/me/niri-setup/waybar/config -s /home/me/niri-setup/waybar/style.css &
else
  pkill waybar
fi
