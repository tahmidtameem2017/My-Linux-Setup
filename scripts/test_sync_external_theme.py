"""Tests for scripts/sync-external-theme.py — the exporter that keeps tmux,
alacritty, niri and the HTML guide on the palette quickshell has active.

These matter because every one of those targets is a *format with no include
mechanism*: alacritty TOML, niri KDL, tmux config and CSS all need the palette
substituted into them, and a silent failure there is invisible until someone
looks at a status bar. The assertions are therefore mostly "the file parses and
the palette is actually in it", not "the exact bytes match".
"""

import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
REPO = SCRIPTS.parent

spec = importlib.util.spec_from_file_location("sync_external_theme", SCRIPTS / "sync-external-theme.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

clib_spec = importlib.util.spec_from_file_location("colorlib", SCRIPTS / "colorlib.py")
clib = importlib.util.module_from_spec(clib_spec)
clib_spec.loader.exec_module(clib)

# A fixed layout.kdl fixture with the hand-written sunset colours the generator
# has to replace. Deliberately NOT a copy of the live niri/layout.kdl: that file
# is rewritten in place by the generator, so copying it would make these tests
# pass or fail depending on whatever palette happened to be active.
LAYOUT_KDL_FIXTURE = """\
// fixture
layout {
    gaps 6
    preset-column-widths {
        proportion 0.5
    }
    focus-ring {
        width 3
        active-gradient from="#E85D2F" to="#F7C7A1" angle=45
        inactive-color "#3D2B24"
    }
    tab-indicator {
        active-color "#E85D2F"
        inactive-color "#3D2B24"
    }
    border {
        off
    }
    struts {
        left 0
        right 0
        top 0
        bottom 0
    }
    background-color "#000000"
}
"""


# A stand-in for the stroke icon set: two tokens (#E85D2F accent, #7C8A6A muted),
# one cut-out (#000000) and one colour that is NOT a taste.md token, which must
# survive untouched rather than be guessed at.
ICON_SVGS = {
    "power.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#E85D2F" d="M0"/></svg>\n',
    "wifi.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path stroke="#7C8A6A" d="M0"/></svg>\n',
    "wifi-off.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#555555" d="M0"/></svg>\n',
    "volume-muted.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path stroke="#555555" d="M0"/></svg>\n',
    "logo.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#E85D2F" d="M0"/>'
                '<path fill="#000000" d="M1"/></svg>\n',
    "brand.svg": '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#123456" d="M0"/></svg>\n',
}


TOKYO = {
    "bg": "#1a1b26", "panel": "#16161e", "row": "#1f2335", "border": "#292e42",
    "borderStrong": "#3b4261", "accent": "#7aa2f7", "accentHover": "#7dcfff",
    "text": "#c0caf5", "muted": "#737aa2", "dim": "#4a5170", "danger": "#f7768e",
}
DRACULA = {
    "bg": "#282a36", "panel": "#343746", "row": "#44475a", "border": "#343746",
    "borderStrong": "#6272a4", "accent": "#bd93f9", "accentHover": "#ff79c6",
    "text": "#f8f8f2", "muted": "#9a9bb3", "dim": "#4d4f68", "danger": "#ff5555",
}
NEARLY_BLACK_WALLPAPER = {  # the failure mode that motivated ensure_contrast here
    "bg": "#010101", "panel": "#020202", "row": "#030303", "border": "#040404",
    "borderStrong": "#050505", "accent": "#0A0A0A", "accentHover": "#0C0C0C",
    "text": "#101010", "muted": "#0D0D0D", "dim": "#080808", "danger": "#0B0B0B",
}


def tmux_eval(path, expr, server="synctest"):
    """Start a throwaway tmux server from `path` and read an option back."""
    subprocess.run(["tmux", "-L", server, "kill-server"], capture_output=True)
    started = subprocess.run(["tmux", "-L", server, "-f", str(path), "new-session", "-d"],
                             capture_output=True, text=True)
    if started.returncode != 0:
        subprocess.run(["tmux", "-L", server, "kill-server"], capture_output=True)
        raise AssertionError("tmux refused %s: %s" % (path, started.stderr))
    import time
    time.sleep(0.4)
    got = subprocess.run(["tmux", "-L", server, "show-options", "-gv", expr],
                         capture_output=True, text=True).stdout.strip()
    subprocess.run(["tmux", "-L", server, "kill-server"], capture_output=True)
    return got


class AnsiDerivationTests(unittest.TestCase):
    def test_every_slot_is_readable_against_bg(self):
        for name, palette in (("tokyo", TOKYO), ("dracula", DRACULA),
                              ("near-black", NEARLY_BLACK_WALLPAPER)):
            with self.subTest(theme=name):
                ansi = sync.derive_ansi(palette)
                bg = clib.rgb(palette["bg"])
                for slot, value in ansi.items():
                    self.assertRegex(value, r"^#[0-9A-F]{6}$", slot)
                    if slot == "CURSOR_TEXT":
                        # Deliberately NOT contrast-fitted: it is the glyph
                        # colour inside the cursor and must equal bg.
                        self.assertEqual(value, palette["bg"].upper())
                        continue
                    self.assertGreaterEqual(clib.contrast(clib.rgb(value), bg),
                                            sync.ANSI_MIN_CONTRAST - 0.1,
                                            "%s slot %s" % (name, slot))

    def test_body_text_clears_the_stricter_body_target(self):
        ansi = sync.derive_ansi(TOKYO)
        bg = clib.rgb(TOKYO["bg"])
        self.assertGreaterEqual(clib.contrast(clib.rgb(ansi["N_WHITE"]), bg), 4.5)

    def test_unnamed_hues_are_derived_from_the_accent_not_left_stale(self):
        # blue/magenta/cyan had no taste.md token and used to keep a hardcoded
        # Frosted-Midnight literal, so a palette switch never touched them.
        ansi = sync.derive_ansi(TOKYO)
        accent = clib.rgb(TOKYO["accent"])
        self.assertNotEqual(ansi["N_BLUE"], TOKYO["accent"])
        for slot, degrees in (("N_BLUE", 180), ("N_MAGENTA", -60), ("N_CYAN", 60)):
            with self.subTest(slot=slot):
                self.assertAlmostEqual(
                    clib.hue(clib.rgb(ansi[slot])),
                    (clib.hue(accent) + degrees / 360.0) % 1.0, places=5)

    def test_two_themes_produce_different_ansi_sets(self):
        self.assertNotEqual(sync.derive_ansi(TOKYO), sync.derive_ansi(DRACULA))


class RenderTests(unittest.TestCase):
    def test_tmux_fragment_has_no_unfilled_placeholder(self):
        text = sync.render_tmux(TOKYO, sync.derive_ansi(TOKYO))
        # A leaked `{token}` would reach tmux verbatim and abort the parse.
        self.assertIsNone(re.search(r"\{[A-Za-z_][A-Za-z0-9_]*\}", text))
        self.assertNotIn("#E85D2F", text)
        self.assertIn("pane-colours[15]", text)

    def test_tmux_search_glyph_is_literal_not_an_escape(self):
        # tmux's parser rejects `\u{...}` with "invalid \u argument" and STOPS
        # at the first error, which silently dropped every later line — so the
        # glyph must be a literal codepoint in the emitted line.
        text = sync.render_tmux(TOKYO, sync.derive_ansi(TOKYO))
        status_left = [l for l in text.splitlines() if l.startswith("set -g status-left")]
        self.assertEqual(len(status_left), 1)
        self.assertIn(chr(0xF02A), status_left[0])
        self.assertNotIn(r"\u", status_left[0])

    def test_help_css_declares_every_token_and_the_derived_extras(self):
        css = sync.render_help_css(TOKYO)
        for key in clib.KEYS:
            self.assertIn("--%s:" % re.sub(r"(?<!^)(?=[A-Z])", "-", key).lower(), css)
        for extra in ("--bg-soft", "--panel-warm", "--line", "--line-strong",
                      "--olive", "--olive-dim", "--text-hi", "--text-2", "--text-3",
                      "--accent-rgb", "--text-rgb", "--muted-rgb", "--olive-rgb"):
            self.assertIn(extra, css, extra)
        # The rgb channels must be usable inside rgba(var(--x), a).
        self.assertRegex(css, r"--accent-rgb: \d+, \d+, \d+;")

    def test_niri_rewrite_touches_only_theme_properties(self):
        source = LAYOUT_KDL_FIXTURE
        out = sync.render_niri_layout(source, TOKYO)
        self.assertIn('active-gradient from="%s" to="%s" angle=45'
                      % (TOKYO["accent"], TOKYO["text"]), out)
        self.assertIn('active-color "%s"' % TOKYO["accent"], out)
        self.assertIn('inactive-color "%s"' % TOKYO["borderStrong"], out)
        self.assertIn('background-color "%s"' % TOKYO["bg"], out)
        # Structural properties must be untouched.
        for keep in ("gaps 6", "width 3", "off", "left 0", "top 0"):
            self.assertIn(keep, out, keep)
        # Idempotent.
        self.assertEqual(out, sync.render_niri_layout(out, TOKYO))

    def test_niri_rewrite_survives_a_sibling_after_the_target_node(self):
        # The regression: a one-slot "current node" tracker treated
        # `background-color` as outside `layout` because a dozen sibling nodes
        # had opened and closed in between.
        source = "layout {\n    focus-ring {\n        width 3\n    }\n" \
                 "    struts {\n        left 0\n    }\n    background-color \"#000000\"\n}\n"
        out = sync.render_niri_layout(source, TOKYO)
        self.assertIn('background-color "%s"' % TOKYO["bg"], out)

    def test_template_render_leaves_unknown_placeholders_alone(self):
        self.assertEqual(sync.render_template("{{FG}} {{NOPE}}", {"FG": "#fff"}),
                         "#fff {{NOPE}}")


@unittest.skipUnless(shutil.which("tmux"), "tmux not installed")
class TmuxIntegrationTests(unittest.TestCase):
    def test_fragment_loads_and_applies_without_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "theme.conf"
            conf.write_text(sync.render_tmux(DRACULA, sync.derive_ansi(DRACULA)))
            self.assertEqual(tmux_eval(conf, "status-style"),
                             "bg=default fg=%s" % DRACULA["dim"])
            self.assertEqual(tmux_eval(conf, "pane-border-style"),
                             "fg=%s" % DRACULA["border"])
            slots = tmux_eval(conf, "pane-colours").splitlines()
            self.assertEqual(len(slots), 16)
            self.assertEqual(slots[1], DRACULA["accent"].lower())

    def test_re_sourcing_does_not_grow_the_pane_colours_array(self):
        # Without the leading `setw -gu`, every prefix + r appended 16 more.
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "theme.conf"
            conf.write_text(sync.render_tmux(TOKYO, sync.derive_ansi(TOKYO)))
            subprocess.run(["tmux", "-L", "syncidem", "kill-server"], capture_output=True)
            subprocess.run(["tmux", "-L", "syncidem", "-f", str(conf), "new-session", "-d"],
                           capture_output=True, text=True)
            import time
            time.sleep(0.4)
            for _ in range(3):
                subprocess.run(["tmux", "-L", "syncidem", "source-file", str(conf)],
                               capture_output=True)
            count = len(subprocess.run(["tmux", "-L", "syncidem", "show-options", "-gv",
                                        "pane-colours"], capture_output=True, text=True
                                       ).stdout.splitlines())
            subprocess.run(["tmux", "-L", "syncidem", "kill-server"], capture_output=True)
            self.assertEqual(count, 16)

    def test_repo_tmux_conf_sources_the_generated_fragment(self):
        conf = (REPO / "tmux" / "tmux.conf").read_text()
        self.assertIn("source-file -q ~/.config/tmux/theme.conf", conf)
        self.assertNotRegex(conf, r"#[0-9A-Fa-f]{6}",
                            "tmux.conf must not hardcode palette colours any more")


class AlacrittyTemplateTests(unittest.TestCase):
    def test_no_placeholder_survives_rendering(self):
        for name in ("default", "float"):
            with self.subTest(profile=name):
                template = (REPO / "alacritty" / ("%s.toml.in" % name)).read_text()
                self.assertNotRegex(template, r"#[0-9A-Fa-f]{6}",
                                    "the template must hold placeholders, not colours")
                values = dict(TOKYO)
                values.update(sync.derive_ansi(TOKYO))
                values["FG"] = TOKYO["text"]
                values["BG"] = TOKYO["bg"]
                rendered = sync.render_template(template, values)
                self.assertNotIn("{{", rendered)
                self.assertIn(TOKYO["text"], rendered)

    def test_generated_file_is_the_path_callers_already_use(self):
        # ~/.config/alacritty/alacritty.toml -> repo alacritty/default.toml, and
        # float.toml is passed by absolute path from binds.kdl / several scripts.
        for name in ("default", "float"):
            self.assertTrue((REPO / "alacritty" / ("%s.toml.in" % name)).is_file())
        binds = (REPO / "niri" / "binds.kdl").read_text()
        for name in ("default", "float"):
            self.assertIn("alacritty/%s.toml" % name, binds + (REPO / "scripts" / "dropdown-terminal.sh").read_text())


class SyncTests(unittest.TestCase):
    """End-to-end against a throwaway copy of the repo."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.home = self.tmp / "home"
        (self.home / ".config" / "niri").mkdir(parents=True)
        (self.home / ".local" / "share" / "niri-setup").mkdir(parents=True)
        self.setup = self.tmp / "repo"
        (self.setup / "niri").mkdir(parents=True)
        (self.setup / "niri" / "layout.kdl").write_text(LAYOUT_KDL_FIXTURE)
        (self.home / ".config" / "niri" / "layout.kdl").write_text(LAYOUT_KDL_FIXTURE)
        (self.setup / "alacritty").mkdir(parents=True)
        for name in ("default", "float"):
            shutil.copy(REPO / "alacritty" / ("%s.toml.in" % name),
                        self.setup / "alacritty" / ("%s.toml.in" % name))
        icons = self.setup / "quickshell" / "sunset" / "assets" / "icons"
        icons.mkdir(parents=True)
        for name, body in ICON_SVGS.items():
            (icons / name).write_text(body)

    def _sync(self, palette):
        return sync.sync(self.setup, self.home, palette)

    def test_first_run_reports_every_target(self):
        changed = self._sync(TOKYO)
        self.assertEqual(set(changed), {"tmux", "alacritty", "niri", "help", "icons"})
        self.assertTrue((self.setup / "tmux" / "theme.conf").is_file())
        self.assertTrue((self.setup / "alacritty" / "default.toml").is_file())
        self.assertTrue((self.setup / "alacritty" / "float.toml").is_file())
        self.assertTrue((self.setup / "help" / "theme.css").is_file())
        self.assertIn(TOKYO["accent"], (self.setup / "help" / "theme.css").read_text())

    def test_second_run_with_the_same_palette_changes_nothing(self):
        self._sync(TOKYO)
        self.assertEqual(self._sync(TOKYO), [])

    def test_switching_palette_rewrites_every_target_including_the_live_niri_copy(self):
        self._sync(TOKYO)
        changed = self._sync(DRACULA)
        self.assertIn("niri", changed)
        self.assertIn(DRACULA["accent"], (self.setup / "niri" / "layout.kdl").read_text())
        self.assertIn(DRACULA["accent"],
                      (self.home / ".config" / "niri" / "layout.kdl").read_text())

    def test_niri_is_not_reported_when_only_another_target_moved(self):
        # Theme.qml reloads the compositor config on the word "niri"; a palette
        # change that left niri/layout.kdl byte-identical must not trigger that.
        self._sync(TOKYO)
        nudge = dict(TOKYO, danger="#FF0000")
        changed = self._sync(nudge)
        self.assertNotIn("niri", changed)
        self.assertIn("tmux", changed)

    def _icon_dir(self):
        fp = (self.home / ".local" / "share" / "niri-setup" / "icon-dir.txt").read_text().strip()
        return self.setup / "quickshell" / "sunset" / "assets" / "icons" / "theme" / fp

    def test_icons_are_remapped_into_their_palette_roles(self):
        """An icon is the derived neutral, NOT the palette's accent.

        This used to assert the opposite -- that power.svg carried `accent` --
        which is the regression: the bar's tray rendered as a row of orange
        alerts competing with the one thing that IS an alert, and the same icon
        was a different colour in the launcher (a Nerd Font glyph off Theme.icon)
        than in the bar (this baked SVG). The neutral ramp is covered in depth by
        scripts/test_icon_colors.py; this only pins the wiring.
        """
        self._sync(TOKYO)
        derived = clib.icon_colors(TOKYO)
        power = (self._icon_dir() / "power.svg").read_text()
        wifi = (self._icon_dir() / "wifi.svg").read_text()
        self.assertIn(derived["icon"], power)
        self.assertIn(derived["icon"], wifi)
        self.assertNotIn(TOKYO["accent"], power)
        # `dim` is the only role with its own step, and it is what draws the
        # off/muted state of the two stateful pairs in the set.
        self.assertIn(derived["iconMuted"], (self._icon_dir() / "volume-muted.svg").read_text())
        self.assertIn(derived["iconMuted"], (self._icon_dir() / "wifi-off.svg").read_text())
        # #000000 is the cut-out inside logo.svg, not a stroke.
        self.assertIn('fill="%s"' % TOKYO["bg"], (self._icon_dir() / "logo.svg").read_text())

    def test_icon_colour_outside_the_token_set_is_left_alone(self):
        # The real set already carried #bd93f9 (dracula) and #7aa2f7 (tokyo
        # night) next to the sunset hexes; rewriting those would be guessing.
        self._sync(TOKYO)
        self.assertIn("#123456", (self._icon_dir() / "brand.svg").read_text())

    def test_icon_dir_is_fingerprinted_and_superseded_copies_are_pruned(self):
        # Qt caches a decoded image per source URL, so an in-place rewrite left
        # every IconImage on the previous theme's raster. The directory has to
        # change name when the palette does.
        self._sync(TOKYO)
        first = self._icon_dir()
        self._sync(DRACULA)
        second = self._icon_dir()
        self.assertNotEqual(first, second)
        self.assertFalse(first.exists(), "stale icon directory must be pruned")
        theme_root = first.parent
        self.assertEqual([d.name for d in theme_root.iterdir() if d.is_dir()],
                         [second.name])

    def test_icon_pointer_keeps_its_inode_across_a_theme_change(self):
        """The shell reads icon-dir.txt through a FileView (QFileSystemWatcher),
        which watches the INODE. A staged write + os.replace killed the watch on
        the very first theme change, so Theme.iconDir kept naming the previous
        fingerprint -- which sync then prunes -- and every IconImage in the shell
        resolved into a deleted directory and rendered blank until a restart.
        The 60s backstop in Theme.qml hides it for a minute; this is the real fix.
        """
        pointer = self.home / ".local" / "share" / "niri-setup" / "icon-dir.txt"
        self._sync(TOKYO)
        before = pointer.stat().st_ino
        self._sync(DRACULA)
        self.assertEqual(pointer.stat().st_ino, before,
                         "icon-dir.txt must be rewritten in place, not renamed")

    def test_icon_pointer_is_published_after_the_icons_exist(self):
        """Announcing a fingerprint before writing its SVGs makes the shell
        resolve a directory that is still empty -> Image.Error -> blank icons."""
        seen = []
        real_write = sync.write_watched

        def spy(path, content):
            seen.append((Path(path), content))
            return real_write(path, content)

        sync.write_watched, original = spy, sync.write_watched
        self.addCleanup(setattr, sync, "write_watched", original)
        self._sync(TOKYO)
        pointer, fingerprint = seen[0]
        self.assertEqual(pointer.name, "icon-dir.txt")
        self.assertTrue((self.setup / "quickshell" / "sunset" / "assets" / "icons"
                         / "theme" / fingerprint.strip() / "power.svg").is_file())

    def test_incomplete_palette_is_completed_not_crashed(self):
        (self.home / ".local" / "share" / "niri-setup" / "active-theme.json").write_text(
            json.dumps({"accent": "#123456", "bg": "not-a-colour"}))
        palette = sync.read_published_palette(self.setup, self.home / ".local/share/niri-setup")
        self.assertEqual(palette["accent"], "#123456")
        self.assertEqual(palette["bg"], clib.DEFAULT_PALETTE["bg"])
        self.assertTrue(clib.is_valid_palette(palette))

    def test_falls_back_to_sunset_when_nothing_is_published(self):
        palette = sync.read_published_palette(self.setup, self.tmp / "nowhere")
        self.assertEqual(palette["accent"], clib.DEFAULT_PALETTE["accent"])
        self.assertTrue(clib.is_valid_palette(palette))

    def test_prefers_the_published_json_over_palette_sh(self):
        d = self.home / ".local" / "share" / "niri-setup"
        (d / "active-theme.json").write_text(json.dumps(TOKYO))
        palette = sync.read_published_palette(self.setup, d)
        self.assertEqual(palette["accent"], TOKYO["accent"])


class CliTests(unittest.TestCase):
    """End-to-end through argv.

    Every case runs against a throwaway setup-home/home pair. The default is the
    REAL repo and the real $HOME, and this script rewrites files in place, so
    running it un-sandboxed would quietly retheme the developer's actual desktop
    as a side effect of the test run.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.setup = self.tmp / "repo"
        (self.setup / "niri").mkdir(parents=True)
        (self.setup / "alacritty").mkdir(parents=True)
        (self.setup / "help").mkdir(parents=True)
        self.home = self.tmp / "home"
        (self.home / ".config" / "niri").mkdir(parents=True)
        (self.home / ".local" / "share" / "niri-setup").mkdir(parents=True)
        (self.setup / "niri" / "layout.kdl").write_text(LAYOUT_KDL_FIXTURE)
        (self.home / ".config" / "niri" / "layout.kdl").write_text(LAYOUT_KDL_FIXTURE)
        for name in ("default", "float"):
            shutil.copy(REPO / "alacritty" / ("%s.toml.in" % name),
                        self.setup / "alacritty" / ("%s.toml.in" % name))

    def _run(self, *args):
        return subprocess.run(["python3", str(SCRIPTS / "sync-external-theme.py"),
                               "--setup-home", str(self.setup),
                               "--home", str(self.home), *args],
                              capture_output=True, text=True)

    def test_stdout_is_one_line_naming_changed_targets(self):
        out = self._run("--palette", json.dumps(TOKYO))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertTrue(out.stdout.startswith("changed: "))
        self.assertEqual(len(out.stdout.strip().splitlines()), 1)
        self.assertEqual(set(out.stdout.split()[1:]),
                         {"tmux", "alacritty", "niri", "help"})

    def test_second_run_is_a_no_op(self):
        self._run("--palette", json.dumps(TOKYO))
        self.assertEqual(self._run("--palette", json.dumps(TOKYO)).stdout.strip(),
                         "changed:")

    def test_garbage_palette_falls_back_instead_of_crashing(self):
        out = self._run("--palette", "not json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertTrue(out.stdout.startswith("changed: "))

    def test_reads_the_published_palette_when_none_is_passed(self):
        (self.home / ".local" / "share" / "niri-setup" / "active-theme.json").write_text(
            json.dumps(DRACULA))
        out = self._run()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn(DRACULA["accent"], (self.setup / "help" / "theme.css").read_text())


if __name__ == "__main__":
    import sys
    unittest.main()