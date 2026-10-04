#!/usr/bin/env bash
# Opens the custom palette editor (help/custom-theme.html) in a floating Brave
# window. Click again to toggle it shut (launcher toggle parity, same as
# scripts/open-help.sh).
#
# The page has to WRITE ~/.local/share/niri-setup/theme-custom.json, and a
# file:// page cannot, so this also runs scripts/custom-theme-server.py on
# loopback and points the browser at it. The server carries a token in the URL
# and demands it back in a header on POST — without that, any page in the
# browser could repaint the desktop by posting to loopback.
#
# Brave gets its own profile dir so the window has a distinct app-id and
# closing it cannot collide with the help guide.

set -uo pipefail

REPO_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
STATE_DIR="$REPO_HOME/.state"
PROFILE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/niri-custom-theme"
PID_FILE="$STATE_DIR/custom-theme-server.pid"
HOST="${NIRI_CUSTOM_THEME_HOST:-127.0.0.7}"
PORT="${NIRI_CUSTOM_THEME_PORT:-4097}"
SERVER="$REPO_HOME/scripts/custom-theme-server.py"
PAGE="$REPO_HOME/help/custom-theme.html"

[[ -f "$PAGE" ]] || { echo "[ERROR] $PAGE not found" >&2; exit 1; }
[[ -f "$SERVER" ]] || { echo "[ERROR] $SERVER not found" >&2; exit 1; }
mkdir -p "$STATE_DIR"

running_pid() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    [[ "$pid" =~ ^[0-9]+$ ]] || { rm -f "$PID_FILE"; return 1; }
    # Same PID-reuse trap as scripts/auto-wallpaper.sh: `kill -0` alone would
    # happily accept an unrelated process that inherited the number.
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || { rm -f "$PID_FILE"; return 1; }
    [[ "$cmdline" == *"custom-theme-server.py"* ]] || { rm -f "$PID_FILE"; return 1; }
    echo "$pid"
}

# Toggle: shut the editor (server and window) if it is already up.
if existing=$(running_pid); then
    pkill -f "user-data-dir=$PROFILE_DIR" 2>/dev/null || true
    kill "$existing" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 0
fi

command -v brave >/dev/null 2>&1 || { echo "[ERROR] brave not found" >&2; exit 1; }

# One token per launch, so a URL captured from a previous session is useless.
token=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
mkdir -p "$PROFILE_DIR"

setsid python3 "$SERVER" --host "$HOST" --port "$PORT" --token "$token" \
    --setup-home "$REPO_HOME" \
    >"$STATE_DIR/custom-theme-server.log" 2>&1 </dev/null &
server_pid=$!
echo "$server_pid" > "$PID_FILE"

# Wait for it to accept connections instead of sleeping a guessed amount: the
# browser will show a connection error if it arrives first, and that reads as a
# broken button rather than a race.
for _ in $(seq 1 50); do
    if ! running_pid >/dev/null; then
        echo "[ERROR] server died on startup; see $STATE_DIR/custom-theme-server.log" >&2
        exit 1
    fi
    if curl -fsS "http://$HOST:$PORT/api/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

url="http://$HOST:$PORT/?t=$token"
setsid brave \
    --user-data-dir="$PROFILE_DIR" \
    --app="$url" \
    --window-size=1180,900 \
    --no-first-run \
    --no-default-browser-check \
    >/dev/null 2>&1 </dev/null &

exit 0