#!/usr/bin/env python3
"""Timer backend: pomodoro + countdown that survive the popup closing.

The browser window is only a remote control — all timing lives here, so
phases chain and beeps fire even with the popup closed.

  GET  /              -> calendar.html (served same-origin, no CORS issues)
  GET  /api/state     -> {"pomo": {...}, "timer": {...}}
  POST /api/pomo      -> {"cmd": start|pause|reset|skip, "cfg": {focus,short,long,rounds}?}
  POST /api/timer     -> {"cmd": start|pause|reset, "seconds"?: int}

Binds 127.0.0.4 (distinct Brave app-id) on an ephemeral port, published to
$NIRI_CLOCK_DIR/port (default ~/.cache/niri-clock/port).
State persists to state.json so timers survive server restarts too.
Phase/timer expiry plays a generated tone via pw-play/paplay/aplay.
"""

import json
import math
import os
import struct
import subprocess
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
HTML_FILE = os.path.normpath(os.path.join(BASE_DIR, "..", "calendar", "calendar.html"))
STATE_DIR = os.environ.get(
    "NIRI_CLOCK_DIR", os.path.join(os.path.expanduser("~"), ".cache", "niri-clock")
)
PORT_FILE = os.path.join(STATE_DIR, "port")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
BEEP_FILE = os.path.join(STATE_DIR, "beep.wav")

DEFAULT_CFG = {"focus": 25, "short": 5, "long": 15, "rounds": 4}
# 1s is plenty: catch_up() advances by wall-clock elapsed, so expiry
# accuracy never depends on this tick (and it halves wakeups/disk writes).
TICK = 1.0
_lock = threading.Lock()


def default_state():
    return {
        "pomo": {"phase": "focus", "round": 1, "remain": DEFAULT_CFG["focus"] * 60.0,
                 "running": False, "last": time.time()},
        "timer": {"remain": 5 * 60.0, "running": False, "last": time.time(),
                  "minutes": 5, "seconds": 0, "finished": False},
        "cfg": dict(DEFAULT_CFG),
    }


state = default_state()


def save_state():
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({"pomo": state["pomo"], "timer": state["timer"], "cfg": state["cfg"]}, f)
    except OSError:
        pass


def load_state():
    try:
        with open(STATE_FILE) as f:
            saved = json.load(f)
        for key in ("pomo", "timer", "cfg"):
            if isinstance(saved.get(key), dict):
                state[key].update(saved[key])
        # Catch up on time that passed while the server was away.
        catch_up(time.time())
    except (OSError, ValueError):
        pass


def ensure_beep():
    """The timer sound: a chiptune rendition of the 'Never Gonna Give You
    Up' chorus (note table after the classic piezo-buzzer transcription).
    Generated locally, no downloads."""
    if os.path.isfile(BEEP_FILE):
        return BEEP_FILE
    # (freq Hz, None = rest, beat units @100ms). Full chorus, with lyrics
    # for orientation: Never gonna give you up / let you down / run
    # around and desert you / make you cry / say goodbye / tell a lie
    # and hurt you.
    Bb4, Ab4, F5, Eb5, Db5, C5, Ab5 = 466.16, 415.30, 698.46, 622.25, 554.37, 523.25, 830.61
    R = None
    melody = [
        Bb4, Bb4, Ab4, Ab4, F5, F5, Eb5,
        Bb4, Bb4, Ab4, Ab4, Eb5, Eb5, Db5,
        C5, Bb4, Db5, Db5, Db5, Db5, Db5,
        Eb5, C5, Bb4, Ab4, Ab4, Ab4, Eb5,
        Db5, Bb4, Bb4, Ab4, Ab4, F5, F5,
        Eb5, Bb4, Bb4, Ab4, Ab4, Ab5, C5,
        Db5, C5, Bb4, Db5, Db5, Db5, Db5,
        Db5, Eb5, C5, Bb4, Ab4, R, Ab4,
        Eb5, Db5, R,
    ]
    rhythm = [
        1, 1, 1, 1, 3, 3, 6,
        1, 1, 1, 1, 3, 3, 3,
        1, 2, 1, 1, 1, 1, 3, 3, 3,
        1, 2, 2, 2, 4, 8,
        1, 1, 1, 1, 3, 3, 6,
        1, 1, 1, 1, 3, 3, 3,
        1, 2, 1, 1, 1, 1, 3, 3, 3,
        1, 2, 2, 2, 4, 8, 4,
    ]
    assert len(melody) == len(rhythm) == 59, "melody/rhythm length mismatch"
    try:
        rate, beat = 44100, 0.10
        pcm = bytearray()
        for freq, units in zip(melody, rhythm):
            dur = beat * units
            n = int(rate * dur)
            if freq is None:
                pcm += b"\x00\x00" * n
                continue
            for t in range(n):
                # Soft envelope: quick attack, gentle decay (no clicks).
                env = min(1.0, t / (rate * 0.01)) * (0.55 + 0.45 * (1 - t / n))
                # Sine + a breath of 2nd harmonic for chiptune warmth.
                v = math.sin(2 * math.pi * freq * t / rate)
                v += 0.25 * math.sin(4 * math.pi * freq * t / rate)
                pcm += struct.pack("<h", int(11000 * env * v / 1.25))
            gap = int(rate * beat * 0.2)  # separation between notes
            pcm += b"\x00\x00" * gap
        with wave.open(BEEP_FILE, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(bytes(pcm))
        return BEEP_FILE
    except OSError:
        return None


def play_beep():
    path = ensure_beep()
    if not path:
        return
    for player in (["pw-play", path], ["paplay", path], ["aplay", "-q", path]):
        try:
            subprocess.Popen(player, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                             start_new_session=True)
            return
        except OSError:
            continue


def pomo_dur(phase):
    cfg = state["cfg"]
    if phase == "focus":
        return max(1, int(cfg.get("focus", 25))) * 60.0
    if phase == "short":
        return max(1, int(cfg.get("short", 5))) * 60.0
    return max(1, int(cfg.get("long", 15))) * 60.0


def pomo_rounds():
    return min(12, max(1, int(state["cfg"].get("rounds", 4))))


def pomo_advance():
    """Move to the next phase. Returns True if a phase just finished."""
    p = state["pomo"]
    if p["phase"] == "focus":
        p["phase"] = "long" if p["round"] >= pomo_rounds() else "short"
    else:
        if p["phase"] == "short":
            p["round"] += 1
        else:
            p["round"] = 1
        p["phase"] = "focus"
    p["remain"] = pomo_dur(p["phase"])


def catch_up(now):
    """Advance running timers by elapsed wall-clock time (beeps included)."""
    p, t = state["pomo"], state["timer"]
    if p["running"]:
        p["remain"] -= now - p["last"]
        while p["remain"] <= 0:
            play_beep()
            overflow = -p["remain"]
            pomo_advance()
            p["remain"] -= overflow
    p["last"] = now
    if t["running"]:
        t["remain"] -= now - t["last"]
        if t["remain"] <= 0:
            t["remain"] = 0
            t["running"] = False
            t["finished"] = True
            play_beep()
    t["last"] = now


def ticker():
    while True:
        time.sleep(TICK)
        with _lock:
            catch_up(time.time())
            save_state()


def snapshot():
    with _lock:
        catch_up(time.time())
        return {
            "pomo": dict(state["pomo"]),
            "timer": dict(state["timer"]),
            "cfg": dict(state["cfg"]),
        }


class Handler(BaseHTTPRequestHandler):
    server_version = "NiriClock/1.0"

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
                self._json(500, {"error": "calendar.html not found"})
        elif self.path == "/api/state":
            self._json(200, snapshot())
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "invalid JSON"})

        if self.path == "/api/pomo":
            cmd = payload.get("cmd", "")
            if cmd not in ("start", "pause", "reset", "skip"):
                return self._json(400, {"error": "bad cmd"})
            with _lock:
                catch_up(time.time())
                p = state["pomo"]
                cfg = payload.get("cfg")
                if isinstance(cfg, dict):
                    for k in ("focus", "short", "long", "rounds"):
                        try:
                            v = int(cfg[k])
                            if k == "rounds":
                                state["cfg"][k] = min(12, max(1, v))
                            elif k == "focus":
                                state["cfg"][k] = min(180, max(1, v))
                            else:
                                state["cfg"][k] = min(60, max(1, v))
                        except (KeyError, TypeError, ValueError):
                            pass
                if cmd == "start":
                    if p["remain"] <= 0:
                        p["remain"] = pomo_dur(p["phase"])
                    p["running"] = True
                elif cmd == "pause":
                    p["running"] = False
                elif cmd == "reset":
                    p.update(phase="focus", round=1, remain=pomo_dur("focus"), running=False)
                elif cmd == "skip":
                    pomo_advance()
                p["last"] = time.time()
                save_state()
            return self._json(200, snapshot())

        if self.path == "/api/timer":
            cmd = payload.get("cmd", "")
            if cmd not in ("start", "pause", "reset"):
                return self._json(400, {"error": "bad cmd"})
            with _lock:
                catch_up(time.time())
                t = state["timer"]
                if cmd == "start":
                    if "seconds" in payload:
                        # Explicit fresh start from the given inputs.
                        try:
                            secs = max(0, int(payload.get("seconds", 0)))
                        except (TypeError, ValueError):
                            secs = 0
                        if secs <= 0:
                            return self._json(400, {"error": "seconds required"})
                        t["remain"] = float(min(359999, secs))
                        t["minutes"], t["seconds"] = t["remain"] // 60, t["remain"] % 60
                    elif t["remain"] > 0:
                        pass  # resume paused countdown
                    else:
                        return self._json(400, {"error": "seconds required"})
                    t["running"] = True
                    t["finished"] = False
                elif cmd == "pause":
                    t["running"] = False
                elif cmd == "reset":
                    try:
                        secs = max(0, int(payload.get("seconds", t["remain"])))
                    except (TypeError, ValueError):
                        secs = 0
                    t["remain"] = float(min(359999, secs))
                    t["minutes"], t["seconds"] = t["remain"] // 60, t["remain"] % 60
                    t["running"] = False
                    t["finished"] = False
                t["last"] = time.time()
                save_state()
            return self._json(200, snapshot())

        return self._json(404, {"error": "not found"})


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    load_state()
    ensure_beep()
    threading.Thread(target=ticker, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.4", 0), Handler)
    with open(PORT_FILE, "w") as f:
        f.write(str(server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
