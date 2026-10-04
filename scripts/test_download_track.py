#!/usr/bin/env python3
"""Tests for the download path: download-track.sh + run-yt-dlp.py.

Every case here is a download that has actually gone wrong on this machine:

  * an omitted link reached the script as the literal text "undefined" (the
    IpcHandler coerces a missing argument to the declared type), so an EMPTY
    link box — which means "download what is playing" — was rejected as
    "unusable link: undefined" instead of searching;
  * an empty field meant "search" only inside QML, so the rule did not hold
    for a keybind, a script, or `qs ipc call`;
  * a wedged yt-dlp outlived the script and ran for hours (one measured at
    2h07m) with ~/Music still open, because tearing a QProcess child down
    gives bash no chance to run its TERM trap;
  * a failed download said nothing but "✕", so a bot-check, an unavailable
    video and a DNS stall were indistinguishable.

No test touches the network: yt-dlp and playerctl are replaced by stubs, so
what is asserted is the CONTRACT (what gets handed to yt-dlp, what is
reported, what is left running) rather than YouTube's mood today.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
DOWNLOAD = str(SCRIPTS / "download-track.sh")
GUARD = str(SCRIPTS / "run-yt-dlp.py")


class DownloadTest(unittest.TestCase):
    """Shared scratch dir + stub bin/ so a test never runs the real tools."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="dl-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.music = self.tmp / "Music"
        self.videos = self.tmp / "Videos"
        self.music.mkdir()
        self.videos.mkdir()
        self.bin = self.tmp / "bin"
        self.bin.mkdir()

    # ---- helpers -------------------------------------------------------

    def stub(self, name: str, body: str) -> Path:
        """A fake `name` on a private PATH. Overwrites any previous stub."""
        p = self.bin / name
        p.write_text("#!/usr/bin/env bash\n" + body + "\n")
        p.chmod(0o755)
        return p

    def env(self, extra=None):
        e = dict(os.environ)
        e["PATH"] = f"{self.bin}:{os.environ['PATH']}"
        e["XDG_MUSIC_DIR"] = str(self.music)
        e["XDG_VIDEOS_DIR"] = str(self.videos)
        # Never post a real desktop notification from a test — unless the test
        # installed its own recording stub, which must not be clobbered here.
        if not (self.bin / "notify-send").exists():
            self.stub("notify-send", "exit 0\n")
        if extra:
            e.update(extra)
        return e

    def download(self, args, env=None, timeout=60):
        return subprocess.run([DOWNLOAD] + list(args), capture_output=True,
                              text=True, env=self.env(env), timeout=timeout)

    @staticmethod
    def failure(stdout: str) -> str:
        """The reason download-track.sh reported, or "" if it reported none."""
        for line in stdout.splitlines():
            if line.startswith("STATUS failed "):
                return line[len("STATUS failed "):]
        return ""

    def no_player(self):
        """playerctl present but nothing on the bus."""
        return self.stub("playerctl", "exit 1\n")


class TestLinkResolution(DownloadTest):
    """A bad link is a hard failure, never a silent fallback to the search."""

    def test_unusable_link_is_rejected_not_searched(self):
        self.no_player()
        yt_args = self.tmp / "yt-args"
        self.stub("yt-dlp", f'echo "$@" >{yt_args}\nexit 1\n')
        r = self.download(["audio", "0", "", "", "not a link"])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.failure(r.stdout), "unusable link: not a link")
        # A fallback would answer a different request than the one made: the
        # wrong video lands in ~/Music and the user finds out later.
        self.assertFalse(yt_args.exists(), "fell back to the search")

    def test_literal_undefined_is_treated_as_no_link(self):
        """The exact string the IpcHandler produced for an omitted argument.

        NowPlayingPopup.resolveLink() drops it before it reaches the script;
        the script agreeing means neither caller can be the reason a download
        fails on it.
        """
        self.stub("playerctl",
                  'echo "Some Artist - Some Song"\n'
                  '[ "$2" = "{{artist}}" ] && echo "Some Artist"\nexit 0\n')
        yt_args = self.tmp / "yt-args"
        self.stub("yt-dlp", f'echo "$@" >{yt_args}\nexit 1\n')
        r = self.download(["audio", "0", "", "", "undefined"])
        self.assertNotEqual(self.failure(r.stdout), "unusable link: undefined")
        self.assertIn("ytsearch1:Some Artist - Some Song", yt_args.read_text())


class TestEmptyFieldMeansNowPlaying(DownloadTest):
    """No url AND no title -> ask the bus. Enforced in the script, not QML."""

    def playing(self, title="Some Song", artist="Some Artist"):
        # playerctl is called two ways by download-track.sh: `metadata
        # xesam:title` and `metadata --format {{artist}}`.
        self.stub("playerctl",
                  'if [ "$2" = "--format" ]; then echo "' + artist + '";'
                  ' else echo "' + title + '"; fi\n')

    def test_searches_what_the_bus_reports(self):
        self.playing()
        yt_args = self.tmp / "yt-args"
        self.stub("yt-dlp", f'echo "$@" >{yt_args}\nexit 1\n')
        self.download(["audio", "0"])
        self.assertIn("ytsearch1:Some Artist Some Song", yt_args.read_text())

    def test_bus_titles_override_the_caller_s(self):
        # The popup passes its MPRIS strings; they may be stale by the time the
        # download starts, and an empty field means "whatever is playing now".
        self.playing(title="Newer Track", artist="Newer Artist")
        yt_args = self.tmp / "yt-args"
        self.stub("yt-dlp", f'echo "$@" >{yt_args}\nexit 1\n')
        self.download(["audio", "0", "", ""])
        self.assertIn("ytsearch1:Newer Artist Newer Track", yt_args.read_text())

    def test_nothing_playing_fails_with_a_reason(self):
        self.no_player()
        self.stub("yt-dlp", "exit 1\n")
        r = self.download(["audio", "0"])
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.failure(r.stdout), "nothing is playing")

    def test_bad_mode_still_exits_2_without_touching_the_bus(self):
        r = self.download(["nonsense", "0"])
        self.assertEqual(r.returncode, 2)


class TestFailureIsExplained(DownloadTest):
    """A failed download says why. yt-dlp's first ERROR line is the why."""

    def test_yt_dlp_error_line_is_quoted_not_the_usage_hint(self):
        self.stub("playerctl", "exit 1\n")
        # yt-dlp reports errors on stderr; the script traps that stream to find
        # the reason, and must not lose it for a user reading a terminal.
        self.stub("yt-dlp",
                  'echo "ERROR: [youtube] abc: Sign in to confirm you are not a bot" >&2\n'
                  'echo "Type yt-dlp --help to get a list of all options." >&2\n'
                  "exit 1\n")
        r = self.download(["audio", "0", "Some Song", "Some Artist"])
        self.assertEqual(r.returncode, 1)
        why = self.failure(r.stdout)
        self.assertIn("Sign in to confirm", why)
        self.assertNotIn("yt-dlp --help", why)

    def test_reason_is_reported_to_the_desktop_too(self):
        self.stub("playerctl", "exit 1\n")
        self.stub("yt-dlp", 'echo "ERROR: Video unavailable" >&2\nexit 1\n')
        self.stub("notify-send", f'echo "$*" >{self.tmp / "notify"}\n')
        self.download(["audio", "0", "Some Song", "Some Artist"])
        self.assertIn("Video unavailable", (self.tmp / "notify").read_text())


class TestProgressStream(DownloadTest):
    """The three line kinds the popup parses, unchanged by all this."""

    def test_status_and_progress_lines_reach_stdout(self):
        self.stub("playerctl", "exit 1\n")
        self.stub("yt-dlp",
                  'echo "STATUS fetching"\n'
                  'echo "DL  42.0%"\n'
                  'echo "PP NA"\n'
                  "exit 1\n")
        r = self.download(["audio", "0", "Some Song", "Some Artist"])
        self.assertIn("STATUS fetching", r.stdout)
        self.assertIn("DL  42.0%", r.stdout)
        self.assertIn("PP NA", r.stdout)

    def test_stderr_still_reaches_the_terminal(self):
        # Trapping stderr to find the reason must not swallow it for a user
        # running the script by hand.
        self.stub("playerctl", "exit 1\n")
        self.stub("yt-dlp", 'echo "[download] Destination:" >&2\nexit 1\n')
        r = self.download(["audio", "0", "Some Song", "Some Artist"])
        self.assertIn("[download] Destination:", r.stderr)


class TestNoOrphanedYtDlp(DownloadTest):
    """yt-dlp must never outlive the script that started it.

    Reproduces the live incident: tearing a QProcess child down does not give
    bash a chance to run its TERM trap, so the backgrounded yt-dlp was
    reparented to init and kept running for hours. SIGKILL is the strongest
    version of that death, so it is the one tested.
    """

    def test_sigkill_of_the_script_kills_yt_dlp(self):
        marker = self.tmp / "yt-dlp.pid"
        # Ignores TERM, like a yt-dlp wedged in a network call: only a real
        # kill-tree (or PDEATHSIG, which is the kernel's) can stop it.
        self.stub("yt-dlp",
                  'trap "" TERM INT\n'
                  f'echo $$ >{marker}\n'
                  "exec sleep 300\n")
        self.stub("playerctl", "exit 1\n")
        script = subprocess.Popen(
            [DOWNLOAD, "audio", "0", "Some Song", "Some Artist"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            env=self.env(), start_new_session=True)
        self.addCleanup(script.kill)

        deadline = time.time() + 20
        while time.time() < deadline and not marker.exists():
            self.assertIsNone(script.poll(), "download exited before yt-dlp started")
            time.sleep(0.1)
        self.assertTrue(marker.exists(), "the yt-dlp stub never started")
        pid = int(marker.read_text().strip())

        os.killpg(os.getpgid(script.pid), signal.SIGKILL)
        script.wait(timeout=20)

        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.1)
        self.fail(f"yt-dlp {pid} outlived the script that started it")

    def test_yt_dlp_runs_in_its_own_process_group(self):
        # So the trap can signal ffmpeg post-processors along with it, not just
        # the one pid.
        self.stub("playerctl", "exit 1\n")
        self.stub("yt-dlp",
                  'ps -o pgid= -p $$ | tr -d " " >' + str(self.tmp / "pgid") + "\nexit 1\n")
        proc = subprocess.Popen(
            [DOWNLOAD, "audio", "0", "Some Song", "Some Artist"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=self.env())
        script_pgid = os.getpgid(proc.pid)   # read before the process is reaped
        proc.wait(timeout=60)
        pgid = int((self.tmp / "pgid").read_text().strip())
        self.assertNotEqual(pgid, script_pgid,
                            "yt-dlp shares the script's process group")


class TestGuardArgv(DownloadTest):
    """run-yt-dlp.py must not eat the URL into argv[0]."""

    def test_url_lands_in_argv1(self):
        seen = self.tmp / "argv1"
        # "$1", not "$0": a shebang script is handed its resolved PATH as $0 no
        # matter what argv[0] was, but $1 is exactly the question — did the URL
        # survive as an argument, or did execvp eat it as the program name?
        self.stub("yt-dlp", f'printf "%s\\n" "$1" >{seen}\n')
        subprocess.run([GUARD, "ytsearch1:Some Song", "--no-playlist"],
                       env=self.env(), capture_output=True, text=True, timeout=30)
        # Handing execvp a bare sys.argv[1:] would make the URL argv[0]; yt-dlp
        # then parses only sys.argv[1:] as options: "no URL" on every download.
        self.assertEqual(seen.read_text().strip(), "ytsearch1:Some Song")


class TestPopupContract(unittest.TestCase):
    """NowPlayingPopup.qml must keep the shape the IPC shim depends on."""

    def setUp(self):
        self.qml = (SCRIPTS.parent / "quickshell" / "sunset" / "components"
                    / "NowPlayingPopup.qml").read_text()
        self.shell = (SCRIPTS.parent / "quickshell" / "sunset" / "shell.qml").read_text()

    def test_download_url_is_a_root_method_not_only_an_ipc_verb(self):
        # shell.qml's shim does loader.item[fn].apply(...) with fn="downloadUrl".
        # An IpcHandler function is not reachable that way: the call threw a
        # TypeError and the download silently never started.
        self.assertRegex(self.qml, r"\n\s*function downloadUrl\(",
                         "NowPlayingPopup has no root downloadUrl()")
        self.assertIn('root.dispatch(nowPlayingLoader, "downloadUrl"', self.shell)

    def test_both_dispatch_targets_are_root_methods(self):
        for fn in ("download", "downloadUrl"):
            with self.subTest(fn=fn):
                self.assertRegex(self.qml, r"\n\s*function " + fn + r"\(")
                self.assertIn(f'root.dispatch(nowPlayingLoader, "{fn}"', self.shell)

    def test_the_three_spellings_of_no_link_all_resolve_to_the_field(self):
        # undefined (menu click), "undefined" (IpcHandler coercion) and "".
        block = self.qml.split("function resolveLink(")[1].split("function ")[0]
        for shape in ('url === undefined', 's === "undefined"', 's === "null"'):
            self.assertIn(shape, block)

    def test_shim_keeps_the_ipc_type_and_the_popup_absorbs_the_coercion(self):
        # quickshell refuses an untyped IPC argument ("Type of argument 3
        # (url: QVariant) cannot be used across IPC"), so the shim's
        # `url: string` is load-bearing — and with it an omitted argument is
        # coerced to the TEXT "undefined". Fixing one side alone is not enough:
        # the popup has to fold it back, which test_..._spellings above covers.
        self.assertRegex(self.shell,
                         r'function downloadUrl\(mode: string, quality: string, url: string\): void')

    def test_failure_reason_is_streamed_and_shown(self):
        self.assertIn("STATUS failed ", self.qml)
        self.assertIn("property string dlError", self.qml)


if __name__ == "__main__":
    unittest.main()