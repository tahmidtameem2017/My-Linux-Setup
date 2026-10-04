"""Tests for scripts/custom-theme-server.py.

The server is the only thing that can write theme-custom.json, and that file is
read by the bar, the launcher, tmux, alacritty, niri and the focus ring. So the
two things worth testing hard are: it refuses everything it should refuse, and
it writes in a way quickshell's file watch survives.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

SCRIPTS = Path(__file__).parent
SERVER = SCRIPTS / "custom-theme-server.py"
REPO = SCRIPTS.parent

SPEC = importlib.util.spec_from_file_location("custom_theme_server", SERVER)
server_mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server_mod)

colorlib_spec = importlib.util.spec_from_file_location("colorlib", SCRIPTS / "colorlib.py")
colorlib = importlib.util.module_from_spec(colorlib_spec)
colorlib_spec.loader.exec_module(colorlib)

GOOD = {key: value for key, value in zip(
    ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover",
     "text", "muted", "dim", "danger"],
    ["#101418", "#1B2126", "#252C33", "#2B333B", "#4A555F", "#7FB3D5",
     "#A9D1EC", "#E8EDF2", "#9AA7B4", "#78838F", "#E06C75"])}


class ValidationTests(unittest.TestCase):
    def test_accepts_exactly_eleven_hex_keys(self):
        out = server_mod.valid_palette(GOOD)
        self.assertIsNotNone(out)
        self.assertEqual(set(out), set(colorlib.KEYS))

    def test_normalises_case(self):
        self.assertEqual(server_mod.valid_palette(
            {k: v.lower() for k, v in GOOD.items()})["accent"], "#7FB3D5")

    def test_rejects_missing_extra_and_malformed(self):
        missing = dict(GOOD)
        del missing["dim"]
        extra = {**GOOD, "shadow": "#000000"}
        short = {**GOOD, "bg": "#fff"}
        no_hash = {**GOOD, "bg": "101418"}
        eight = {**GOOD, "bg": "#10141820"}
        not_a_string = {**GOOD, "bg": 0x101418}
        for name, palette in [("missing key", missing), ("extra key", extra),
                              ("3-digit hex", short), ("no hash", no_hash),
                              ("8-digit hex", eight), ("not a string", not_a_string)]:
            with self.subTest(case=name):
                self.assertIsNone(server_mod.valid_palette(palette))

    def test_rejects_non_dicts(self):
        for value in (None, [], "{}", 5):
            with self.subTest(value=value):
                self.assertIsNone(server_mod.valid_palette(value))

    def test_the_shell_normalises_whatever_the_editor_saves(self):
        """The editor does not rewrite what you type; Theme.qml does.

        That is deliberate — an editor that silently altered your colours would
        be lying to you. What must be true is that the *result* is still legible,
        because Theme.qml runs the same floor table over whatever loads. So a
        palette saved straight from the editor is expected to fail the floors
        as-is, and is expected to pass once normalised.
        """
        def failing(palette, token, minimum, against):
            return colorlib.contrast(colorlib.rgb(palette[token]),
                                     colorlib.rgb(palette[against])) \
                < minimum - colorlib.FLOOR_EPS

        fixed = colorlib.enforce_floors(GOOD)
        for token, rules in colorlib.FLOORS.items():
            for minimum, against in rules:
                self.assertFalse(
                    failing(fixed, token, minimum, against),
                    "%s on %s is still %.2f after normalisation"
                    % (token, against,
                       colorlib.contrast(colorlib.rgb(fixed[token]),
                                         colorlib.rgb(fixed[against]))))
        # ...and the safety net is actually needed, i.e. the raw sample does
        # break a floor. Otherwise this test would pass vacuously.
        self.assertTrue(any(failing(GOOD, token, minimum, against)
                            for token, rules in colorlib.FLOORS.items()
                            for minimum, against in rules))


class WriteTests(unittest.TestCase):
    def test_write_in_place_preserves_the_inode(self):
        """The whole reason write_in_place exists.

        quickshell watches this path with QFileSystemWatcher, which binds to the
        inode. The usual write-tmp-then-mv would look atomic and correct and
        would silently kill the watch, so the editor would save and nothing
        would change.
        """
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "theme-custom.json"
            path.write_text("{}")
            first = path.stat().st_ino
            time.sleep(0.01)
            server_mod.write_in_place(path, json.dumps(GOOD))
            self.assertEqual(path.stat().st_ino, first)
            self.assertEqual(json.loads(path.read_text()), GOOD)
            server_mod.write_in_place(path, json.dumps({**GOOD, "bg": "#000000"}))
            self.assertEqual(path.stat().st_ino, first)

    def test_write_truncates_rather_than_leaving_a_tail(self):
        """A shorter palette must not leave the old longer bytes behind."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "theme-custom.json"
            server_mod.write_in_place(path, json.dumps(GOOD))
            server_mod.write_in_place(path, json.dumps({**GOOD, "bg": "#000"}))
            self.assertEqual(json.loads(path.read_text())["bg"], "#000")

    def test_creates_the_file_and_its_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "nested" / "deeper" / "theme-custom.json"
            server_mod.write_in_place(path, "{}")
            self.assertTrue(path.exists())


class HttpTests(unittest.TestCase):
    """Exercise the real routes over a real socket."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.theme_dir = Path(self.tmp.name)
        (self.theme_dir / "help").mkdir()
        (self.theme_dir / "help" / "custom-theme.html").write_text("<!doctype html>ok")
        self.token = "test-token-1234"
        self.port = 4188
        self.proc = subprocess.Popen(
            [sys.executable, str(SERVER), "--host", "127.0.0.1",
             "--port", str(self.port), "--token", self.token,
             "--setup-home", str(self.theme_dir)],
            env={**os.environ, "NIRI_SETUP_THEME_DIR": str(self.theme_dir)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.proc.wait)
        self.addCleanup(self.proc.kill)
        for pipe in (self.proc.stdout, self.proc.stderr):
            self.addCleanup(pipe.close)
        for _ in range(100):
            try:
                self.get("/api/health")   # self.get builds the base URL itself
                break
            except Exception:
                time.sleep(0.05)
        else:
            self.fail("server never came up")

    def get(self, path):
        with urllib.request.urlopen("http://127.0.0.1:%d%s" % (self.port, path),
                                    timeout=10) as response:
            return response.status, json.loads(response.read())

    def post(self, path, body, token=None):
        request = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (self.port, path),
            data=json.dumps(body).encode(), method="POST",
            headers={"Content-Type": "application/json", **(
                {"X-Theme-Token": token} if token else {})})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_serves_the_page(self):
        with urllib.request.urlopen(
                "http://127.0.0.1:%d/" % self.port, timeout=10) as response:
            self.assertEqual(response.status, 200)
            self.assertIn("text/html", response.headers["Content-Type"])
            self.assertIn(b"ok", response.read())

    def test_post_without_token_is_forbidden(self):
        """The reason the token exists: any page in the browser reaches loopback."""
        status, body = self.post("/api/theme", {"palette": GOOD, "apply": False})
        self.assertEqual(status, 403)
        self.assertFalse((self.theme_dir / "theme-custom.json").exists())

    def test_post_with_wrong_token_is_forbidden(self):
        status, _ = self.post("/api/theme", {"palette": GOOD}, token="nope")
        self.assertEqual(status, 403)

    def test_post_with_token_writes_the_file(self):
        status, body = self.post("/api/theme", {"palette": GOOD, "apply": False},
                                 token=self.token)
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertFalse(body["applied"], "apply=False must not try to switch")
        written = json.loads((self.theme_dir / "theme-custom.json").read_text())
        self.assertEqual(written, GOOD)

    def test_post_rejects_an_invalid_palette(self):
        for bad in ({}, {"palette": {}}, {"palette": {"bg": "#fff"}}):
            with self.subTest(body=bad):
                status, body = self.post("/api/theme", bad, token=self.token)
                self.assertEqual(status, 400)
                self.assertIn("11 keys", body["error"])
        self.assertFalse((self.theme_dir / "theme-custom.json").exists())

    def test_api_theme_reports_defaults_when_no_file_exists(self):
        status, body = self.get("/api/theme")
        self.assertEqual(status, 200)
        self.assertFalse(body["exists"])
        self.assertEqual(body["custom"], server_mod.DEFAULT_PALETTE)

    def test_api_palettes_lists_files_and_skips_junk(self):
        (self.theme_dir / "theme-wallpaper.json").write_text(json.dumps(GOOD))
        (self.theme_dir / "theme-broken.json").write_text('{"bg": "#fff"}')
        (self.theme_dir / "theme-custom.json").write_text(json.dumps(GOOD))
        _, body = self.get("/api/palettes")
        self.assertIn("wallpaper", body["variants"])
        self.assertNotIn("broken", body["variants"])
        # The Custom file must not be offered as a "start from" source; that is
        # what the editor is editing.
        self.assertNotIn("custom", body["variants"])

    def test_unknown_route_is_404(self):
        try:
            self.get("/api/nope")
            self.fail("expected 404")
        except urllib.error.HTTPError as error:
            self.assertEqual(error.code, 404)

    def test_refuses_a_non_loopback_host(self):
        """Pointing this at a routable address would void the token's purpose."""
        done = subprocess.run(
            [sys.executable, str(SERVER), "--host", "0.0.0.0", "--token", "x"],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("loopback-only", done.stderr)


if __name__ == "__main__":
    unittest.main()