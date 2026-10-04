#!/bin/bash
# copy-file.sh <path> — copy a file to the Wayland clipboard.
# Text files (.txt .md .py .c .cpp ...) copy their CONTENTS as
# text/plain; images (.jpg .png .jpeg ...) copy their bytes with
# the matching image/* MIME, so both paste like a screenshot does.
# Directories and unknown types copy the path string instead, so
# Ctrl+C on any file row always has a useful result.
set -uo pipefail

p="${1:-}"
[ -n "$p" ] || exit 2

# A directory has no contents to copy: the path is the payload.
if [ -d "$p" ]; then
  wl-copy -- "$p" 2>/dev/null || true
  exit 0
fi

ext="${p##*.}"
ext="${ext,,}"

case "$ext" in
  jpg|jpeg) mime="image/jpeg" ;;
  png)      mime="image/png" ;;
  webp)     mime="image/webp" ;;
  gif)      mime="image/gif" ;;
  bmp)      mime="image/bmp" ;;
  svg)      mime="image/svg+xml" ;;
  ico)      mime="image/vnd.microsoft.icon" ;;
  tif|tiff) mime="image/tiff" ;;
  avif)     mime="image/avif" ;;
  heic)     mime="image/heic" ;;
  heif)     mime="image/heif" ;;
  # Text: contents land as plain text, ready to paste anywhere.
  txt|md|markdown|py|c|h|cpp|hpp|cc|cxx|hxx|js|mjs|cjs|ts|jsx|tsx|qml|rs|go|java|kt|kts|sh|bash|zsh|kdl|json|toml|yaml|yml|css|scss|sass|less|html|htm|xml|lua|vim|sql|ini|cfg|conf|log|csv|tsv|tex|rst|swift|rb|php|pl|pm|r|m|mm|dart|vue|svelte|gradle|env|nix|el|ex|exs|erl|clj|fs|ml|hs|sc|awk|sed|mak|mk|properties)
    wl-copy --type text/plain < "$p" 2>/dev/null || true
    exit 0
    ;;
  *)
    # Binaries, archives, media: copy the path so the row is
    # still pasteable (same payload a drag carries as text/plain).
    wl-copy -- "$p" 2>/dev/null || true
    exit 0
    ;;
esac

wl-copy --type "$mime" < "$p" 2>/dev/null || true
