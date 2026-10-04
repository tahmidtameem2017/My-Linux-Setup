#!/usr/bin/env python3
"""Tests for scripts/sushi-preview.sh — the Sushi frontend behind the
launcher's hybrid preview (Ctrl+Space on files the native pane cannot draw).

The load-bearing bits pinned here are the ones a refactor would silently
break: the interface name really is org.gnome.NautilusPreviewer2 even though
the bus name has no "2", the file URI is percent-encoded (spaces and '#' in
filenames are routine), and a missing sushi must exit 3 instead of pretending
the preview opened.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
SCRIPT = str(SCRIPTS / "sushi-preview.sh")

# Logs every argv (empty args survive as "ARG|") and fakes NameHasOwner from a
# file, so no test ever touches the real session bus.
FAKE_GDBUS = """#!/bin/sh
for a in "$@"; do printf 'ARG|%s\\n' "$a"; done >> "$GDBUS_LOG"
case "$*" in
    *NameHasOwner*) cat "$GDBUS_OWNER" 2>/dev/null || printf '(false,)\\n' ;;
    *) printf '()\\n' ;;
esac
exit 0
"""

FAKE_SUSHI = "#!/bin/sh\nexit 0\n"


class SushiPreviewTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sushi-test-")
        self.addCleanup(self.tmp.cleanup)
        self.bindir = Path(self.tmp.name) / "bin"
        self.bindir.mkdir()
        self.log = Path(self.tmp.name) / "gdbus.log"
        self.owner = Path(self.tmp.name) / "owner"
        self._fake("gdbus", FAKE_GDBUS)
        self._fake("sushi", FAKE_SUSHI)

    def _fake(self, name, body):
        p = self.bindir / name
        p.write_text(body)
        p.chmod(p.stat().st_mode | stat.S_IEXEC)

    def run_script(self, *args, path=None):
        env = os.environ.copy()
        env["PATH"] = str(self.bindir) + ":" + os.environ["PATH"] if path is None else path
        env["GDBUS_LOG"] = str(self.log)
        env["GDBUS_OWNER"] = str(self.owner)
        return subprocess.run([SCRIPT, *args], capture_output=True, text=True, env=env)

    def logged_args(self):
        if not self.log.exists():
            return []
        return [ln[len("ARG|"):] for ln in self.log.read_text().splitlines() if ln.startswith("ARG|")]

    # ---- show -----------------------------------------------------------

    def test_show_encodes_uri_and_calls_previewer2(self):
        target = Path(self.tmp.name) / "a b#c.txt"
        target.write_text("x")
        r = self.run_script("show", str(target))
        self.assertEqual(r.returncode, 0, r.stderr)
        args = self.logged_args()
        self.assertIn("org.gnome.NautilusPreviewer2.ShowFile", args)
        self.assertIn("org.gnome.NautilusPreviewer", args)  # bus name, no "2"
        uri = next(a for a in args if a.startswith("file://"))
        self.assertTrue(uri.endswith("a%20b%23c.txt"), uri)
        # Empty handle + activation token must be passed explicitly, then
        # closeIfAlreadyShown=false, so a switch never closes the window.
        self.assertEqual(args[-4:], [uri, "", "false", ""])

    def test_show_missing_file_is_a_hard_failure(self):
        r = self.run_script("show", str(Path(self.tmp.name) / "nope.pdf"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no such file", r.stderr)
        self.assertEqual(self.logged_args(), [])

    def test_show_without_sushi_exits_3(self):
        bare = Path(self.tmp.name) / "bare"
        bare.mkdir()
        for tool in ("bash", "python3", "gdbus"):
            src = subprocess.run(["sh", "-c", f"command -v {tool}"],
                                 capture_output=True, text=True).stdout.strip()
            os.symlink(src, bare / tool)
        r = self.run_script("show", __file__, path=str(bare))
        self.assertEqual(r.returncode, 3)
        self.assertIn("sushi is not installed", r.stderr)

    # ---- close / status -------------------------------------------------

    def test_close_calls_close_method(self):
        r = self.run_script("close")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("org.gnome.NautilusPreviewer2.Close", self.logged_args())

    def test_status_reads_name_owner(self):
        self.owner.write_text("(true,)\n")
        r = self.run_script("status")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.strip(), "active")

    def test_status_inactive_exits_1(self):
        self.owner.write_text("(false,)\n")
        r = self.run_script("status")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.strip(), "inactive")

    def test_usage_errors(self):
        for args in ([], ["bogus"], ["show"], ["close", "extra"]):
            with self.subTest(args=args):
                r = self.run_script(*args)
                self.assertEqual(r.returncode, 1)
                self.assertIn("usage:", r.stderr)


if __name__ == "__main__":
    unittest.main()
