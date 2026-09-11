#!/usr/bin/env python3
"""clip-path-watcher.py — save a path sidecar next to every clipboard image.

Runs as `wl-paste --type image --watch clip-path-watcher.py save` (started
from spawn-at-startup.kdl). Each time an image lands on the clipboard, the
script saves the exact bytes to ~/.cache/cliphist/images/ and stores the
saved path back into cliphist history, so the picker shows an
image entry AND a copyable path entry for it.
"""

import hashlib
import os
import subprocess
import sys

IMG_DIR = os.path.expanduser("~/.cache/cliphist/images")


def detect_ext(blob):
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if blob[:3] == b"GIF":
        return "gif"
    if blob[:2] == b"\xff\xd8":
        return "jpg"
    if blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
        return "webp"
    if blob[:2] == b"BM":
        return "bmp"
    if blob[:4] in (b"II*\x00", b"MM\x00*"):
        return "tiff"
    return None


def main():
    if len(sys.argv) < 2 or sys.argv[1] != "save":
        sys.stderr.write("usage: wl-paste --type image --watch "
                         "clip-path-watcher.py save\n")
        sys.exit(2)
    blob = sys.stdin.buffer.read()
    if not blob:
        return
    ext = detect_ext(blob)
    if ext is None:
        return
    os.makedirs(IMG_DIR, exist_ok=True)
    name = hashlib.sha256(blob).hexdigest()[:16] + "." + ext
    dest = os.path.join(IMG_DIR, name)
    if not os.path.exists(dest):
        with open(dest, "wb") as f:
            f.write(blob)
        subprocess.run(["cliphist", "store"], input=dest.encode(),
                       check=False)


main()
