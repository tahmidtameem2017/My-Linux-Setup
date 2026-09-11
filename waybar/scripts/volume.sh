#!/bin/bash
# Opens the themed HTML volume mixer in a floating browser window.
# Click again (or press Esc / Close) to toggle it shut.
# Niri floats it via the `title="Volume"` rule in niri/rules.kdl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/../volume/volume-server.py"
STATE_DIR="${NIRI_VOLUME_DIR:-${HOME}/.cache/niri-volume}"
PORT_FILE="$STATE_DIR/port"
APP_MARKER="niri-volume"
SERVER_MARKER="volume-server.py"

# Toggle: if the mixer window is already open, close window + server.
if pgrep -f "[n]iri-volume" >/dev/null 2>&1; then
  pkill -f "[n]iri-volume" 2>/dev/null || true
  pkill -f "$SERVER_MARKER" 2>/dev/null || true
  exit 0
fi

# Drop any stale server, then (re)start it.
pkill -f "$SERVER_MARKER" 2>/dev/null || true
mkdir -p "$STATE_DIR"
rm -f "$PORT_FILE"
NIRI_VOLUME_DIR="$STATE_DIR" nohup python3 "$SERVER" >/dev/null 2>&1 < /dev/null &

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
  echo "[ERROR] volume server did not start" >&2
  pkill -f "$SERVER_MARKER" 2>/dev/null || true
  exit 1
fi

URL="http://127.0.0.1:$PORT/"

if command -v brave >/dev/null 2>&1; then
  exec brave \
    --user-data-dir="$STATE_DIR" \
    --app="$URL" \
    --window-size=400,440 \
    --no-first-run \
    --no-default-browser-check >/dev/null 2>&1 < /dev/null &
  exit 0
fi

if command -v firefox >/dev/null 2>&1; then
  exec firefox --new-window "$URL" >/dev/null 2>&1 < /dev/null &
  exit 0
fi

exec xdg-open "$URL" >/dev/null 2>&1 < /dev/null &
