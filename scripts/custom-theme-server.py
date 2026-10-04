#!/usr/bin/env python3
"""Loopback server for the custom palette editor (help/custom-theme.html).

Why a server at all: the page has to WRITE ~/.local/share/niri-setup/
theme-custom.json, and a file:// page cannot do that. Brave will not give a
file:// origin write access, and there is no portable way to ask. So the page is
served over http://127.0.0.1 and this is the only thing listening.

Design notes that are load-bearing, not decoration:

* **In-place writes, never rename-replace.** quickshell watches this file with
  QFileSystemWatcher, which binds to the *inode*. The atomic
  write-tmp-then-mv dance that every other script here uses to avoid torn reads
  would therefore replace the inode and the watch would silently stop firing —
  the editor would appear to save and the theme would never change. So this
  truncates and rewrites the same file. A reader can in principle catch a torn
  write; Theme.qml's applyCustomJson() rejects unparseable/partial JSON and
  retries on the next change event, so correctness is preserved either way.

* **Token in the URL + a required header on POST.** This listens on loopback,
  which sounds safe, but every page in the user's browser can reach loopback.
  Without the token, any website they visit could POST a palette and repaint
  their whole desktop. Requiring the header means a cross-origin page cannot
  even issue the request (and a preflight fails, since we answer no CORS
  headers). This is the same threat the legacy waybar popup servers had, and
  this time it is actually closed.

* **Strict 11-key validation.** Anything else written here is read by the bar,
  the launcher, tmux, alacritty, niri and the focus ring. A missing key means a
  palette that fails to apply and a confusing half-themed desktop, so we refuse.

Usage (normally via scripts/custom-theme.sh):
    custom-theme-server.py --port 4097 --token <hex> [--setup-home DIR]
"""

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from colorlib import KEYS  # noqa: E402

PAGE = "custom-theme.html"
CUSTOM_BASENAME = "theme-custom.json"

# Its own loopback address, not 127.0.0.1. Chromium derives the window app-id
# from the host (brave-127.0.0.1__-Default etc), and niri/rules.kdl already
# pins 127.0.0.1 to the legacy volume popup's 400x440. Reusing it would drop
# this editor into a postage stamp. .7 is unclaimed, and a distinct app-id also
# means its own window rule can be sized for an editor instead of a popup.
DEFAULT_HOST = "127.0.0.7"
TOKEN_HEADER = "X-Theme-Token"
MAX_BODY = 64 * 1024
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

# Matches Theme.qml's `customPalette` default, so "Reset" and a fresh clone
# agree on what an unedited Custom looks like.
DEFAULT_PALETTE = {
    "bg": "#000000",
    "panel": "#0a0a0a",
    "row": "#141010",
    "border": "#1a1210",
    "borderStrong": "#3D2B24",
    "accent": "#E85D2F",
    "accentHover": "#FF8B4A",
    "text": "#F7C7A1",
    "muted": "#7C8A6A",
    "dim": "#555555",
    "danger": "#DC3030",
}


def valid_palette(value):
    """Return the palette if it is exactly the 11 valid keys, else None."""
    if not isinstance(value, dict):
        return None
    if set(value) != set(KEYS):
        return None
    if not all(isinstance(value[k], str) and HEX.match(value[k]) for k in KEYS):
        return None
    return {k: value[k].upper() for k in KEYS}


def write_in_place(path, text):
    """Rewrite `path` without replacing its inode (see module docstring)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    # r+ leaves the inode alone; truncate() then write() gives the same bytes a
    # fresh file would have.
    with open(path, "r+") if path.exists() else open(path, "w") as handle:
        handle.truncate(0)
        handle.seek(0)
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())


class Handler(BaseHTTPRequestHandler):
    server_version = "custom-theme/1.0"

    # Injected by main().
    token = ""
    theme_dir = Path.home() / ".local" / "share" / "niri-setup"
    setup_home = Path.home() / "niri-setup"
    page_path = Path.home() / "niri-setup" / "help" / PAGE

    # ---- helpers ---------------------------------------------------------

    def _send(self, code, body=b"", ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        # No CORS headers on purpose: see the module docstring. A page on any
        # other origin must not be able to read or POST to this server.
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code, payload):
        self._send(code, json.dumps(payload, indent=2) + "\n")

    def _authorised(self):
        return secrets.compare_digest(self.headers.get(TOKEN_HEADER, ""), self.token)

    def custom_path(self):
        return self.theme_dir / CUSTOM_BASENAME

    def read_custom(self):
        try:
            return valid_palette(json.loads(self.custom_path().read_text()))
        except (OSError, ValueError):
            return None

    def apply_in_shell(self):
        """Ask the running shell to switch to Custom (turns auto off)."""
        qs = "qs"
        try:
            subprocess.run([qs, "-c", "sunset", "ipc", "call", "themes", "set", "custom"],
                           capture_output=True, text=True, timeout=15)
            return True
        except (OSError, subprocess.SubprocessError):
            return False

    # ---- routes ----------------------------------------------------------

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        path = self.path.split("?", 1)[0]
        if path == "/":
            try:
                html = self.page_path.read_bytes()
            except OSError:
                return self._json(500, {"error": "missing %s" % self.page_path})
            return self._send(200, html, "text/html; charset=utf-8")
        if path == "/api/theme":
            return self._json(200, {
                "custom": self.read_custom() or DEFAULT_PALETTE,
                "path": str(self.custom_path()),
                "exists": self.custom_path().exists(),
            })
        if path == "/api/palettes":
            return self._json(200, self.collect_palettes())
        if path == "/api/health":
            return self._json(200, {"ok": True})
        return self._json(404, {"error": "no such route"})

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_POST(self):  # noqa: N802
        if not self._authorised():
            return self._json(403, {"error": "bad or missing %s" % TOKEN_HEADER})
        path = self.path.split("?", 1)[0]
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._json(400, {"error": "bad Content-Length"})
        if length <= 0 or length > MAX_BODY:
            return self._json(400, {"error": "empty or oversized body"})
        try:
            payload = json.loads(self.rfile.read(length))
        except ValueError:
            return self._json(400, {"error": "body is not JSON"})

        palette = valid_palette(payload.get("palette"))
        if palette is None:
            return self._json(400, {
                "error": "palette must be exactly these 11 keys, each #rrggbb: %s"
                         % ", ".join(KEYS)})

        try:
            write_in_place(self.custom_path(),
                           json.dumps(palette, indent=2) + "\n")
        except OSError as error:
            return self._json(500, {"error": str(error)})

        # NB: no external sync from here. scripts/sync-external-theme.py reads
        # active-theme.json, which is the shell's *output* — so calling it the
        # instant the file lands races the shell's own publish and pushes the
        # previous palette (it truthfully reports "changed:" with nothing in
        # it). The shell runs the exporter itself from paletteSyncTimer, which
        # is the only ordering that is actually correct.
        applied = False
        if payload.get("apply"):
            applied = self.apply_in_shell()

        return self._json(200, {
            "ok": True,
            "palette": palette,
            "applied": applied,
            "shellRunning": applied,
        })

    def collect_palettes(self):
        """Every palette the editor can start from.

        Reads the files Theme.qml reads, so "start from Everforest" gives the
        exact colours the shell would apply, not a second copy that can drift.
        """
        out = {"active": None, "variants": {}}
        try:
            active = json.loads((self.theme_dir / "active-theme.json").read_text())
            out["active"] = valid_palette(active)
        except (OSError, ValueError):
            pass
        for path in sorted(self.theme_dir.glob("theme-*.json")):
            if path.name == CUSTOM_BASENAME:
                continue
            try:
                palette = valid_palette(json.loads(path.read_text()))
            except (OSError, ValueError):
                continue
            if palette:
                out["variants"][path.stem[len("theme-"):]] = palette
        return out

    def log_message(self, fmt, *args):
        # Keep the launcher's captured output quiet but keep real errors.
        sys.stderr.write("[custom-theme] " + fmt % args + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=4097)
    parser.add_argument("--host", default=DEFAULT_HOST,
                        help="loopback address; do not point this off 127.0.0.0/8")
    parser.add_argument("--token", default=None,
                        help="shared secret required on POST; generated if omitted")
    parser.add_argument("--setup-home", default=os.environ.get(
        "NIRI_SETUP_HOME", os.path.expanduser("~/niri-setup")))
    args = parser.parse_args(argv)

    # Loopback only. Not paranoia about the user's network: a browser on this
    # machine reaches any address, and the whole point of the token is that a
    # page on another origin cannot drive this. That guarantee is meaningless
    # if the server is reachable from the network.
    if not re.match(r"^127\.\d+\.\d+\.\d+$", args.host):
        parser.error("this server is loopback-only by design")

    Handler.token = args.token or secrets.token_urlsafe(24)
    Handler.setup_home = Path(args.setup_home).expanduser()
    Handler.page_path = Handler.setup_home / "help" / PAGE
    Handler.theme_dir = Path(os.environ.get(
        "NIRI_SETUP_THEME_DIR",
        os.path.expanduser("~/.local/share/niri-setup")))

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    url = "http://%s:%d/?t=%s" % (args.host, args.port, Handler.token)
    # The wrapper reads this line to open the browser.
    print(url, flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())