#!/bin/bash
# switch-shell.sh — flip the live niri session between waybar and quickshell.
# Usage: switch-shell.sh [waybar|quickshell|status]
#   waybar      copy niri/spawn-waybar.kdl     -> live spawn-at-startup.kdl
#   quickshell  copy niri/spawn-quickshell.kdl -> live spawn-at-startup.kdl
#   status      show which session is live (diff-based)
# Live = repo niri/spawn-at-startup.kdl + ~/.config/niri/spawn-at-startup.kdl,
# then `niri validate` + `niri msg action load-config-file`.
set -euo pipefail

REPO="$(dirname "$(realpath "$0")")/.."
LIVE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/spawn-at-startup.kdl"
WAYBAR_SRC="$REPO/niri/spawn-waybar.kdl"
QSHELL_SRC="$REPO/niri/spawn-quickshell.kdl"
REPO_LIVE="$REPO/niri/spawn-at-startup.kdl"

usage() {
  echo "usage: $(basename "$0") [waybar|quickshell|status]" >&2
  exit 1
}

current_mode() {
  if [ ! -f "$REPO_LIVE" ]; then
    echo "unknown (missing $REPO_LIVE)"
    return 0
  fi
  if cmp -s "$REPO_LIVE" "$WAYBAR_SRC"; then
    echo "waybar"
  elif cmp -s "$REPO_LIVE" "$QSHELL_SRC"; then
    echo "quickshell"
  else
    echo "custom (spawn-at-startup.kdl matches neither variant)"
  fi
}

activate() {
  local mode="$1" src="$2"
  [ -f "$src" ] || { echo "[ERROR] missing source: $src" >&2; exit 1; }
  cp "$src" "$REPO_LIVE"
  mkdir -p "$(dirname "$LIVE")"
  cp "$src" "$LIVE"
  echo "[INFO] live session -> $mode"
  echo "[INFO] validating..."
  niri validate -c "$REPO_LIVE" 2>/dev/null || niri validate
  echo "[INFO] reloading niri config..."
  niri msg action load-config-file
  echo "[INFO] done. current mode: $(current_mode)"
  if [ "$mode" = "quickshell" ]; then
    echo "[HINT] stop waybar/dunst manually if still running: pkill waybar; pkill dunst"
    echo "[HINT] start quickshell if not spawned: quickshell -c sunset &"
  else
    echo "[HINT] stop quickshell if running: pkill quickshell"
    echo "[HINT] restart bar/notifs if needed: waybar -c $REPO/waybar/config -s $REPO/waybar/style.css & dunst -conf $REPO/dunst/dunstrc &"
  fi
}

[ $# -eq 1 ] || usage
case "$1" in
  waybar) activate "waybar" "$WAYBAR_SRC" ;;
  quickshell) activate "quickshell" "$QSHELL_SRC" ;;
  status) echo "mode: $(current_mode)" ;;
  *) usage ;;
esac
