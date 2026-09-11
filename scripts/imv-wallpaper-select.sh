#!/bin/bash
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
WALLPAPER_SH="/home/me/niri-setup/scripts/wallpaper.sh"

TMP_CONF=$(mktemp /tmp/imv-wallpaper-XXXXXX)
cat > "$TMP_CONF" << CONF
[binds]
Return = exec $WALLPAPER_SH "\$imv_current_file"; imv-msg \$imv_pid quit
CONF

imv_config="$TMP_CONF" imv -f -s crop "$WALLPAPER_DIR"
rm -f "$TMP_CONF"
