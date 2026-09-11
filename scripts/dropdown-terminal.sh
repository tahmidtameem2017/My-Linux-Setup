#!/bin/bash
# Dropdown scratchpad terminal — zero dependencies, niri IPC only.
# Toggle with Mod+Grave: spawns on first run, then parks the terminal on
# the persistent "scratch" workspace (declared in niri/config.kdl) to hide
# it, and moves it back to the focused workspace to show it.
set -euo pipefail

TITLE="Dropdown"
SCRATCH="scratch"
TERM_CMD="alacritty --title $TITLE --config-file /home/me/niri-setup/alacritty/float.toml"

windows=$(niri msg --json windows)
id=$(echo "$windows" | jq -r --arg t "$TITLE" '[.[] | select(.app_id=="Alacritty" and .title==$t)][0].id // empty')

if [ -z "$id" ]; then
    # Not running: spawn (the Dropdown window rule floats it top-anchored).
    $TERM_CMD >/dev/null 2>&1 < /dev/null &
    disown
    exit 0
fi

focused_ref=$(niri msg --json workspaces | jq -r '[.[] | select(.is_focused)][0] | if .name != null and .name != "" then .name else (.idx | tostring) end')
ws=$(echo "$windows" | jq -r --argjson i "$id" '[.[] | select(.id==$i)][0].workspace_id')
ws_name=$(niri msg --json workspaces | jq -r --argjson i "$ws" '[.[] | select(.id==$i)][0].name // empty')

if [ "$ws_name" = "$SCRATCH" ]; then
    niri msg action move-window-to-workspace --window-id "$id" "$focused_ref"
    niri msg action focus-window --id "$id"
else
    niri msg action move-window-to-workspace --window-id "$id" "$SCRATCH"
fi
