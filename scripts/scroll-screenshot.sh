#!/bin/bash
# scroll-screenshot.sh — scrolling screenshot: auto-scroll a region and stitch.
#
# First run starts a capture: pick a region with slurp, then the script
# wheel-scrolls with ydotool and stitches frames by overlap matching
# (ImageMagick subimage search). Run it AGAIN while capturing to stop early;
# it also stops at the bottom (no movement twice) or after MAX_FRAMES.
# Result lands in ~/Pictures/Screenshots and on the clipboard.
set -euo pipefail

RUN="${XDG_RUNTIME_DIR:-/tmp}/scrollshot"
OUT_DIR="$HOME/Pictures/Screenshots"
WHEEL_NOTCHES=6   # wheel clicks per step (bigger = faster, but needs overlap)
SETTLE=0.7        # seconds to wait after each scroll for the page to settle
MAX_FRAMES=60
START_DELAY=3

mkdir -p "$OUT_DIR"

if [ -f "$RUN/running" ]; then
  touch "$RUN/stop"
  notify-send -a niri -t 2000 "Scrolling screenshot" "Stopping — stitching what we have…"
  exit 0
fi

for c in ydotool slurp grim magick wl-copy; do
  command -v "$c" >/dev/null || {
    notify-send -u critical -a niri "Scrolling screenshot" "missing dependency: $c"
    exit 1
  }
done

geom=$(slurp 2>/dev/null) || exit 0
[ -n "$geom" ] || exit 0
# geom looks like "436,234 1826x916"
gx=${geom%%,*}
rest=${geom#*,}
gy=${rest%% *}
size=${rest##* }
gw=${size%%x*}
gh=${size##*x}
cx=$((gx + gw / 2))
cy=$((gy + gh / 2))

rm -rf "$RUN"
mkdir -p "$RUN"
touch "$RUN/running"
trap 'rm -rf "$RUN"' EXIT

notify-send -a niri -t 3000 "Scrolling screenshot" \
  "Starts in ${START_DELAY}s — hover the area. Fire the bind again to stop early."
sleep "$START_DELAY"

ydotool mousemove --absolute --xpos "$cx" --ypos "$cy" 2>/dev/null || true

grim -g "$geom" "$RUN/f0.png"
prev="$RUN/prev.png"
cp "$RUN/f0.png" "$prev"
frames=("$RUN/f0.png")
bottom_hits=0
n=0

# template strip taken from the previous frame each round:
# 50% width centered, 25% height sitting at 40% down the frame
sw=$((gw * 50 / 100))
sh=$((gh * 25 / 100))
sx=$(( (gw - sw) / 2 ))
sy=$((gh * 40 / 100))
# coarse pass runs at 1/4 scale; the fine pass re-matches at full res inside a
# narrow band (scroll is vertical only, so the x offset never changes)
sw4=$((sw / 4))
sh4=$((sh / 4))
sx4=$((sx / 4))
sy4=$((sy / 4))
TOL=10

match_delta() { # $1=cur.png -> prints scroll delta in px, or nothing
  magick "$1" -colorspace Gray "$RUN/cur_g.png"
  magick "$RUN/cur_g.png" -resize 25% "$RUN/cur_gs.png"
  magick "$prev" -colorspace Gray -crop "${sw}x${sh}+${sx}+${sy}" +repage "$RUN/strip_g.png"
  magick "$RUN/strip_g.png" -resize 25% "$RUN/strip_gs.png"

  local out loc y1c y_est band_y y1
  out=$(magick compare -metric RMSE -subimage-search \
    "$RUN/cur_gs.png" "$RUN/strip_gs.png" "$RUN/d1.png" 2>&1 || true)
  loc=$(printf '%s' "$out" | grep -oE '@ [0-9]+,[0-9]+' | tail -1 | tr -d '@ ')
  [ -n "$loc" ] || return 1
  y1c=${loc##*,}
  y_est=$((y1c * 4))
  band_y=$((y_est - TOL))
  [ "$band_y" -lt 0 ] && band_y=0

  magick "$RUN/cur_g.png" -crop "${sw}x$((sh + 2 * TOL))+${sx}+${band_y}" +repage "$RUN/band.png"
  out=$(magick compare -metric RMSE -subimage-search \
    "$RUN/band.png" "$RUN/strip_g.png" "$RUN/d2.png" 2>&1 || true)
  loc=$(printf '%s' "$out" | grep -oE '@ [0-9]+,[0-9]+' | tail -1 | tr -d '@ ')
  [ -n "$loc" ] || return 1
  y1=${loc##*,}
  echo $((sy - band_y - y1))
}

while [ "$n" -lt "$MAX_FRAMES" ]; do
  ydotool mousemove --wheel -- 0 "-$WHEEL_NOTCHES" 2>/dev/null || true
  sleep "$SETTLE"
  [ -f "$RUN/stop" ] && break

  cur="$RUN/cur.png"
  grim -g "$geom" "$cur"

  delta=$(match_delta "$cur" || true)
  if [ -z "$delta" ] || [ "$delta" -lt 3 ]; then
    bottom_hits=$((bottom_hits + 1))
  else
    bottom_hits=0
    crop="$RUN/crop$n.png"
    magick "$cur" -gravity South -crop "${gw}x${delta}+0+0" +repage "$crop"
    frames+=("$crop")
    cp "$cur" "$prev"
  fi
  [ "$bottom_hits" -ge 2 ] && break
  n=$((n + 1))
done

stamp=$(date +"Screenshot Scroll %Y-%m-%d %H-%M-%S.png")
out_png="$OUT_DIR/$stamp"
magick "${frames[@]}" -append "$out_png"
wl-copy <"$out_png"
notify-send -a niri -t 4000 "Scrolling screenshot saved" \
  "$out_png — also on the clipboard"
qs -c sunset ipc call screenshots open "$out_png" 2>/dev/null || true
