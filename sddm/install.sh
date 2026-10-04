#!/usr/bin/env bash
# sddm/install.sh — install Sunset Orange AMOLED SDDM theme
# Usage: ./sddm/install.sh [--no-activate]   (requires sudo)
#   Copies sddm/sunset → /usr/share/sddm/themes/sunset
#   Writes /etc/sddm.conf.d/sunset.conf  ([Theme] Current=sunset)
# Safe: backs up existing theme to /tmp/bak, never restarts sddm/locks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/sddm/sunset"
DST="/usr/share/sddm/themes/sunset"
CONF_D="/etc/sddm.conf.d"
CONF_FILE="$CONF_D/sunset.conf"
BAK="/tmp/bak"

NO_ACTIVATE=false
if [[ "${1:-}" == "--no-activate" ]]; then
  NO_ACTIVATE=true
fi

# sudo guard
if ! sudo -n true 2>/dev/null; then
  echo "[INFO] sudo password required — run manually:"
  echo "  sudo mkdir -p $DST && sudo cp -r $SRC/* $DST/"
  echo "  sudo mkdir -p $CONF_D && printf '[Theme]\nCurrent=sunset\n' | sudo tee $CONF_FILE >/dev/null"
  echo ""
  echo "Or run: sudo $0"
  echo "Dry-run (no sudo): copying to /tmp/test-sunset for inspection"
  mkdir -p /tmp/test-sunset
  cp -r "$SRC"/* /tmp/test-sunset/
  ls -lh /tmp/test-sunset/
  exit 1
fi

echo "[INFO] installing sunset theme → $DST"
sudo mkdir -p "$BAK"

if [[ -d "$DST" ]]; then
  echo "[INFO] backing up existing $DST → $BAK/sddm-sunset-$(date +%Y%m%d-%H%M%S)"
  sudo cp -a "$DST" "$BAK/sddm-sunset-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
fi

sudo mkdir -p "$DST"
sudo cp -r "$SRC"/* "$DST/"
sudo chmod -R 644 "$DST"
sudo find "$DST" -type d -exec chmod 755 {} \;
# Main.qml must be readable
sudo chmod 644 "$DST/Main.qml" "$DST/theme.conf" "$DST/metadata.desktop" 2>/dev/null || true

echo "[INFO] validating QML..."
if command -v qmlformat >/dev/null 2>&1; then
  qmlformat "$SRC/Main.qml" >/dev/null && echo "[OK] qmlformat $SRC/Main.qml" || echo "[WARN] qmlformat failed"
fi
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$SRC/Main.qml" && echo "[OK] qmllint $SRC/Main.qml" || echo "[WARN] qmllint reported issues (check sddm log)"
fi

if [[ "$NO_ACTIVATE" == false ]]; then
  echo "[INFO] activating theme → $CONF_FILE"
  if [[ -f "$CONF_FILE" ]]; then
    sudo cp -a "$CONF_FILE" "$BAK/sunset.conf.$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null || true
  fi
  sudo mkdir -p "$CONF_D"
  printf "[Theme]\nCurrent=sunset\n" | sudo tee "$CONF_FILE" >/dev/null
  echo "[INFO] wrote $CONF_FILE"
  cat "$CONF_FILE"
else
  echo "[INFO] --no-activate: skipping $CONF_FILE write"
fi

echo ""
echo "[INFO] done. Do NOT restart sddm now — it will apply on next boot/re-login."
echo "  Verify: cat $CONF_FILE && ls -l $DST"
echo "  Test without reboot: sddm-greeter --test-mode --theme $DST"
echo "  Revert: sudo rm $CONF_FILE; # restores default (alphabetical: elarun)"
