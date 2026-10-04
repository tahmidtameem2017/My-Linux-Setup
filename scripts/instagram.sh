#!/bin/bash
# Opens Instagram in its own Brave process with a MOBILE user agent, so the
# phone UI loads (Instagram's desktop web UI is unusable on a narrow tiling
# window: no nav, no search, no reels).
#
# Why a separate process instead of just `--user-agent` on a normal launch:
# Chromium reads command-line flags ONLY at browser startup. When your main
# Brave is already running (it always is), a second `brave --user-agent=...`
# is forwarded to the live instance as a "new tab" request and the flag is
# silently DROPPED -- verified here: the page still received
# `Mozilla/5.0 (X11; Linux x86_64) ... Chrome/151`. The only way to make a
# startup-only flag take effect is a distinct --user-data-dir, which forces a
# genuinely new browser process. That also means a separate cookie jar, so you
# log into Instagram once here and it is remembered for this window only.
#
# Brave has no "Request mobile site" menu item (checked the binary and every
# locale .pak -- no such string), so this is the supported route.
#
# Toggle: run it again to close the window (matches open-help.sh).
set -euo pipefail

STATE_DIR="${HOME}/.cache/niri-instagram"
URL="https://www.instagram.com/"

# iPhone Safari UA. Instagram keys its mobile layout off this; the Desktop
# token would hand back the desktop UI regardless of window size.
MOBILE_UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

# Toggle: if the Instagram window is already open, close just that process
# (matched by its dedicated profile dir, so nothing else can collide).
if pgrep -f "user-data-dir=$STATE_DIR" >/dev/null 2>&1; then
  pkill -f "user-data-dir=$STATE_DIR" 2>/dev/null || true
  exit 0
fi

if ! command -v brave >/dev/null 2>&1; then
  echo "[ERROR] brave not found in PATH" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

# NOTE: deliberately NOT re-reading brave-flags.conf here. The /usr/bin/brave
# wrapper already injects every non-comment line of it ahead of our arguments,
# so passing them again would duplicate each flag (observed: the full GPU/RAM
# block twice in the real cmdline). Just call `brave` and let the wrapper do it.
exec brave \
  --user-data-dir="$STATE_DIR" \
  --user-agent="$MOBILE_UA" \
  --app="$URL" \
  --window-size=480,900 \
  --no-first-run \
  --no-default-browser-check >/dev/null 2>&1 < /dev/null &