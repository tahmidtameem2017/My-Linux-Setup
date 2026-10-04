#!/usr/bin/env python3
"""Loopback server for the all-in-one niri config editor (help/config-editor.html).

Why a server at all: the page has to WRITE ~/.config/niri/*.kdl, and a
file:// page cannot. Brave will not grant a file:// origin write access
and there is no portable way to ask, so the page is served over
http://127.0.0.8 and this is the only thing listening.

Design notes that are load-bearing, not decoration:

* **The LIVE config, not the repo.** ~/.config/niri/*.kdl are copies
  with drift (gaps, animations and input all differ from the repo right
  now), and the compositor runs the live copies. An editor that edited
  the repo would show values nothing is using, and applying would
  clobber the user's live tweaks with stale repo ones. So this reads
  and writes ~/.config/niri only; the repo stays the install baseline.

* **Surgical edits, never rewrite.** Each setting is one regex (or one
  block insertion) inside its file. Everything else -- comments, the
  theme-synced focus-ring colours, unrelated window rules -- must
  survive an apply byte-for-byte. scripts/sync-external-theme.py owns
  the colours in layout.kdl; this server must not touch them.

* **Validate before the compositor ever sees it.** After writing, the
  server runs `niri validate`. If that fails it restores every original
  file from memory and reports the error -- a bad slider drag must not
  leave a broken config behind. Only then does it hot-reload.

* **Token in the URL + a required header on POST.** Loopback is
  reachable from every page in the browser; without the header any
  site could reconfigure the compositor. No CORS headers on purpose.

* **Missing blocks are inserted, not failed.** The live animations.kdl
  is `animations {}` and the live input.kdl has no `mouse` block, so
  "set window-open to 250ms" creates the block with the repo's default
  curve rather than reporting a missing anchor.

Usage (normally via scripts/config-editor.sh):
    config-editor-server.py --host 127.0.0.8 --port 4098 --token <hex>
"""

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PAGE = "config-editor.html"
TOKEN_HEADER = "X-Config-Token"
MAX_BODY = 64 * 1024

# Defaults match the repo's niri/*.kdl; used when a block is absent
# (the live config disables animations and has no mouse block).
DEFAULTS = {
    "gaps": 6,
    "centerFocusedColumn": "on-overflow",
    "defaultColumnWidth": 0.5,
    "focusRingWidth": 3,
    "opacity": 1.0,
    "cornerRadius": 0,
    "tapToClick": False,
    "naturalScroll": False,
    "mouseAccel": 0.3,
    "windowOpen": 250,
    "windowClose": 180,
}
CENTER_OPTIONS = ("never", "on-overflow", "always")
OPEN_CURVE = '"cubic-bezier" 0.22 1 0.36 1'
CLOSE_CURVE = '"ease-out-quad"'


# ---- KDL surgery helpers ------------------------------------------------
# The files here are one property per line, so line-oriented edits are
# safe: a block spans from its `name {` line to the line where the
# brace depth returns to zero.

def block_span(lines, name):
    """Line span (inclusive) of `name { ... }`, counting braces."""
    opener = re.compile(r"^\s*%s\s*\{" % re.escape(name))
    for i, line in enumerate(lines):
        if not opener.match(line):
            continue
        depth = 0
        for j in range(i, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth == 0:
                return (i, j)
        return (i, len(lines) - 1)
    return None


def sub_once(text, pattern, repl, flags=re.M):
    new, n = re.subn(pattern, repl, text, count=1, flags=flags)
    return new, n == 1


def set_in_block(text, block_name, prop_pattern, fmt):
    """Set one property inside `block_name`: replace the first line
    matching prop_pattern, or insert fmt(indent) after the opener."""
    lines = text.splitlines(keepends=True)
    span = block_span(lines, block_name)
    if span is None:
        return text, False
    a, b = span
    block = "".join(lines[a:b + 1])
    new_block, ok = sub_once(
        block, prop_pattern,
        lambda m: fmt(re.match(r"\s*", m.group(0)).group(0)))
    if not ok:
        blines = block.splitlines(keepends=True)
        base = re.match(r"\s*", blines[0]).group(0)
        blines.insert(1, fmt(base + "    ") + "\n")
        new_block = "".join(blines)
    lines[a:b + 1] = [new_block]
    return "".join(lines), True


def insert_block(text, parent, block_name, body_lines):
    """Insert `block_name { ... }` before the closing brace of parent."""
    lines = text.splitlines(keepends=True)
    span = block_span(lines, parent)
    if span is None:
        return text, False
    a, b = span
    # A single-line parent (`animations {}`) must first become
    # multi-line, or the children would land outside its brace --
    # and niri silently accepts unknown top-level nodes, so the
    # validate pass would not catch that.
    if a == b:
        opener = lines[a]
        if not re.match(r"^\s*\S+\s*\{\s*\}\s*$", opener):
            return text, False
        indent = re.match(r"\s*", opener).group(0)
        name = re.match(r"\s*(\S+)\s*\{", opener).group(1)
        lines[a:b + 1] = [indent + name + " {\n", indent + "}\n"]
        b = a + 1
    child = re.match(r"\s*", lines[a]).group(0) + "    "
    prop = child + "    "
    chunk = [child + block_name + " {\n"]
    chunk += [prop + line + "\n" for line in body_lines]
    chunk += [child + "}\n"]
    lines[b:b] = chunk
    return "".join(lines), True


def set_flag(text, block_name, flag, on):
    """Add or remove a bare `flag;`-style line inside a block."""
    lines = text.splitlines(keepends=True)
    span = block_span(lines, block_name)
    if span is None:
        return text, False
    a, b = span
    block = "".join(lines[a:b + 1])
    flag_re = re.compile(r"^[ \t]*%s[ \t]*\n?" % re.escape(flag), re.M)
    if on:
        if flag_re.search(block):
            return text, True
        blines = block.splitlines(keepends=True)
        base = re.match(r"\s*", blines[0]).group(0)
        blines.insert(1, base + "    " + flag + "\n")
        lines[a:b + 1] = ["".join(blines)]
        return "".join(lines), True
    lines[a:b + 1] = [flag_re.sub("", block)]
    return "".join(lines), True


def fmt_float(value):
    # KDL distinguishes `opacity 1` (integer, rejected) from
    # `opacity 1.0` (float), so keep at least one decimal.
    text = ("%.2f" % value).rstrip("0")
    return text + "0" if text.endswith(".") else text


# ---- readers ------------------------------------------------------------

def read_state(config_dir):
    def text(name):
        try:
            return (config_dir / name).read_text()
        except OSError:
            return ""

    layout = text("layout.kdl")
    rules = text("rules.kdl")
    inp = text("input.kdl")
    anim = text("animations.kdl")

    def first(source, pattern, flags=0):
        m = re.search(pattern, source, flags)
        return m.group(1) if m else None

    def in_block(source, name, pattern):
        lines = source.splitlines()
        span = block_span(lines, name)
        if span is None:
            return None
        m = re.search(pattern, "\n".join(lines[span[0]:span[1] + 1]), re.M)
        return m.group(1) if m else None

    state = {}
    for key, pattern, cast in (
        ("gaps", r"^\s*gaps\s+(\d+)", int),
        ("focusRingWidth", None, None),  # handled below (inside a block)
    ):
        if pattern is None:
            continue
        m = first(layout, pattern, re.M)
        state[key] = cast(m) if m else DEFAULTS[key]

    m = first(layout, r'^\s*center-focused-column\s+"([^"]*)"', re.M)
    state["centerFocusedColumn"] = m or DEFAULTS["centerFocusedColumn"]
    m = first(layout, r"default-column-width\s*\{\s*proportion\s+([\d.]+)")
    state["defaultColumnWidth"] = float(m) if m else DEFAULTS["defaultColumnWidth"]

    ring = in_block(layout, "focus-ring", r"^\s*width\s+(\d+)")
    state["focusRingWidth"] = int(ring) if ring else DEFAULTS["focusRingWidth"]

    m = first(rules, r"^\s*opacity\s+([\d.]+)", re.M)
    state["opacity"] = float(m) if m else DEFAULTS["opacity"]
    m = first(rules, r"^\s*geometry-corner-radius\s+(\d+)", re.M)
    state["cornerRadius"] = int(m) if m else DEFAULTS["cornerRadius"]

    lines = inp.splitlines()
    span = block_span(lines, "touchpad")
    tp_text = ""
    if span:
        tp_text = "\n".join(lines[span[0]:span[1] + 1])
    state["tapToClick"] = bool(re.search(r"^\s*tap\s*$", tp_text, re.M))
    state["naturalScroll"] = bool(re.search(r"^\s*natural-scroll\s*$", tp_text, re.M))

    mouse = in_block(inp, "mouse", r"accel-speed\s+(-?[\d.]+)")
    state["mouseAccel"] = float(mouse) if mouse is not None else DEFAULTS["mouseAccel"]
    notes = {"mouseBlock": mouse is not None}

    wo = in_block(anim, "window-open", r"duration-ms\s+(\d+)")
    wc = in_block(anim, "window-close", r"duration-ms\s+(\d+)")
    state["windowOpen"] = int(wo) if wo else DEFAULTS["windowOpen"]
    state["windowClose"] = int(wc) if wc else DEFAULTS["windowClose"]
    # Enabled = the animations block holds anything but comments.
    anim_lines = anim.splitlines()
    anim_span = block_span(anim_lines, "animations")
    notes["animationsEnabled"] = bool(anim_span) and any(
        line.strip() and not line.strip().startswith("//")
        for line in anim_lines[anim_span[0] + 1:anim_span[1]])

    return state, notes


def niri_running():
    # niri exports its socket path in NIRI_SOCKET (newer builds use
    # per-session names like niri.wayland-1.888.sock); older builds
    # used a fixed path under XDG_RUNTIME_DIR.
    candidates = [os.environ.get("NIRI_SOCKET"), str(Path(os.environ.get(
        "XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())) / "niri" / "ipc.sock")]
    return any(c and Path(c).exists() for c in candidates)


# ---- writers ------------------------------------------------------------
# Each returns (new_text, missing_keys). A missing key means the
# anchor could not be found and could not be inserted; the apply
# still proceeds and the editor reports what it could not set.

def edit_layout(text, v):
    missing = []
    text, ok = sub_once(
        text, r"^([ \t]*)gaps[ \t]+[\d.]+[ \t]*$",
        lambda m: "%sgaps %d" % (m.group(1), v["gaps"]))
    if not ok:
        missing.append("gaps")
    text, ok = sub_once(
        text, r'^([ \t]*)center-focused-column[ \t]+"[^"]*"',
        lambda m: '%scenter-focused-column "%s"' % (m.group(1), v["centerFocusedColumn"]))
    if not ok:
        missing.append("centerFocusedColumn")
    text, ok = sub_once(
        text, r"(default-column-width[ \t]*\{[ \t]*proportion[ \t]+)[\d.]+",
        lambda m: "%s%s" % (m.group(1), fmt_float(v["defaultColumnWidth"])))
    if not ok:
        missing.append("defaultColumnWidth")
    text, ok = set_in_block(
        text, "focus-ring", r"^([ \t]*)width[ \t]+\d+[ \t]*$",
        lambda i: "%swidth %d" % (i, v["focusRingWidth"]))
    if not ok:
        missing.append("focusRingWidth")
    return text, missing


def edit_rules(text, v):
    missing = []
    text, ok = sub_once(
        text, r"^([ \t]*)opacity[ \t]+[\d.]+[ \t]*$",
        lambda m: "%sopacity %s" % (m.group(1), fmt_float(v["opacity"])))
    if not ok:
        missing.append("opacity")
    text, ok = sub_once(
        text, r"^([ \t]*)geometry-corner-radius[ \t]+\d+[ \t]*$",
        lambda m: "%sgeometry-corner-radius %d" % (m.group(1), v["cornerRadius"]))
    if not ok:
        missing.append("cornerRadius")
    return text, missing


def edit_input(text, v):
    missing = []
    text, ok = set_flag(text, "touchpad", "tap", v["tapToClick"])
    if not ok:
        missing.append("tapToClick")
    text, ok = set_flag(text, "touchpad", "natural-scroll", v["naturalScroll"])
    if not ok:
        missing.append("naturalScroll")
    has_mouse = block_span(text.splitlines(), "mouse") is not None
    if has_mouse and v["naturalScroll"]:
        text, _ = set_flag(text, "mouse", "natural-scroll", True)
    if has_mouse:
        text, ok = set_in_block(
            text, "mouse", r"^([ \t]*)accel-speed[ \t]+-?[\d.]+[ \t]*$",
            lambda i: "%saccel-speed %s" % (i, fmt_float(v["mouseAccel"])))
    else:
        text, ok = insert_block(
            text, "input", "mouse",
            ["accel-speed %s" % fmt_float(v["mouseAccel"])])
    if not ok:
        missing.append("mouseAccel")
    return text, missing


def edit_animations(text, v):
    missing = []
    for key, block, curve in (
        ("windowOpen", "window-open", OPEN_CURVE),
        ("windowClose", "window-close", CLOSE_CURVE),
    ):
        if block_span(text.splitlines(), block):
            text, ok = set_in_block(
                text, block, r"^([ \t]*)duration-ms[ \t]+\d+[ \t]*$",
                lambda i, n=v[key]: "%sduration-ms %d" % (i, n))
        else:
            text, ok = insert_block(
                text, "animations", block,
                ["duration-ms %d" % v[key], "curve %s" % curve])
        if not ok:
            missing.append(key)
    return text, missing


EDITORS = (
    ("layout.kdl", edit_layout),
    ("rules.kdl", edit_rules),
    ("input.kdl", edit_input),
    ("animations.kdl", edit_animations),
)


def normalise(payload):
    """Validate + clamp the posted values. Raises ValueError naming
    the offending field, so the page can show exactly what was wrong."""
    v = {}

    def num(key, lo, hi, cast):
        raw = payload.get(key, DEFAULTS[key])
        try:
            n = cast(raw)
        except (TypeError, ValueError):
            raise ValueError("%s is not a number" % key)
        if not lo <= n <= hi:
            raise ValueError("%s must be between %s and %s" % (key, lo, hi))
        v[key] = n

    num("gaps", 0, 200, int)
    center = payload.get("centerFocusedColumn", DEFAULTS["centerFocusedColumn"])
    if center not in CENTER_OPTIONS:
        raise ValueError("centerFocusedColumn must be one of: %s"
                         % ", ".join(CENTER_OPTIONS))
    v["centerFocusedColumn"] = center
    num("defaultColumnWidth", 0.1, 1.0, float)
    num("focusRingWidth", 0, 20, int)
    num("opacity", 0.3, 1.0, float)
    num("cornerRadius", 0, 40, int)
    for key in ("tapToClick", "naturalScroll"):
        val = payload.get(key, DEFAULTS[key])
        if not isinstance(val, bool):
            raise ValueError("%s must be true or false" % key)
        v[key] = val
    num("mouseAccel", -1.0, 1.0, float)
    num("windowOpen", 0, 2000, int)
    num("windowClose", 0, 2000, int)
    return v


def apply_values(values, config_dir):
    originals = {}
    plans = {}
    for name, fn in EDITORS:
        path = config_dir / name
        try:
            originals[name] = path.read_text()
        except OSError as error:
            return {"ok": False, "error": "cannot read %s: %s" % (name, error)}
        plans[name] = fn(originals[name], values)

    changed = []
    missing = []
    for name, (new_text, miss) in plans.items():
        missing += miss
        if new_text == originals[name]:
            continue
        try:
            (config_dir / name).write_text(new_text)
        except OSError as error:
            _restore(originals, config_dir)
            return {"ok": False, "error": "cannot write %s: %s" % (name, error)}
        changed.append(name)

    # Validate before the compositor can act on it. A failed check
    # must leave the config exactly as it was.
    try:
        check = subprocess.run(["niri", "validate"], capture_output=True,
                               text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as error:
        _restore(originals, config_dir)
        return {"ok": False, "error": "cannot run niri validate: %s" % error}
    if check.returncode != 0:
        _restore(originals, config_dir)
        return {"ok": False,
                "error": "niri rejected the config: %s"
                         % (check.stderr.strip() or check.stdout.strip())}

    reloaded = False
    if changed:
        try:
            reload_cmd = subprocess.run(
                ["niri", "msg", "action", "load-config-file"],
                capture_output=True, text=True, timeout=30)
            reloaded = reload_cmd.returncode == 0
        except (OSError, subprocess.SubprocessError):
            reloaded = False

    return {"ok": True, "changed": changed, "missing": missing,
            "reloaded": reloaded, "niriRunning": niri_running()}


def _restore(originals, config_dir):
    for name, text in originals.items():
        try:
            (config_dir / name).write_text(text)
        except OSError:
            pass


# ---- HTTP ---------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "config-editor/1.0"

    # Injected by main().
    token = ""
    config_dir = Path.home() / ".config" / "niri"
    page_path = Path.home() / "niri-setup" / "help" / PAGE

    def _send(self, code, body=b"", ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        # No CORS headers on purpose: a page on any other origin must
        # not be able to read or POST to this server.
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code, payload):
        self._send(code, json.dumps(payload, indent=2) + "\n")

    def _authorised(self):
        return secrets.compare_digest(self.headers.get(TOKEN_HEADER, ""), self.token)

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        path = self.path.split("?", 1)[0]
        if path == "/":
            try:
                html = self.page_path.read_bytes()
            except OSError:
                return self._json(500, {"error": "missing %s" % self.page_path})
            return self._send(200, html, "text/html; charset=utf-8")
        if path == "/api/config":
            values, notes = read_state(self.config_dir)
            return self._json(200, {
                "values": values,
                "notes": notes,
                "niriRunning": niri_running(),
                "configDir": str(self.config_dir),
            })
        if path == "/api/health":
            return self._json(200, {"ok": True})
        return self._json(404, {"error": "no such route"})

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_POST(self):  # noqa: N802
        if not self._authorised():
            return self._json(403, {"error": "bad or missing %s" % TOKEN_HEADER})
        path = self.path.split("?", 1)[0]
        if path != "/api/apply":
            return self._json(404, {"error": "no such route"})
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
        if not isinstance(payload, dict) or not isinstance(payload.get("values"), dict):
            return self._json(400, {"error": "expected {values: {...}}"})
        try:
            values = normalise(payload["values"])
        except ValueError as error:
            return self._json(400, {"error": str(error)})
        return self._json(200, apply_values(values, self.config_dir))

    def log_message(self, fmt, *args):
        # Keep the launcher's captured output quiet but keep real errors.
        sys.stderr.write("[config-editor] " + fmt % args + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=4098)
    parser.add_argument("--host", default="127.0.0.8",
                        help="loopback address; do not point this off 127.0.0.0/8")
    parser.add_argument("--token", default=None,
                        help="shared secret required on POST; generated if omitted")
    parser.add_argument("--setup-home", default=os.environ.get(
        "NIRI_SETUP_HOME", os.path.expanduser("~/niri-setup")))
    parser.add_argument("--config-dir", default=os.path.expanduser(
        "~/.config/niri"),
                        help="the LIVE niri config directory this editor edits")
    args = parser.parse_args(argv)

    # Loopback only, for the same reason as the custom theme server:
    # the token guarantee is meaningless if the network can reach us.
    if not re.match(r"^127\.\d+\.\d+\.\d+$", args.host):
        parser.error("this server is loopback-only by design")

    Handler.token = args.token or secrets.token_urlsafe(24)
    Handler.config_dir = Path(args.config_dir).expanduser()
    Handler.page_path = Path(args.setup_home).expanduser() / "help" / PAGE

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
