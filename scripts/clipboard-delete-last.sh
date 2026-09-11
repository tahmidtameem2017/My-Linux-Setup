#!/bin/bash
# clipboard-delete-last.sh — delete the most recently copied clipboard item
# (the latest entry in cliphist history) and clear the live clipboard so it
# can no longer be pasted.
set -euo pipefail

# The `wl-paste --watch cliphist store` daemon holds the BoltDB write lock, so a
# standalone `cliphist delete` (and even `cliphist list`) can transiently fail
# under concurrent clipboard activity. Pause the watcher first, do our work
# uncontended, then restart it (always, via trap).
watch_pid=$(pgrep -f "wl-paste --watch cliphist store" | head -n1 || true)

cleanup() {
  if [ -n "${watch_pid:-}" ] && ! kill -0 "$watch_pid" 2>/dev/null; then
    nohup wl-paste --watch cliphist store >/dev/null 2>&1 &
  fi
}
trap cleanup EXIT

[ -n "${watch_pid:-}" ] && kill "$watch_pid" 2>/dev/null
sleep 0.2

# cliphist lists newest-first; grab the id of the top entry. Guard the pipeline
# so a transient read error can never abort the script (set -e/pipefail).
id=""
for _ in 1 2 3; do
  id=$(cliphist list 2>/dev/null | head -n1 | cut -f1 || true)
  [ -n "$id" ] && break
  sleep 0.1
done

if [ -z "$id" ]; then
  notify-send -a niri -i edit-delete "Clipboard empty" "No clipboard history to delete."
  exit 0
fi

# cliphist delete reads the entry id(s) from stdin.
echo "$id" | cliphist delete 2>/dev/null || true

# Clear the live Wayland clipboard + primary selection so the deleted item
# can no longer be pasted.
wl-copy --clear 2>/dev/null || true
wl-copy -p --clear 2>/dev/null || true

notify-send -a niri -i edit-delete "Clipboard item deleted" \
  "Removed the latest copied item from history."
