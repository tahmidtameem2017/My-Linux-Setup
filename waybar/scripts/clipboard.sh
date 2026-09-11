#!/bin/bash
# shellcheck disable=SC2015
# Clipboard history picker: image entries paste back as image + copyable
# file path (via clipboard-pick.py); everything else restores verbatim.
cliphist list | fuzzel --config /home/me/niri-setup/fuzzel/clipboard.ini --dmenu | /home/me/niri-setup/waybar/scripts/clipboard-pick.py
