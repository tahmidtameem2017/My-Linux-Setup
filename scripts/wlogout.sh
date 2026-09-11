#!/bin/bash
# Icons in style.css use absolute paths, but stay robust to CWD anyway.
cd "/home/me/niri-setup/wlogout" || exit 1
wlogout -C /home/me/niri-setup/wlogout/style.css -l /home/me/niri-setup/wlogout/layout -b 5 -T 400 -B 400
