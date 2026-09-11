#!/usr/bin/env python3
"""Quick-settings backend for the themed HTML popup (stdlib only).

  GET  /                  -> settings.html
  GET  /api/status        -> {wifi, bluetooth, power, brightness, volume, dnd, idle}
  POST /api/wifi          -> {op: on|off} | {op: connect, ssid, password?}
  POST /api/bluetooth     -> {op: on|off|connect|disconnect, address?}
  POST /api/power         -> {profile: performance|balanced|power-saver}
  POST /api/brightness    -> {value: 5-100}
  POST /api/volume        -> {value: 0-100} (capped at 100)
  POST /api/mute          -> {muted: bool} (absent = toggle)
  POST /api/dnd           -> {op: on|off|toggle} via dunstctl
  POST /api/idle          -> {mode: 5 minutes|10 minutes|20 minutes|30 minutes|infinity}

Binds 127.0.0.3 (distinct Brave app-id) on an ephemeral port, published to
$NIRI_SETTINGS_DIR/port (default ~/.cache/niri-settings/port).
"""

import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(BASE_DIR))
HTML_FILE = os.path.join(BASE_DIR, "settings.html")
STATE_DIR = os.environ.get(
    "NIRI_SETTINGS_DIR", os.path.join(os.path.expanduser("~"), ".cache", "niri-settings")
)
PORT_FILE = os.path.join(STATE_DIR, "port")
SWAYIDLE_SH = os.path.join(REPO_ROOT, "scripts", "swayidle.sh")
IDLE_FILE = os.path.join(os.path.expanduser("~"), ".local", "state", "idle-time")
IDLE_MODES = ["5 minutes", "10 minutes", "20 minutes", "30 minutes", "infinity"]


def run(*args, timeout=15):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        # Strip newlines only: power_status() detects profiles by leading
        # whitespace, so a blanket .strip() would eat the first line's
        # indent and hide it. Callers needing more stripping do it themselves.
        return proc.returncode, (proc.stdout or "").strip("\n")
    except Exception as e:
        return 1, str(e)


# ---------- wifi (nmcli) ----------

def wifi_status():
    _, state = run("nmcli", "-t", "-f", "WIFI", "g", timeout=5)
    enabled = state.strip() == "enabled"
    active = ""
    _, conns = run("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active", timeout=5)
    for line in conns.splitlines():
        name, _, typ = line.partition(":")
        if typ == "802-11-wireless":
            active = name
            break
    networks = []
    if enabled:
        _, out = run("nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi", timeout=20)
        seen = set()
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) < 4:
                continue
            is_active, ssid = parts[0], parts[1]
            if not ssid or ssid in seen:
                continue
            seen.add(ssid)
            try:
                signal = int(parts[2])
            except ValueError:
                signal = 0
            networks.append({
                "ssid": ssid,
                "signal": signal,
                "security": parts[3] not in ("", "--"),
                "active": is_active == "yes" or ssid == active,
            })
        networks.sort(key=lambda n: (not n["active"], -n["signal"]))
    return {"enabled": enabled, "ssid": active, "networks": networks[:12]}


# ---------- bluetooth (bluetoothctl) ----------

def bt_status():
    _, show = run("bluetoothctl", "show", timeout=5)
    powered = bool(re.search(r"^\s*Powered:\s*yes", show, re.M))
    devices = []
    _, out = run("bluetoothctl", "devices", timeout=5)
    for line in out.splitlines():
        m = re.match(r"Device\s+(\S+)\s+(.*)", line)
        if not m:
            continue
        addr, name = m.group(1), m.group(2)
        _, info = run("bluetoothctl", "info", addr, timeout=5)
        connected = bool(re.search(r"^\s*Connected:\s*yes", info, re.M))
        devices.append({"name": name, "address": addr, "connected": connected})
    return {"powered": powered, "devices": devices[:12]}


# ---------- power profiles ----------

def power_status():
    _, out = run("powerprofilesctl", "list", timeout=5)
    profiles = []
    for line in out.splitlines():
        # Top-level only: "* name:" or "  name:". Property lines are
        # indented 4+ spaces (CpuDriver, PlatformDriver, ...) — skip those.
        m = re.match(r"^(?:\*| ) ([\w-]+):", line)
        if m:
            profiles.append(m.group(1))
    if not profiles:
        profiles = ["performance", "balanced", "power-saver"]
    _, active = run("powerprofilesctl", "get", timeout=5)
    active = (active or "").strip()
    if active not in profiles:
        active = profiles[0]
    return {"active": active, "profiles": profiles}


# ---------- brightness ----------

def brightness_status():
    _, cur = run("brightnessctl", "get", timeout=5)
    _, mx = run("brightnessctl", "max", timeout=5)
    try:
        pct = round(int(cur) / int(mx) * 100)
    except (ValueError, ZeroDivisionError):
        pct = 0
    return {"value": max(0, min(100, pct))}


# ---------- volume (wpctl, capped at 100%) ----------

def volume_status():
    code, out = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@", timeout=5)
    m = re.search(r"Volume:\s*([\d.]+)", out or "")
    try:
        volume = round(float(m.group(1)) * 100) if m else 0
    except ValueError:
        volume = 0
    muted = "[MUTED]" in (out or "")
    return {"value": max(0, min(100, volume)), "muted": muted}


# ---------- do-not-disturb (dunst) ----------

def dnd_status():
    _, out = run("dunstctl", "is-paused", timeout=5)
    return {"paused": (out or "").strip() == "true"}


# ---------- idle timeout (swayidle) ----------

def idle_status():
    try:
        with open(IDLE_FILE) as f:
            current = f.read().strip()
    except OSError:
        current = "10 minutes"
    if current not in IDLE_MODES:
        current = "10 minutes"
    return {"current": current, "modes": list(IDLE_MODES)}


def idle_set(mode):
    os.makedirs(os.path.dirname(IDLE_FILE), exist_ok=True)
    with open(IDLE_FILE, "w") as f:
        f.write(mode)
    run("pkill", "swayidle", timeout=5)
    try:
        subprocess.Popen(
            ["bash", SWAYIDLE_SH],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def full_status():
    return {
        "wifi": wifi_status(),
        "bluetooth": bt_status(),
        "power": power_status(),
        "brightness": brightness_status(),
        "volume": volume_status(),
        "dnd": dnd_status(),
        "idle": idle_status(),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "NiriSettings/1.0"

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
                self._json(500, {"error": "settings.html not found"})
        elif self.path == "/api/status":
            self._json(200, full_status())
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "invalid JSON"})

        if self.path == "/api/wifi":
            op = payload.get("op", "")
            if op == "on":
                run("nmcli", "radio", "wifi", "on")
            elif op == "off":
                run("nmcli", "radio", "wifi", "off")
            elif op == "connect":
                ssid = payload.get("ssid", "")
                if not ssid:
                    return self._json(400, {"error": "ssid required"})
                cmd = ["nmcli", "dev", "wifi", "connect", ssid]
                if payload.get("password"):
                    cmd += ["password", payload["password"]]
                code, out = run(*cmd, timeout=30)
                status = full_status()
                status["ok"] = code == 0
                status["message"] = out.splitlines()[-1] if out else ""
                return self._json(200, status)
            else:
                return self._json(400, {"error": "unknown op"})
            return self._json(200, full_status())

        if self.path == "/api/bluetooth":
            op = payload.get("op", "")
            if op == "on":
                run("bluetoothctl", "power", "on")
            elif op == "off":
                run("bluetoothctl", "power", "off")
            elif op in ("connect", "disconnect"):
                addr = payload.get("address", "")
                if not re.fullmatch(r"[0-9A-Fa-f:]{17}", addr or ""):
                    return self._json(400, {"error": "bad address"})
                run("bluetoothctl", op, addr, timeout=25)
            else:
                return self._json(400, {"error": "unknown op"})
            return self._json(200, full_status())

        if self.path == "/api/power":
            profile = payload.get("profile", "")
            if profile not in ("performance", "balanced", "power-saver"):
                return self._json(400, {"error": "bad profile"})
            run("powerprofilesctl", "set", profile)
            return self._json(200, full_status())

        if self.path == "/api/brightness":
            try:
                value = max(5, min(100, int(payload.get("value", 0))))
            except (TypeError, ValueError):
                return self._json(400, {"error": "value must be 5-100"})
            run("brightnessctl", "set", f"{value}%")
            return self._json(200, full_status())

        if self.path == "/api/volume":
            try:
                value = max(0, min(100, int(payload.get("value", 0))))
            except (TypeError, ValueError):
                return self._json(400, {"error": "value must be 0-100"})
            run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value}%")
            return self._json(200, full_status())

        if self.path == "/api/mute":
            if "muted" in payload:
                arg = "1" if payload["muted"] else "0"
            else:
                arg = "toggle"
            run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", arg)
            return self._json(200, full_status())

        if self.path == "/api/dnd":
            op = payload.get("op", "")
            if op == "on":
                run("dunstctl", "set-paused", "true")
            elif op == "off":
                run("dunstctl", "set-paused", "false")
            elif op == "toggle":
                run("dunstctl", "set-paused", "toggle")
            else:
                return self._json(400, {"error": "op must be on|off|toggle"})
            return self._json(200, full_status())

        if self.path == "/api/idle":
            mode = payload.get("mode", "")
            if mode not in IDLE_MODES:
                return self._json(400, {"error": "bad mode"})
            try:
                idle_set(mode)
            except OSError as e:
                return self._json(500, {"error": str(e)})
            return self._json(200, full_status())

        return self._json(404, {"error": "not found"})


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.3", 0), Handler)
    with open(PORT_FILE, "w") as f:
        f.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
