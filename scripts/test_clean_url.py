#!/usr/bin/env python3
"""Tests for scripts/clean-url.py — the sanitizer behind URL-based downloads.

The contract is one canonical line on stdout, so every case here is a paste a
user could realistically produce (a Brave address bar, a chat message, a share
sheet) and the exact string yt-dlp must be handed.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("clean_url", SCRIPTS / "clean-url.py")
clean_url = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(clean_url)

SCRIPT = str(SCRIPTS / "clean-url.py")
WATCH = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"


class TestYouTubeCanonical(unittest.TestCase):
    """Every YouTube shape collapses to the same watch URL."""

    def test_watch_with_every_tracking_param(self):
        self.assertEqual(
            clean_url.clean(
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s&list=PLabc"
                "&index=2&si=AbC-123&feature=share"),
            WATCH)

    def test_short_link(self):
        self.assertEqual(clean_url.clean("https://youtu.be/dQw4w9WgXcQ?t=43&si=x"), WATCH)

    def test_path_shapes(self):
        for path in ("shorts", "embed", "live", "v", "e"):
            with self.subTest(path=path):
                self.assertEqual(
                    clean_url.clean(f"https://www.youtube.com/{path}/dQw4w9WgXcQ?si=x"),
                    WATCH)

    def test_mobile_music_nocookie_hosts(self):
        for host in ("m.youtube.com", "music.youtube.com", "gaming.youtube.com",
                     "www.youtube-nocookie.com"):
            with self.subTest(host=host):
                self.assertEqual(
                    clean_url.clean(f"https://{host}/watch?v=dQw4w9WgXcQ&t=1"), WATCH)

    def test_uppercase_host_and_id_preserved(self):
        # The id is case-sensitive; only the host is folded.
        self.assertEqual(clean_url.clean("HTTPS://WWW.YouTube.COM/watch?v=dQw4w9WgXcQ"),
                         WATCH)

    def test_attribution_link_wrapper(self):
        self.assertEqual(
            clean_url.clean(
                "https://www.youtube.com/attribution_link?u=%2Fwatch%3Fv%3DdQw4w9WgXcQ%26t%3D3s"),
            WATCH)

    def test_userinfo_and_port_are_dropped(self):
        self.assertEqual(
            clean_url.clean("https://user:pw@www.youtube.com:443/watch?v=dQw4w9WgXcQ"),
            WATCH)

    def test_missing_scheme_is_tolerated(self):
        self.assertEqual(clean_url.clean("youtu.be/dQw4w9WgXcQ"), WATCH)
        self.assertEqual(clean_url.clean("youtube.com/watch?v=dQw4w9WgXcQ"), WATCH)

    def test_rejects_ids_that_are_not_ids(self):
        # 11 chars of base64 is the shape. A playlist ref or a truncated paste
        # must NOT be handed to yt-dlp as a video: it would "succeed" and
        # silently fetch something else.
        for bad in ("https://www.youtube.com/watch?v=short",
                    "https://www.youtube.com/watch?list=PLabc",
                    "https://www.youtube.com/feed/trending"):
            with self.subTest(bad=bad):
                with self.assertRaises(clean_url.Bad):
                    clean_url.clean(bad)


class TestExtract(unittest.TestCase):
    """A paste is text, not necessarily a URL."""

    def test_url_inside_sentence(self):
        self.assertEqual(
            clean_url.clean("omg listen to this https://youtu.be/dQw4w9WgXcQ?t=1 so good"),
            WATCH)

    def test_wrapped_in_brackets(self):
        self.assertEqual(clean_url.clean("(https://youtu.be/dQw4w9WgXcQ)"), WATCH)

    def test_quote_terminates_the_run(self):
        self.assertEqual(clean_url.clean('"https://youtu.be/dQw4w9WgXcQ" nice'), WATCH)

    def test_first_url_wins(self):
        self.assertEqual(
            clean_url.clean("https://youtu.be/aaaaaaaaaaa then https://youtu.be/bbbbbbbbbbb"),
            "https://www.youtube.com/watch?v=aaaaaaaaaaa")


class TestOtherHosts(unittest.TestCase):
    """Non-YouTube: drop the fingerprint, keep the meaning."""

    def test_tracking_stripped_keeps_media_param(self):
        self.assertEqual(
            clean_url.clean("https://cdn.example.com/v/clip.mp4?id=42&si=abc&fbclid=xyz"),
            "https://cdn.example.com/v/clip.mp4?id=42")

    def test_utm_prefix_stripped(self):
        self.assertEqual(
            clean_url.clean("https://example.com/watch/9?utm_source=x&v=abc"),
            "https://example.com/watch/9?v=abc")

    def test_empty_path_becomes_root(self):
        self.assertEqual(clean_url.clean("https://example.com"), "https://example.com/")

    def test_fragment_dropped(self):
        self.assertEqual(clean_url.clean("https://example.com/a#t=10"), "https://example.com/a")


class TestRejects(unittest.TestCase):

    def test_empty(self):
        with self.assertRaises(clean_url.Bad):
            clean_url.clean("   ")

    def test_non_web_schemes(self):
        for raw in ("file:///home/me/Music/x.mp3", "magnet:?xt=urn:btih:abc",
                    "spotify:track:abc", "ftp://example.com/x.mp3"):
            with self.subTest(raw=raw):
                with self.assertRaises(clean_url.Bad):
                    clean_url.clean(raw)

    def test_hostless(self):
        with self.assertRaises(clean_url.Bad):
            clean_url.clean("https:///watch")


class TestCli(unittest.TestCase):
    """The shell script consumes this contract, so pin the exit codes."""

    def run_cli(self, *args):
        return subprocess.run([sys.executable, SCRIPT, *args],
                              capture_output=True, text=True)

    def test_prints_one_line(self):
        p = self.run_cli("https://youtu.be/dQw4w9WgXcQ?t=9")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, WATCH + "\n")

    def test_bad_link_exits_1_with_reason_on_stderr(self):
        p = self.run_cli("not a url at all")
        self.assertEqual(p.returncode, 1)
        self.assertEqual(p.stdout, "")
        self.assertIn("unusable link", p.stderr)

    def test_missing_arg_exits_2(self):
        p = self.run_cli()
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()