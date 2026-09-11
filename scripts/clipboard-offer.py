#!/usr/bin/env python3
"""clipboard-offer.py — put image bytes + copyable path on the clipboard.

Usage:
    clipboard-offer.py IMAGE_FILE [PATH_TEXT]

Serves, in one clipboard offer (no focus stealing, works headless):
    image/<fmt>            exact bytes of IMAGE_FILE
    text/uri-list          file:// URI of PATH_TEXT (or IMAGE_FILE)
    text/plain(+variants)  raw filesystem path

Image editors get the picture; terminals/text fields get a path they can
use. Needs python-pywayland (Arch: python-pywayland). Runs until the
clipboard is replaced — launch detached (setsid) so the caller can exit.
"""

import os
import sys

sys.path.insert(0, os.path.expanduser("~/.local/lib/niri-clipboard"))
try:
    from pywayland.client import Display
    from pywayland.protocol.ext_data_control_v1 import (
        ExtDataControlManagerV1,
    )
    from pywayland.protocol.wayland import WlSeat
except ImportError:
    sys.stderr.write("clipboard-offer.py: python-pywayland is not installed\n")
    sys.exit(1)


def detect_mime(blob):
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if blob[:3] == b"GIF":
        return "image/gif"
    if blob[:2] == b"\xff\xd8":
        return "image/jpeg"
    if blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
        return "image/webp"
    if blob[:2] == b"BM":
        return "image/bmp"
    return None


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: clipboard-offer.py IMAGE_FILE [PATH_TEXT]\n")
        sys.exit(2)
    img_path = os.path.abspath(sys.argv[1])
    path_text = sys.argv[2] if len(sys.argv) > 2 else img_path
    with open(img_path, "rb") as f:
        img_bytes = f.read()
    mime = detect_mime(img_bytes)
    if mime is None:
        sys.stderr.write("clipboard-offer.py: not a recognized image\n")
        sys.exit(1)
    uri = "file://" + path_text + "\r\n"
    raw = path_text.encode()

    data = {
        mime: img_bytes,
        "text/uri-list": uri.encode(),
        "text/plain;charset=utf-8": raw,
        "text/plain": raw,
        "TEXT": raw,
        "STRING": raw,
        "UTF8_STRING": raw,
    }

    display = Display()
    display.connect()
    state = {}

    def on_global(registry, id_, interface, version):
        if interface == "ext_data_control_manager_v1":
            state["manager"] = registry.bind(id_, ExtDataControlManagerV1, 1)
        elif interface == "wl_seat":
            state["seat"] = registry.bind(id_, WlSeat, min(version, 7))

    registry = display.get_registry()
    registry.dispatcher["global"] = on_global
    display.roundtrip()
    if "manager" not in state or "seat" not in state:
        sys.stderr.write("clipboard-offer.py: no data-control manager/seat\n")
        sys.exit(1)

    device = state["manager"].get_data_device(state["seat"])
    display.roundtrip()

    def on_send(_src, mime_type, fd):
        try:
            os.write(fd, data.get(mime_type, b""))
        finally:
            os.close(fd)

    def on_cancelled(_src):
        raise SystemExit(0)

    source = state["manager"].create_data_source()
    source.dispatcher["send"] = on_send
    source.dispatcher["cancelled"] = on_cancelled
    for mime_type in data:
        source.offer(mime_type)
    device.set_selection(source)
    display.flush()

    while display.dispatch(block=True) != -1:
        pass


main()
