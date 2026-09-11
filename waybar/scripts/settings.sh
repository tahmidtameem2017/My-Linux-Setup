#!/bin/bash
# Opens the themed HTML quick-settings panel in a floating browser window.
# Click again (or press Esc / Close) to toggle it shut.
# Niri floats it via its app-id rule in niri/rules.kdl.
# NOTE: uses http://127.0.0.3 (not .1/.2/.4/localhost) so Brave derives a
# distinct app-id from the volume/power/clock/wallpaper popups.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/../settings/settings-server.py"
STATE_DIR="${NIRI_SETTINGS_DIR:-${HOME}/.cache/niri-settings}"
PORT_FILE="$STATE_DIR/port"
APP_MARKER="niri-settings"
SERVER_MARKER="settings-server.py"

# Toggle: if the panel window is already open, close window + server.
if pgrep -f "[n]iri-settings" >/dev/null 2>&1; then
  pkill -f "[n]iri-settings" 2>/dev/null || true
  pkill -f "$SERVER_MARKER" 2>/dev/null || true
  exit 0
fi

# Drop any stale server, then (re)start it.
pkill -f "$SERVER_MARKER" 2>/dev/null || true
mkdir -p "$STATE_DIR"
rm -f "$PORT_FILE"
NIRI_SETTINGS_DIR="$STATE_DIR" nohup python3 "$SERVER" >/dev/null 2>&1 < /dev/null &

# Wait for the server to publish its port (ephemeral, avoids collisions).
PORT=""
for _ in $(seq 1 30); do
  if [ -s "$PORT_FILE" ]; then
    PORT="$(cat "$PORT_FILE")"
    break
  fi
  sleep 0.1
done
if [ -z "$PORT" ]; then
  echo "[ERROR] settings server did not start" >&2
  pkill -f "$SERVER_MARKER" 2>/dev/null || true
  exit 1
fi

URL="http://127.0.0.3:$PORT/"

if command -v brave >/dev/null 2>&1; then
  exec brave \
    --user-data-dir="$STATE_DIR" \
    --app="$URL" \
    --window-size=400,600 \
    --no-first-run \
    --no-default-browser-check >/dev/null 2>&1 < /dev/null &
  exit 0
fi

if command -v firefox >/dev/null 2>&1; then
  exec firefox --new-window "$URL" >/dev/null 2>&1 < /dev/null &
  exit 0
fi

exec xdg-open "$URL" >/dev/null 2>&1 < /dev/null &
