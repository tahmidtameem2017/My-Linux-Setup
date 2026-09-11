#!/usr/bin/env python3
"""clipboard-pick.py — paste one history entry as image+path when paired.

Takes fuzzel-selected `cliphist list` line(s) on stdin, decodes the entry,
and:
  - image entry immediately followed (older) by its saved path entry
    (written by clip-path-watcher.py): offer BOTH together — image/png
    plus text/uri-list + text/plain path — via clipboard-offer.py, so a
    text field receives the copyable path while image apps get pixels.
  - anything else: restore bytes verbatim with `wl-copy` (legacy path).
"""

import hashlib
import os
import subprocess
import sys

IMG_DIR = os.path.expanduser("~/.cache/cliphist/images")
OFFER = "/home/me/niri-setup/scripts/clipboard-offer.py"


def is_image(blob):
    return (
        blob[:8] == b"\x89PNG\r\n\x1a\n"
        or blob[:3] == b"GIF"
        or blob[:2] == b"\xff\xd8"
        or (blob[:4] == b"RIFF" and blob[8:12] == b"WEBP")
        or blob[:2] == b"BM"
        or blob[:4] in (b"II*\x00", b"MM\x00*")
    )


def looks_like_path(blob):
    try:
        text = blob.decode("utf-8").strip()
    except UnicodeDecodeError:
        return None
    if (
        text.startswith("/")
        and "\x00" not in text
        and "\n" not in text
        and os.path.exists(text)
    ):
        return text
    return None


def decode(entry_id):
    return subprocess.run(
        ["cliphist", "decode", str(entry_id)],
        capture_output=True, check=False,
    ).stdout


def entry_ids():
    out = subprocess.run(
        ["cliphist", "list"], capture_output=True, check=False
    ).stdout.decode("utf-8", "replace").splitlines()
    ids = []
    for line in out:
        head, _, _ = line.partition("\t")
        if head.strip().isdigit():
            ids.append(int(head.strip()))
    return ids


def main():
    sel_ids = []
    for line in sys.stdin.read().splitlines():
        head, _, _ = line.partition("\t")
        if head.strip().isdigit():
            sel_ids.append(int(head.strip()))
    if not sel_ids:
        return

    ids = entry_ids()
    pos = {i: n for n, i in enumerate(ids)}
    picked = sel_ids[0]
    blob = decode(picked)

    pair_path = None
    if is_image(blob) and picked in pos:
        for older in ids[pos[picked] + 1:]:
            if older in sel_ids:
                continue
            cand = decode(older)
            path = looks_like_path(cand)
            if path is None:
                continue
            if os.path.dirname(path) == IMG_DIR:
                pair_path = path
                break
            if hashlib.sha256(blob).hexdigest()[:16] in path:
                pair_path = path
                break
            break

    if pair_path is not None:
        tmp = pair_path + ".offer.png"
        with open(tmp, "wb") as f:
            f.write(blob)
        subprocess.run(["setsid", "-f", OFFER, tmp, pair_path], check=False)
    else:
        subprocess.run(["wl-copy"], input=blob, check=False)


main()
