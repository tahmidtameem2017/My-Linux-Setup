#!/usr/bin/env python3
"""Power menu backend for the themed HTML popup (stdlib only).

Serves power.html and one endpoint:

  GET  /            -> power.html
  POST /api/action  -> {"op": shutdown|reboot|suspend|logout|lock}

Only these five fixed commands can run; the client can never inject
arbitrary commands. Matches the actions from wlogout/layout.

Binds 127.0.0.2 (NOT 127.0.0.1/localhost) on an ephemeral port so Brave
derives a distinct app-id from the volume/wallpaper popups. Port goes to
$NIRI_POWER_DIR/port (default ~/.cache/niri-power/port).
"""

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(BASE_DIR))
HTML_FILE = os.path.join(BASE_DIR, "power.html")
STATE_DIR = os.environ.get(
    "NIRI_POWER_DIR", os.path.join(os.path.expanduser("~"), ".cache", "niri-power")
)
PORT_FILE = os.path.join(STATE_DIR, "port")
SWAYLOCK_SH = os.path.join(REPO_ROOT, "scripts", "swaylock.sh")

# Fixed allowlist: op -> argv. Nothing else can ever execute.
ACTIONS = {
    "shutdown": ["systemctl", "poweroff"],
    "reboot": ["systemctl", "reboot"],
    "suspend": ["systemctl", "suspend"],
    "logout": ["pkill", "niri"],
    "lock": ["bash", SWAYLOCK_SH],
}


class Handler(BaseHTTPRequestHandler):
    server_version = "NiriPower/1.0"

    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(HTML_FILE, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(data)
            except OSError:
                self._json(500, {"error": "power.html not found"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/action":
            return self._json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "invalid JSON"})
        argv = ACTIONS.get(payload.get("op", ""))
        if argv is None:
            return self._json(400, {"error": "unknown op"})
        try:
            # Detached: the HTTP response must go out before a
            # shutdown/reboot/logout kills our session.
            subprocess.Popen(
                argv,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as e:
            return self._json(500, {"error": str(e)})
        return self._json(200, {"ok": True})


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.2", 0), Handler)
    with open(PORT_FILE, "w") as f:
        f.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
