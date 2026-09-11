#!/bin/bash
# clipboard-save-image.sh — save the current clipboard image to
# ~/Pictures/Clipboard/ with a timestamped filename.
set -euo pipefail

out_dir="${HOME}/Pictures/Clipboard"
mkdir -p "$out_dir"

# Detect which image MIME type the clipboard offers.
types=$(wl-paste --list-types 2>/dev/null || true)
type=""
ext=""
case "$types" in
  *image/png*)  type=image/png;  ext=png  ;;
  *image/jpeg*) type=image/jpeg; ext=jpg  ;;
  *image/gif*)  type=image/gif;  ext=gif  ;;
  *image/webp*) type=image/webp; ext=webp ;;
  *image/bmp*)  type=image/bmp;  ext=bmp  ;;
  *image/tiff*) type=image/tiff; ext=tiff ;;
esac

# If the clipboard already carries a saved path for this image (stored by
# clip-path-watcher.py), reuse it instead of writing a duplicate file.
if [ -n "$type" ]; then
  for cand in $(wl-paste --type text 2>/dev/null || true); do
    case "$cand" in
      "${HOME}/.cache/cliphist/images/"*)
        if [ -f "$cand" ] && cmp -s <(wl-paste -t "$type" 2>/dev/null) "$cand"; then
          setsid -f /home/me/niri-setup/scripts/clipboard-offer.py "$cand" "$cand" 2>/dev/null
          notify-send -a niri -i image-x-generic "Clipboard image" "$cand"
          exit 0
        fi
        ;;
    esac
  done
fi

if [ -z "$type" ]; then
  notify-send -a niri -i dialog-information "No image in clipboard" \
    "The clipboard doesn't contain an image to save."
  exit 0
fi

stamp=$(date +%Y%m%d-%H%M%S)
out="${out_dir}/clipboard-${stamp}.${ext}"

wl-paste -t "$type" > "$out" 2>/dev/null || true

if [ -s "$out" ]; then
  cliphist store < "$out" 2>/dev/null || true
  setsid -f /home/me/niri-setup/scripts/clipboard-offer.py "$out" "$out" 2>/dev/null
  notify-send -a niri -i image-x-generic "Clipboard image saved" "$out"
else
  rm -f "$out"
  notify-send -a niri -i dialog-warning "Save failed" \
    "Could not read an image from the clipboard."
fi
