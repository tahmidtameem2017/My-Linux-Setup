#!/bin/bash
# Opens the sunset Setup Guide (help/index.html) in a floating browser
# window. Click again to toggle it shut (launcher toggle parity).
# Brave gets a dedicated profile (~/.cache/niri-help) so the window
# carries its own app-id, like the legacy waybar HTML popups.
set -euo pipefail

REPO_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
PAGE="$REPO_HOME/help/index.html"
STATE_DIR="${HOME}/.cache/niri-help"

if [[ ! -f "$PAGE" ]]; then
  echo "[ERROR] $PAGE not found" >&2
  exit 1
fi

# The guide loads help/theme.css for the live palette. Regenerate it if it is
# missing (fresh clone, or a theme switch that happened before this script
# existed) so the page never renders half-themed. Cheap and idempotent.
THEME_CSS="$REPO_HOME/help/theme.css"
if [[ ! -f "$THEME_CSS" ]]; then
  python3 "$REPO_HOME/scripts/sync-external-theme.py" --setup-home "$REPO_HOME" >/dev/null 2>&1 || true
fi

# Toggle: if the guide window is already open, close just the window
# (matched by its dedicated profile dir, so nothing else can collide).
if pgrep -f "user-data-dir=$STATE_DIR" >/dev/null 2>&1; then
  pkill -f "user-data-dir=$STATE_DIR" 2>/dev/null || true
  exit 0
fi

URL="file://$PAGE"

if command -v brave >/dev/null 2>&1; then
  mkdir -p "$STATE_DIR"
  exec brave \
    --user-data-dir="$STATE_DIR" \
    --app="$URL" \
    --window-size=1100,860 \
    --no-first-run \
    --no-default-browser-check >/dev/null 2>&1 < /dev/null &
  exit 0
fi

if command -v firefox >/dev/null 2>&1; then
  exec firefox --new-window "$URL" >/dev/null 2>&1 < /dev/null &
  exit 0
fi

exec xdg-open "$URL" >/dev/null 2>&1 < /dev/null &
