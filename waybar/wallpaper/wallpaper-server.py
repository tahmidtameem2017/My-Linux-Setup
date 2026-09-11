#!/usr/bin/env python3
"""Wallpaper gallery backend for the themed HTML popup (stdlib only).

Serves wallpaper.html and a small JSON API reusing the existing scripts:

  GET  /              -> wallpaper.html
  GET  /api/list      -> {"images": [{"id","name"}], "current": name, "auto": status}
  GET  /thumb/<id>    -> cached thumbnail (magick) or original
  GET  /full/<id>     -> original image (preview pane)
  POST /api/set       -> {"id"} runs scripts/wallpaper.sh (full pipeline)
  POST /api/action    -> {"op": "random"|"next"|"prev"} via change-wallpaper-simple.sh
  POST /api/auto      -> {"op": "start"|"stop"} via auto-wallpaper.sh

Binds 127.0.0.1 on an ephemeral port, writes it to
$NIRI_WALLPAPER_DIR/port (default ~/.cache/niri-wallpaper/port).
Image ids are indexes into the sorted library scan, never client paths.
"""

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(BASE_DIR))
HTML_FILE = os.path.join(BASE_DIR, "wallpaper.html")
WALLPAPER_DIR = os.path.join(os.path.expanduser("~"), "Pictures", "Wallpapers")
STATE_DIR = os.environ.get(
    "NIRI_WALLPAPER_DIR", os.path.join(os.path.expanduser("~"), ".cache", "niri-wallpaper")
)
PORT_FILE = os.path.join(STATE_DIR, "port")
THUMB_DIR = os.path.join(STATE_DIR, "thumbs")
CURRENT_FILE = os.path.join(REPO_ROOT, ".state", "current_wallpaper")
SET_SCRIPT = os.path.join(REPO_ROOT, "scripts", "wallpaper.sh")
STEP_SCRIPT = os.path.join(REPO_ROOT, "scripts", "change-wallpaper-simple.sh")
AUTO_SCRIPT = os.path.join(REPO_ROOT, "scripts", "auto-wallpaper.sh")

EXTS = (".jpg", ".jpeg", ".png", ".webp", ".avif")
MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".avif": "image/avif",
}


def run(*args, timeout=30):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, (proc.stdout or "").strip()
    except Exception as e:
        return 1, str(e)


def scan():
    """Sorted list of absolute image paths (top level only)."""
    try:
        names = sorted(os.listdir(WALLPAPER_DIR))
    except OSError:
        return []
    return [
        os.path.join(WALLPAPER_DIR, n)
        for n in names
        if n.lower().endswith(EXTS)
        and os.path.isfile(os.path.join(WALLPAPER_DIR, n))
    ]


def current_name():
    try:
        with open(CURRENT_FILE) as f:
            return os.path.basename(f.read().strip())
    except OSError:
        return ""


def auto_status():
    code, out = run(AUTO_SCRIPT, "--status", timeout=5)
    lines = [l for l in out.splitlines() if l.strip()]
    return lines[0] if lines else ("stopped" if code else "unknown")


def thumb_for(path):
    """Return thumbnail bytes (cached), falling back to the original."""
    try:
        st = os.stat(path)
    except OSError:
        return None, None
    ext = os.path.splitext(path)[1].lower()
    cache = os.path.join(
        THUMB_DIR, f"{st.st_mtime_ns}_{st.st_size}_{os.path.basename(path)}.jpg"
    )
    if os.path.isfile(cache):
        try:
            with open(cache, "rb") as f:
                return f.read(), "image/jpeg"
        except OSError:
            pass
    code, _ = run(
        "magick",
        path + "[0]",
        "-auto-orient",
        "-thumbnail",
        "384x216",
        cache,
        timeout=20,
    )
    if code == 0 and os.path.isfile(cache):
        try:
            with open(cache, "rb") as f:
                return f.read(), "image/jpeg"
        except OSError:
            pass
    try:
        with open(path, "rb") as f:
            return f.read(), MIME.get(ext, "application/octet-stream")
    except OSError:
        return None, None


class Handler(BaseHTTPRequestHandler):
    server_version = "NiriWallpaper/1.0"

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj))

    def _status(self):
        images = scan()
        cur = current_name()
        return {
            "images": [{"id": i, "name": os.path.basename(p)} for i, p in enumerate(images)],
            "current": cur,
            "auto": auto_status(),
            "count": len(images),
        }

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(HTML_FILE, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                self._json(500, {"error": "wallpaper.html not found"})
        elif self.path == "/api/list":
            self._json(200, self._status())
        elif self.path.startswith("/thumb/") or self.path.startswith("/full/"):
            kind, _, raw = self.path[1:].partition("/")
            try:
                idx = int(raw.split("?", 1)[0].split("/", 1)[0])
            except ValueError:
                return self._json(400, {"error": "bad id"})
            images = scan()
            if not 0 <= idx < len(images):
                return self._json(404, {"error": "unknown id"})
            if kind == "thumb":
                data, ctype = thumb_for(images[idx])
            else:
                try:
                    with open(images[idx], "rb") as f:
                        data = f.read()
                    ctype = MIME.get(os.path.splitext(images[idx])[1].lower(),
                                     "application/octet-stream")
                except OSError:
                    data, ctype = None, None
            if data is None:
                return self._json(500, {"error": "cannot read image"})
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "public, max-age=86400")
            self.end_headers()
            self.wfile.write(data)
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "invalid JSON"})
        images = scan()

        if self.path == "/api/set":
            try:
                idx = int(payload.get("id", -1))
            except (TypeError, ValueError):
                return self._json(400, {"error": "id required"})
            if not 0 <= idx < len(images):
                return self._json(404, {"error": "unknown id"})
            code, out = run(SET_SCRIPT, images[idx], timeout=300)
            status = self._status()
            status["ok"] = code == 0
            status["message"] = out.splitlines()[-1] if out else ""
            return self._json(200, status)

        if self.path == "/api/action":
            op = payload.get("op", "")
            if op not in ("random", "next", "prev"):
                return self._json(400, {"error": "op must be random|next|prev"})
            run(STEP_SCRIPT, op, timeout=60)
            return self._json(200, self._status())

        if self.path == "/api/auto":
            op = payload.get("op", "")
            if op == "stop":
                run(AUTO_SCRIPT, "--stop", timeout=10)
            elif op == "start":
                try:
                    subprocess.Popen(
                        [AUTO_SCRIPT],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        stdin=subprocess.DEVNULL,
                        start_new_session=True,
                    )
                except Exception as e:
                    return self._json(500, {"error": str(e)})
            else:
                return self._json(400, {"error": "op must be start|stop"})
            return self._json(200, self._status())

        return self._json(404, {"error": "not found"})


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    os.makedirs(THUMB_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(PORT_FILE, "w") as f:
        f.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
