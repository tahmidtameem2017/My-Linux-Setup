#!/bin/bash
# rollback-to-waybar.sh — instant rollback from quickshell to the waybar gold session.
#   1. pkill quickshell
#   2. restore spawn-at-startup.kdl from latest ~/.config/niri.bak-*/spawn-at-startup.kdl,
#      else /tmp/spawn-waybar-gold.kdl, else repo niri/spawn-waybar.kdl
#   3. niri validate + load-config-file
#   4. restart waybar + dunst, notify-send confirmation
set -euo pipefail

REPO="$(dirname "$(realpath "$0")")/.."
NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
LIVE="$NIRI_DIR/spawn-at-startup.kdl"
REPO_LIVE="$REPO/niri/spawn-at-startup.kdl"
GOLD_TMP="/tmp/spawn-waybar-gold.kdl"
REPO_GOLD="$REPO/niri/spawn-waybar.kdl"

pick_source() {
  local latest
  latest="$(ls -dt "$HOME"/.config/niri.bak-*/spawn-at-startup.kdl 2>/dev/null | head -n 1 || true)"
  if [ -n "${latest:-}" ] && [ -f "$latest" ]; then
    echo "$latest"
  elif [ -f "$GOLD_TMP" ]; then
    echo "$GOLD_TMP"
  elif [ -f "$REPO_GOLD" ]; then
    echo "$REPO_GOLD"
  else
    echo "[ERROR] no rollback source found (checked ~/.config/niri.bak-*/, $GOLD_TMP, $REPO_GOLD)" >&2
    exit 1
  fi
}

SRC="$(pick_source)"
echo "[INFO] rollback source: $SRC"

pkill quickshell 2>/dev/null || true

cp "$SRC" "$REPO_LIVE"
mkdir -p "$NIRI_DIR"
cp "$SRC" "$LIVE"

echo "[INFO] validating..."
niri validate -c "$REPO_LIVE" 2>/dev/null || niri validate
echo "[INFO] reloading niri config..."
niri msg action load-config-file

pkill waybar 2>/dev/null || true
pkill dunst 2>/dev/null || true
waybar -c "$REPO/waybar/config" -s "$REPO/waybar/style.css" &
dunst -conf "$REPO/dunst/dunstrc" &
sleep 1

notify-send -a niri-setup "Rollback complete" "Session restored to waybar (source: $(basename "$(dirname "$SRC")")/$(basename "$SRC"))" || true
echo "[INFO] rollback complete — waybar+dunst restarted"
