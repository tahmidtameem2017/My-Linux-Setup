#!/bin/bash
# clear-clipboard.sh — wipe the current clipboard + primary selection and all
# clipboard history (cliphist for the waybar "Clipboard" module, copyq for Mod+C).
set -euo pipefail

# 1. Clear the live Wayland clipboard and primary selection so nothing pastes.
wl-copy --clear 2>/dev/null || true
wl-copy -p --clear 2>/dev/null || true

# 2. Wipe cliphist history (the source behind the waybar Clipboard picker).
if command -v cliphist >/dev/null 2>&1; then
  cliphist wipe >/dev/null 2>&1 || true
fi

# 3. Clear copyq history if its daemon is actually running.
if command -v copyq >/dev/null 2>&1 && pgrep -x copyq >/dev/null 2>&1; then
  copyq clear >/dev/null 2>&1 || true
fi

notify-send -a niri -i edit-clear "Clipboard cleared" \
  "Clipboard contents and history have been wiped."
