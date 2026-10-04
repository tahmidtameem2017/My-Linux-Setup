"""dictation-reset.sh must never signal a process that is not the daemon.

This script sends SIGTERM and ultimately SIGKILL, so a false positive does not
produce a cosmetic bug: it kills an innocent process. That is not hypothetical
in this repo — `auto-wallpaper.sh` shipped with a stale PID file naming 993,
which the kernel had handed to `at-spi-bus-launcher`'s child, so its `--stop`
killed an accessibility service. The fix there was to match
`/proc/<pid>/cmdline` against its own name; the fix here is stricter still.

The specific bug this pins: matching the WHOLE cmdline with a `*whisrsd*`
substring also matches a process merely *mentioning* the daemon. Verified with a
decoy invoked as `some-other-service --whisrsd-flag`, which the substring
version collected and would have SIGKILLed. Matching is therefore on the
basename of argv[0], which cannot match a mention.

Also pinned: the escalation ladder must degrade in order rather than skipping
straight to the strongest signal, because rungs 1-2 keep the model resident
while rungs 3-4 throw the daemon away.
"""

import os
import re
import signal
import subprocess
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "dictation-reset.sh"


def read_script() -> str:
    return SCRIPT.read_text()


def code_only() -> str:
    """Script text with `#` comments stripped.

    Necessary, not fussy: the file explains at length why `pkill` is wrong, so a
    naive search matches the warning about the mistake instead of the mistake,
    and the assertion would pass on code that really does blind-pkill.
    """
    out = []
    for line in read_script().splitlines():
        stripped = line.split("#", 1)[0]
        if stripped.strip():
            out.append(stripped)
    return "\n".join(out)


def extract_function(name: str) -> str:
    """Pull a bash function body out of the script so it can be sourced alone."""
    text = read_script()
    m = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}", text, re.S | re.M)
    if not m:
        raise AssertionError(f"function {name}() not found in {SCRIPT}")
    return m.group(0)


def daemon_pids() -> list[str]:
    """Source the script's real daemon_pids() and run it."""
    out = subprocess.run(
        ["bash", "-c", extract_function("daemon_pids") + "\ndaemon_pids"],
        capture_output=True, text=True, timeout=60,
    )
    return [ln.strip() for ln in out.stdout.split("\n") if ln.strip()]


class TestDaemonMatching(unittest.TestCase):
    def setUp(self):
        self.decoys = []

    def tearDown(self):
        for p in self.decoys:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass

    def spawn_decoy(self, argv0: str) -> subprocess.Popen:
        p = subprocess.Popen(
            ["bash", "-c", f'exec -a "{argv0}" sleep 120'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.decoys.append(p)
        return p

    def test_finds_the_real_daemon(self):
        """If whisrsd is running, it must be found — otherwise the reset is a no-op."""
        real = subprocess.run(["pgrep", "-x", "whisrsd"], capture_output=True, text=True)
        if not real.stdout.strip():
            self.skipTest("whisrsd not running")
        self.assertIn(real.stdout.split()[0], daemon_pids())

    def test_ignores_a_process_that_merely_mentions_whisrsd(self):
        """The regression: argv mentioning the daemon must NOT match."""
        decoy = self.spawn_decoy("some-other-service --whisrsd-flag")
        time.sleep(0.4)
        self.assertNotIn(str(decoy.pid), daemon_pids(),
                         "a process merely mentioning whisrsd was matched for killing")

    def test_ignores_a_decoy_that_looks_like_the_daemon_path(self):
        decoy = self.spawn_decoy("/usr/local/bin/whisrsd-helper --serve")
        time.sleep(0.4)
        self.assertNotIn(str(decoy.pid), daemon_pids())

    def test_ignores_ordinary_processes(self):
        decoy = self.spawn_decoy("/usr/bin/sleep")
        time.sleep(0.4)
        self.assertNotIn(str(decoy.pid), daemon_pids())


class TestEscalationLadder(unittest.TestCase):
    def setUp(self):
        self.text = code_only()

    def test_ladder_is_ordered_weakest_to_strongest(self):
        """Rungs must appear in escalating order, so the polite path runs first."""
        order = [
            '"$WHISRS" cancel',
            "systemctl --user restart",
            "kill -TERM",
            "kill -KILL",
        ]
        positions = []
        for needle in order:
            self.assertIn(needle, self.text, f"missing rung: {needle}")
            positions.append(self.text.index(needle))
        self.assertEqual(positions, sorted(positions),
                         "escalation rungs are out of order — a strong signal "
                         "would fire before the polite ones")

    def test_kill_rungs_are_never_blind_pkill(self):
        """`pkill whisrsd` / a pid read from a file are both the old bug."""
        self.assertNotRegex(self.text, r"\bpkill\b")
        # Every kill target must trace back to daemon_pids. The indirection
        # through a local is fine (and is what the code does), so this checks
        # the assignment rather than demanding the call be inline.
        for m in re.finditer(r"kill -(?:TERM|KILL|INT)\s+\$(\w+)", self.text):
            var = m.group(1)
            self.assertRegex(
                self.text, rf'\b{var}="\$\(daemon_pids',
                f"kill target ${var} is not sourced from daemon_pids: {m.group(0)!r}",
            )

    def test_reports_microphone_state_at_the_end(self):
        """The question the user has is 'is the mic free', so it must be answered."""
        self.assertIn("mic_holders", self.text)
        self.assertRegex(self.text, r"microphone now:")

    def test_never_touches_the_shell_or_niri_config(self):
        """A panic key must be safe to mash; it may not restart quickshell."""
        for forbidden in ("pkill quickshell", "load-config-file", "niri msg action"):
            self.assertNotIn(forbidden, self.text)

    def test_has_a_read_only_status_mode(self):
        self.assertIn("do_status()", self.text)
        self.assertRegex(self.text, r"status\)\s*do_status")


if __name__ == "__main__":
    unittest.main()