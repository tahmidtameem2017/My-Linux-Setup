#!/usr/bin/env python3
"""Tests for scripts/perf-stats.sh — the sampler behind the bar's
performance pill (quickshell services/PerfService.qml parses its
one-line key=value output).

The contract is the line itself: every key present, every value an
integer in range, memUsed <= memTotal, battery -1 (absent) or 0-100.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import subprocess
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
SCRIPT = str(SCRIPTS / "perf-stats.sh")
KEYS = ("cpu", "gpu", "gpuBusy", "memUsed", "memTotal",
        "batPct", "batCharging")


class TestPerfStats(unittest.TestCase):
    """One line, every key, integers in range."""

    def parse(self):
        out = subprocess.run([SCRIPT], capture_output=True, text=True,
                             timeout=15)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.count("\n"), 1)
        fields = out.stdout.strip().split()
        stats = {}
        for kv in fields:
            key, _, val = kv.partition("=")
            self.assertIsNot(val, "", f"missing value for {key}")
            stats[key] = int(val)
        return stats

    def test_every_key_present(self):
        for key in KEYS:
            with self.subTest(key=key):
                self.assertIn(key, self.parse())

    def test_ranges(self):
        s = self.parse()
        self.assertGreaterEqual(s["cpu"], 0)
        self.assertLessEqual(s["cpu"], 100)
        self.assertGreaterEqual(s["gpu"], 0)
        self.assertGreaterEqual(s["gpuBusy"], -1)
        self.assertLessEqual(s["gpuBusy"], 100)
        self.assertGreaterEqual(s["memTotal"], 0)
        self.assertGreaterEqual(s["memUsed"], 0)
        self.assertLessEqual(s["memUsed"], s["memTotal"])
        self.assertGreaterEqual(s["batPct"], -1)
        self.assertLessEqual(s["batPct"], 100)
        self.assertIn(s["batCharging"], (0, 1))

    def test_stays_fast(self):
        # ~0.5s is the deliberate CPU sample window; a 5s budget
        # catches an accidental blocking read (nvidia-smi/upower
        # must never hang the sampler).
        t0 = time.monotonic()
        self.parse()
        self.assertLess(time.monotonic() - t0, 5.0)


if __name__ == "__main__":
    unittest.main()
