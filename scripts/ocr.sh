#!/bin/bash
# ocr.sh — tesseract OCR on an image file -> clipboard + notification.
# Usage: ocr.sh <image>
# Env:   OCR_LANGS  tesseract language pack(s), e.g. "eng" or "eng+fra"
set -uo pipefail

img="${1:-}"
if [ -z "$img" ] || [ ! -f "$img" ]; then
  notify-send -u critical -a niri "OCR" "no image: $img"
  exit 1
fi

text=$(tesseract "$img" stdout \
  --oem 1 --psm 6 -l "${OCR_LANGS:-eng}" --dpi 300 \
  -c preserve_interword_spaces=1 2>/dev/null) || {
  notify-send -u critical -a niri "OCR" "tesseract failed on $(basename "$img")"
  exit 1
}

if [ -z "${text//[[:space:]]/}" ]; then
  notify-send -a niri -t 3000 "OCR" "No text found"
  exit 0
fi

printf '%s' "$text" | wl-copy
preview=$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-80)
notify-send -a niri -t 4000 "OCR — copied to clipboard" "$preview"
