#!/usr/bin/env python3
"""Volume mixer backend for the themed HTML popup (stdlib only).

Serves volume.html and a small JSON API backed by wpctl/pactl:

  GET  /              -> volume.html
  GET  /api/status    -> {"volume": int, "muted": bool, "sink": str, "sinks": [...]}
  POST /api/volume    -> {"value": 0-100}
  POST /api/mute      -> {"muted": bool} (absent = toggle)
  POST /api/sink      -> {"name": sink_name} (set default sink)

Binds 127.0.0.1 on an ephemeral port and writes it to
$NIRI_VOLUME_DIR/port (default ~/.cache/niri-volume/port) so the
launcher script knows where to point the browser.
"""

import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
HTML_FILE = os.path.join(BASE_DIR, "volume.html")
STATE_DIR = os.environ.get(
    "NIRI_VOLUME_DIR", os.path.join(os.path.expanduser("~"), ".cache", "niri-volume")
)
PORT_FILE = os.path.join(STATE_DIR, "port")


def run(*args):
    """Run a command, return stdout on success else empty string (never raises)."""
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return proc.stdout if proc.returncode == 0 else ""
    except Exception:
        return ""


def parse_sinks():
    """Return (sinks, default_name) from pactl. Sinks: [{name, desc, muted}]."""
    out = run("pactl", "list", "sinks")
    sinks = []
    current = {}
    for line in out.splitlines():
        if line.startswith("Sink #"):
            if current.get("name"):
                sinks.append(current)
            current = {}
        elif line.strip().startswith("Name:"):
            current["name"] = line.split("Name:", 1)[1].strip()
        elif line.strip().startswith("Description:"):
            current["desc"] = line.split("Description:", 1)[1].strip()
        elif line.strip().startswith("Mute:"):
            current["muted"] = line.split("Mute:", 1)[1].strip().lower() == "yes"
    if current.get("name"):
        sinks.append(current)
    for s in sinks:
        s.setdefault("desc", s["name"])
        s.setdefault("muted", False)

    default = ""
    info = run("pactl", "info")
    m = re.search(r"^Default Sink:\s*(\S+)", info, re.M)
    if m:
        default = m.group(1)
    return sinks, default


def get_status():
    out = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
    m = re.search(r"Volume:\s*([\d.]+)", out)
    volume = round(float(m.group(1)) * 100) if m else 0
    muted = "[MUTED]" in out
    sinks, default = parse_sinks()
    desc = default
    for s in sinks:
        s["default"] = s["name"] == default
        if s["default"]:
            desc = s["desc"]
            muted = muted or s["muted"]
    return {"volume": volume, "muted": muted, "sink": desc, "sinks": sinks}


class Handler(BaseHTTPRequestHandler):
    server_version = "NiriVolume/1.0"

    def log_message(self, *args):
        pass  # keep quiet

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, code, obj):
        self._send(code, json.dumps(obj))

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(HTML_FILE, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                self._send_json(500, {"error": "volume.html not found"})
        elif self.path == "/api/status":
            self._send_json(200, get_status())
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            return self._send_json(400, {"error": "invalid JSON"})

        if self.path == "/api/volume":
            try:
                value = max(0, min(100, int(payload.get("value", 0))))
            except (TypeError, ValueError):
                return self._send_json(400, {"error": "value must be 0-100"})
            run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value}%")
            return self._send_json(200, get_status())

        if self.path == "/api/mute":
            if "muted" in payload:
                arg = "1" if payload["muted"] else "0"
            else:
                arg = "toggle"
            run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", arg)
            return self._send_json(200, get_status())

        if self.path == "/api/sink":
            name = payload.get("name", "")
            if not name:
                return self._send_json(400, {"error": "name required"})
            run("pactl", "set-default-sink", name)
            return self._send_json(200, get_status())

        return self._send_json(404, {"error": "not found"})


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(PORT_FILE, "w") as f:
        f.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
