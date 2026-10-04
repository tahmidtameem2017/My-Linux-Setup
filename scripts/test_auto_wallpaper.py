"""Tests for scripts/auto-wallpaper.sh's PID-file handling.

The daemon is started detached and tracked only by a PID file, so the one
interesting question is whether that file is believed. It should not be, unless
the process it names is genuinely this script.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
SCRIPT = SCRIPTS / "auto-wallpaper.sh"
REPO = SCRIPTS.parent


class PidFileTests(unittest.TestCase):
    def run_script(self, home, *args):
        env = dict(os.environ)
        env["NIRI_SETUP_HOME"] = str(home)
        # An empty WALL_DIR keeps get_wallpapers() from walking a real library.
        env["WALL_DIR"] = str(Path(home) / "empty-wallpapers")
        return subprocess.run([str(SCRIPT), *args], capture_output=True,
                              text=True, env=env, timeout=30)

    def fresh_home(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name)
        (home / ".state").mkdir()
        (home / "empty-wallpapers").mkdir()
        # The script sources INTERVAL from scripts/wallpaper-process.sh relative
        # to NIRI_SETUP_HOME, which does not exist in the temp home. Stub it.
        scripts = home / "scripts"
        scripts.mkdir()
        stub = scripts / "wallpaper-process.sh"
        stub.write_text("#!/bin/sh\nexit 1\n")
        stub.chmod(0o755)
        return home

    def test_status_reports_not_running_without_a_pid_file(self):
        home = self.fresh_home()
        result = self.run_script(home, "--status")
        self.assertIn("Daemon not running", result.stdout)

    def test_recycled_pid_is_not_mistaken_for_the_daemon(self):
        """A PID the kernel handed to something else must not count as ours.

        This is not hypothetical: a stale PID file named 993 while 993 had
        become at-spi-bus-launcher's child gdbus, so `kill -0 993` succeeded and
        the script reported a running daemon that did not exist. Worse, --stop
        would have killed an unrelated process.
        """
        home = self.fresh_home()
        pid_file = home / ".state" / "auto-wallpaper.pid"
        # PID 1 always exists and never runs this script.
        pid_file.write_text("1\n")

        result = self.run_script(home, "--status")
        self.assertIn("Daemon not running", result.stdout)
        self.assertFalse(pid_file.exists(),
                         "a PID file naming a foreign process must be cleared")

    def test_stop_does_not_kill_a_foreign_process(self):
        """The real hazard: --stop must not signal a recycled PID."""
        home = self.fresh_home()
        pid_file = home / ".state" / "auto-wallpaper.pid"
        pid_file.write_text("1\n")

        result = self.run_script(home, "--stop")
        # Exit 0 is right (stopping nothing is success, like `systemctl stop` on
        # an inactive unit). What matters is that it said so and sent no signal:
        # PID 1 surviving is the observable proof, plus the cleared PID file.
        self.assertEqual(result.returncode, 0)
        self.assertIn("No running daemon found", result.stdout)
        self.assertNotIn("Stopped daemon", result.stdout)
        self.assertFalse(pid_file.exists())
        self.assertTrue(Path("/proc/1").exists(), "PID 1 must still be alive")

    def test_garbage_pid_file_is_cleared(self):
        home = self.fresh_home()
        (home / ".state" / "auto-wallpaper.pid").write_text("not-a-pid\n")
        result = self.run_script(home, "--status")
        self.assertIn("Daemon not running", result.stdout)
        self.assertFalse((home / ".state" / "auto-wallpaper.pid").exists())

    def test_script_parses(self):
        result = subprocess.run(["bash", "-n", str(SCRIPT)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_pid_is_daemon_matches_this_script(self):
        """Sanity check on the helper itself, in isolation."""
        source = SCRIPT.read_text()
        self.assertIn("SCRIPT_NAME=\"auto-wallpaper.sh\"", source)
        self.assertIn("[[ \"$cmdline\" == *\"$SCRIPT_NAME\"* ]]", source)
        # The old check that made this bug possible must be gone.
        self.assertNotIn('if kill -0 "$pid" 2>/dev/null; then', source)
        self.assertEqual(SCRIPT.stat().st_mode & 0o111, 0o111,
                         "auto-wallpaper.sh must stay executable")


if __name__ == "__main__":
    unittest.main()