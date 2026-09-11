#!/bin/bash
# Opens the themed clock popup (calendar + pomodoro + timer) in a floating
# browser window. Click again (or press Esc) to toggle it shut.
# Niri floats it via its app-id rule in niri/rules.kdl.
# NOTE: timing lives in timer-server.py, which intentionally KEEPS RUNNING
# after the window closes so pomodoros chain and beep in the background.
# Uses http://127.0.0.4 for a distinct Brave app-id.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/../clock/timer-server.py"
STATE_DIR="${NIRI_CLOCK_DIR:-${HOME}/.cache/niri-clock}"
PORT_FILE="$STATE_DIR/port"
APP_MARKER="niri-clock"
SERVER_MARKER="timer-server.py"

# Toggle: if the popup window is already open, close just the window.
# The server keeps running so active timers continue in the background.
if pgrep -f "[n]iri-clock" >/dev/null 2>&1; then
  pkill -f "[n]iri-clock" 2>/dev/null || true
  exit 0
fi

# Start the timer server only if it isn't already running.
if ! pgrep -f "$SERVER_MARKER" >/dev/null 2>&1; then
  mkdir -p "$STATE_DIR"
  rm -f "$PORT_FILE"
  NIRI_CLOCK_DIR="$STATE_DIR" nohup python3 "$SERVER" >/dev/null 2>&1 < /dev/null &
fi

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
  echo "[ERROR] timer server did not start" >&2
  exit 1
fi

URL="http://127.0.0.4:$PORT/"

if command -v brave >/dev/null 2>&1; then
  mkdir -p "$STATE_DIR"
  exec brave \
    --user-data-dir="$STATE_DIR" \
    --app="$URL" \
    --window-size=400,490 \
    --no-first-run \
    --no-default-browser-check >/dev/null 2>&1 < /dev/null &
  exit 0
fi

if command -v firefox >/dev/null 2>&1; then
  exec firefox --new-window "$URL" >/dev/null 2>&1 < /dev/null &
  exit 0
fi

exec xdg-open "$URL" >/dev/null 2>&1 < /dev/null &
