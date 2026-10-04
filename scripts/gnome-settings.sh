#!/bin/bash
# gnome-settings.sh — open GNOME Settings (the system settings app) under niri.
# Replaces the old native quickshell "Settings Center" popup (removed 2026-10-02):
# GNOME already owns network/sound/display/accounts/power/appearance, so this
# session just launches it instead of re-implementing it.
#
# Why the env overrides:
#   XDG_CURRENT_DESKTOP=GNOME  gnome-control-center 50+ refuses to start unless
#                               it believes it is on GNOME. Scoped to this spawn
#                               only — the niri session stays "niri".
#   LD_PRELOAD=gtk-nocsd       strips the GTK header bar. niri draws no title
#                               buttons, so libadwaita's CSD would leave an
#                               unclosable strip on every panel. (Only preloaded
#                               when the local build exists; harmless to skip.)
#
# Close the window with Mod+Q (niri/binds.kdl).
# Optional args are forwarded: gnome-settings.sh network bluetooth
set -euo pipefail

NOCSD_LIB="$HOME/.local/lib/libgtk-nocsd.so.0"

if ! command -v gnome-control-center >/dev/null 2>&1; then
  echo "[ERROR] gnome-control-center not installed" >&2
  exit 1
fi

export XDG_CURRENT_DESKTOP=GNOME
if [ -f "$NOCSD_LIB" ]; then
  export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}$NOCSD_LIB"
fi

exec gnome-control-center "$@"