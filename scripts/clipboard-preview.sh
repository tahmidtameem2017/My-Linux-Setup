#!/usr/bin/env bash
# clipboard-preview.sh <cid> <kind> — emit preview payload on stdout.
#   "IMG <abs-path>" on the first line, else "TXT" then decoded text.
set -u
cid=${1:-}
kind=${2:-txt}
[[ $cid =~ ^[0-9]+$ ]] || exit 0
bin=/tmp/clipboard-preview.bin
rm -f "$bin"
cliphist decode "$cid" >"$bin" 2>/dev/null
if [[ $kind == img ]]; then
    ext=$(python3 -c '
import sys
d = open(sys.argv[1], "rb").read(16)
if d.startswith(b"\x89PNG"): print("png")
elif d[:3] == b"GIF": print("gif")
elif d[:2] == b"\xff\xd8": print("jpg")
elif d[:4] == b"RIFF" and d[8:12] == b"WEBP": print("webp")
elif d[:2] == b"BM": print("bmp")
elif d[:4] in (b"II*\x00", b"MM\x00*"): print("tiff")
else: print("png")' "$bin")
    out=/tmp/clipboard-preview.$ext
    cp "$bin" "$out"
    echo "IMG $out"
else
    echo "TXT"
    head -c 6000 "$bin" | iconv -f UTF-8 -t UTF-8//IGNORE 2>/dev/null | head -n 200
fi
