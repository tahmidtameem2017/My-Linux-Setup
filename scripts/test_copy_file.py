#!/usr/bin/env python3
"""Tests for scripts/copy-file.sh — the clipboard backend behind the
launcher's Ctrl+C on file rows.

The contract is the clipboard itself, so every case round-trips through
the real wl-copy/wl-paste pair: the offered MIME type and the pasted
bytes are both asserted (text and image contents land as their bytes;
directories and unknown types fall back to the path string).

Skipped wholesale when wl-clipboard is absent (headless machines).

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
SCRIPT = str(SCRIPTS / "copy-file.sh")

WL_COPY = shutil.which("wl-copy")
WL_PASTE = shutil.which("wl-paste")


def paste_types():
    out = subprocess.run([WL_PASTE, "--list-types"],
                         capture_output=True, text=True)
    return out.stdout.split()


def paste_bytes(mime):
    # -n: wl-paste appends a newline on output unless told not to;
    # the clipboard itself holds the exact bytes copy-file.sh sent.
    return subprocess.run([WL_PASTE, "-n", "--type", mime],
                          capture_output=True).stdout


@unittest.skipUnless(WL_COPY and WL_PASTE, "wl-clipboard not installed")
class TestTextContents(unittest.TestCase):
    """Text files copy their CONTENTS as text/plain."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def copy(self, name, data):
        p = self.dir / name
        p.write_bytes(data)
        subprocess.run([SCRIPT, str(p)], check=True)
        time.sleep(0.2)  # clipboard ownership takes a moment
        return p

    def test_text_extensions_copy_contents(self):
        for name in ("notes.txt", "README.md", "main.py",
                     "main.c", "main.cpp", "script.sh"):
            with self.subTest(name=name):
                payload = f"contents of {name}".encode()
                self.copy(name, payload)
                self.assertIn("text/plain", paste_types())
                self.assertEqual(paste_bytes("text/plain"), payload)

    def test_directory_copies_path(self):
        self.copy  # silence linters about the helper
        subprocess.run([SCRIPT, str(self.dir)], check=True)
        time.sleep(0.2)
        self.assertIn("text/plain", paste_types())
        self.assertEqual(paste_bytes("text/plain"),
                         str(self.dir).encode())

    def test_unknown_extension_copies_path(self):
        p = self.copy("slide.pdf", b"%PDF-1.4 fake")
        self.assertIn("text/plain", paste_types())
        self.assertEqual(paste_bytes("text/plain"), str(p).encode())


@unittest.skipUnless(WL_COPY and WL_PASTE, "wl-clipboard not installed")
class TestImageContents(unittest.TestCase):
    """Images copy their bytes with the matching image/* MIME."""

    # Minimal valid PNG (1x1 red) and JPEG (tiny, from PIL-free bytes):
    # the MIME assertion is what matters; bytes must round-trip exactly.
    PNG = bytes.fromhex(
        "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
        "1f15c4890000000d49444154789c626001000000ffff030000060005"
        "57bfabd40000000049454e44ae426082")
    JPG = bytes.fromhex(
        "ffd8ffe000104a46494600010100000100010000ffdb004300080606"
        "070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e"
        "1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d"
        "3832323332ffc0000b080001000101011100ffc4001f0000010501"
        "01010101010000000000000000000102030405060708090a0bffc4"
        "00b5100002010303020403050504040000017d0102030004110512"
        "2131410613516107227114328191a1082342b1c11552d1f0243362"
        "7282090a161718191a25262728292a3435363738393a4344454647"
        "48494a535455565758595a636465666768696a737475767778797a"
        "838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2"
        "b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9da"
        "e1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc4001f0100"
        "030101010101010101010000000000000102030405060708090a0b"
        "ffc400b51100020102040403040705040400010277000102031104"
        "052131061241510761711322328108144291a1b1c109233352f015"
        "6272d10a162434e125f11718191a262728292a35363738393a4344"
        "45464748494a535455565758595a636465666768696a7374757677"
        "78797a838485868788898a92939495969798999aa2a3a4a5a6a7a8"
        "a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8"
        "d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda0008010100"
        "003f00d2cf20ffd9")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def test_png_copies_image_bytes(self):
        p = self.dir / "dot.png"
        p.write_bytes(self.PNG)
        subprocess.run([SCRIPT, str(p)], check=True)
        time.sleep(0.2)
        self.assertEqual(paste_types(), ["image/png"])
        self.assertEqual(paste_bytes("image/png"), self.PNG)

    def test_jpg_copies_image_bytes(self):
        p = self.dir / "dot.jpg"
        p.write_bytes(self.JPG)
        subprocess.run([SCRIPT, str(p)], check=True)
        time.sleep(0.2)
        self.assertEqual(paste_types(), ["image/jpeg"])
        self.assertEqual(paste_bytes("image/jpeg"), self.JPG)

    def test_uppercase_extension_maps_mime(self):
        p = self.dir / "dot.JPG"
        p.write_bytes(self.JPG)
        subprocess.run([SCRIPT, str(p)], check=True)
        time.sleep(0.2)
        self.assertEqual(paste_types(), ["image/jpeg"])


class TestCli(unittest.TestCase):
    """Exit codes are pinned even without a clipboard."""

    def test_missing_arg_exits_2(self):
        p = subprocess.run([SCRIPT], capture_output=True)
        self.assertEqual(p.returncode, 2)

    def test_nonexistent_path_still_exits_0(self):
        # An unresolvable path must not break the launcher: the
        # script degrades silently (wl-copy fails, `|| true`).
        p = subprocess.run([SCRIPT, "/nonexistent/nope.txt"],
                           capture_output=True)
        self.assertEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
