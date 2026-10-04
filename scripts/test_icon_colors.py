"""The neutral icon ramp must be one colour, derived the same way on both sides.

Two programs write the shell's icon colour and they are not allowed to disagree:

  * scripts/sync-external-theme.py -> colorlib.neutral_icon() bakes it into every
    `stroke=`/`fill=` in assets/icons/theme/<fp>/*.svg, because quickshell's
    IconImage has no `color` property to bind.
  * quickshell/sunset/services/Theme.qml `_pinIcon()` returns it as `Theme.icon`,
    which the launcher's Nerd Font glyph Text binds directly.

Those two kinds of icon sit in the SAME launcher list, one row apart, so a drift
of one 8-bit channel is visible as two different greys in one column. So this
does not re-implement the QML: it extracts the real functions out of Theme.qml
and runs them under node, then compares against the real colorlib. Change the
algorithm on either side and this fails.

It also pins the properties the ramp exists for, which are the reason it is
derived rather than authored per palette:

  * both steps clear their contrast floor against bg, on every palette
  * the two steps are genuinely two weights, not one colour twice
  * the icon is neutral (far less saturated than the accent) but tinted (its hue
    is still the accent's)
  * it depends on `accent` and `bg` and NOTHING else, so moving a surface cannot
    quietly restyle the chrome
"""

import json
import re
import subprocess
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
REPO = SCRIPTS.parent
THEME_QML = REPO / "quickshell" / "sunset" / "services" / "Theme.qml"
ICON_DIR = REPO / "quickshell" / "sunset" / "assets" / "icons"

colorlib_spec = __import__("importlib.util", fromlist=["util"]).spec_from_file_location(
    "colorlib", SCRIPTS / "colorlib.py")
colorlib = __import__("importlib.util", fromlist=["util"]).module_from_spec(colorlib_spec)
colorlib_spec.loader.exec_module(colorlib)

sync_spec = __import__("importlib.util", fromlist=["util"]).spec_from_file_location(
    "sync_external_theme", SCRIPTS / "sync-external-theme.py")
sync = __import__("importlib.util", fromlist=["util"]).module_from_spec(sync_spec)
sync_spec.loader.exec_module(sync)

# The QML functions _pinIcon leans on. Listed explicitly so a rename fails here
# instead of silently dropping one side of the comparison.
QML_FUNCTIONS = ("_rgb", "_hex", "_lum", "_contrast", "_mix", "_greyAt", "_push",
                 "_pinIcon")
QML_REALS = ("floorEps", "iconTint", "iconRatio", "iconMutedRatio")


# --------------------------------------------------------------------------
# pulling real code out of Theme.qml
# --------------------------------------------------------------------------

def _skip_noise(text, i):
    """Advance past a line comment / block comment / string starting at i.

    A naive `text.index("}")` would stop on a brace inside a comment, and these
    functions are heavily commented on purpose -- the comments are where the
    traps are documented, so they are not going away.
    """
    if text.startswith("//", i):
        end = text.find("\n", i)
        return len(text) if end < 0 else end
    if text.startswith("/*", i):
        end = text.find("*/", i)
        return len(text) if end < 0 else end + 2
    if text[i] in "\"'`":
        quote = text[i]
        i += 1
        while i < len(text):
            if text[i] == "\\":
                i += 2
                continue
            if text[i] == quote:
                return i + 1
            i += 1
        raise AssertionError("unterminated string in Theme.qml")
    return i


def _matching_brace(text, open_index):
    """Index of the `}` closing the `{` at `open_index`, skipping comments/strings."""
    assert text[open_index] == "{"
    depth, i = 0, open_index
    while i < len(text):
        i = _skip_noise(text, i)
        if i >= len(text):
            break
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise AssertionError("unbalanced braces in Theme.qml")


def qml_reals():
    """The numeric constants, parsed out of Theme.qml."""
    qml = THEME_QML.read_text()
    values = {}
    for name in QML_REALS:
        match = re.search(r"readonly property real %s:\s*([-\d.]+)" % name, qml)
        assert match, "Theme.qml no longer declares readonly property real %s" % name
        values[name] = float(match.group(1))
    return values


def qml_source():
    """A JS object literal exposing Theme.qml's real icon-ramp functions.

    Lifted verbatim, not retyped. These functions call each other, so they all go
    into one namespace object -- which is exactly how QML resolves them, since
    they are all members of the same root object.
    """
    qml = THEME_QML.read_text()
    members = []
    for name in QML_FUNCTIONS:
        start = qml.index("function %s(" % name)
        brace = qml.index("{", start)
        # `_name: function _name(...) {...}` -- object-literal members, not
        # shorthand, which is not valid JS.
        members.append("%s: %s" % (name, qml[start:_matching_brace(qml, brace) + 1]))
    for name in QML_REALS:
        members.append("%s: %r" % (name, qml_reals()[name]))
    return "const Theme = {%s};\n" % ",\n".join(members)


def qml_pin(palette, ratio):
    """Run Theme.qml's own _pinIcon over `palette`, via node."""
    # The extracted functions call each other by bare name. That is how QML
    # resolves them (all members of one root object) but it is a global lookup in
    # plain JS, so bind them into module scope or the first call throws.
    bindings = ", ".join(QML_FUNCTIONS + QML_REALS)
    program = qml_source() + """
const {BINDINGS} = Theme;
const palette = JSON.parse(process.argv[1]);
const out = [];
for (const r of process.argv.slice(2).map(Number))
    out.push(Theme._pinIcon(palette, r).join(","));
process.stdout.write(out.join(" "));
""".replace("BINDINGS", bindings)
    result = subprocess.run(["node", "-e", program, json.dumps(palette),
                             "%.17g" % colorlib.ICON_RATIO,
                             "%.17g" % colorlib.ICON_MUTED_RATIO],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("node failed on the extracted Theme.qml: %s" % result.stderr)
    return [tuple(int(v) for v in part.split(",")) for part in result.stdout.split()]


NODE = subprocess.run(["node", "--version"], capture_output=True)


# --------------------------------------------------------------------------
# palettes under test
# --------------------------------------------------------------------------

def handwritten_palettes():
    """The 11 palettes Theme.qml declares as literals.

    The four wallpaper palettes and custom are live bindings (`wallpaperDarkPalette`,
    `customPalette`), so they cannot be lifted without executing the whole shell --
    the adversarial set below is what actually guards the derivation, and
    test_wallust_palette.py covers the wallust side end to end.
    """
    qml = THEME_QML.read_text()
    start = qml.index("readonly property var palettes: (")
    block = qml[start:_matching_brace(qml, qml.index("{", start)) + 1]
    out = {}
    for name, body in re.findall(r'"([\w-]+)":\s*\{([^{}]*)\}', block):
        tokens = dict(re.findall(r'"(\w+)":\s*"(#[0-9A-Fa-f]{6})"', body))
        if len(tokens) == len(colorlib.KEYS):
            out[name] = colorlib.complete(tokens)
    return out


def adversarial_palettes():
    """Palettes designed to break the derivation, not to look nice.

    A wallpaper accent can be anything, and the accent only carries a 4.5 floor,
    so the ramp is judged here on inputs chosen to hit its edges: a background
    the accent has no headroom against, an accent that is pure white or pure
    black, an already-achromatic accent (no hue to inherit), and a hue landing on
    each primary.
    """
    base = colorlib.DEFAULT_PALETTE
    out = {}
    for name, accent in (("accent-white", "#FFFFFF"), ("accent-black", "#000000"),
                         ("accent-mid-grey", "#808080"), ("accent-red", "#FF0000"),
                         ("accent-green", "#00FF00"), ("accent-blue", "#0000FF"),
                         ("accent-cyan", "#00FFFF")):
        out[name] = {**base, "accent": accent}
    # A light background: the pin has to push AWAY instead of pulling toward it,
    # and _push picks black/white by headroom. This is the wallpaper that used to
    # make the bar's icons disappear.
    for name, bg, panel, row in (("light-bg", "#F2F0EE", "#EAE7E4", "#FFFFFF"),
                                 ("mid-grey-bg", "#808080", "#6E6E6E", "#949494")):
        out[name] = {**base, "bg": bg, "panel": panel, "row": row,
                     "accent": "#8A3FFC", "text": "#101010"}
    # Accent only just clearing its own floor, on a background it barely beats.
    out["accent-at-floor"] = {**base, "bg": "#101010", "accent": "#3A3A3A"}
    return out


ALL = {**handwritten_palettes(), **adversarial_palettes()}


def icon_colors(palette):
    return {"icon": colorlib.neutral_icon(palette),
            "iconMuted": colorlib.neutral_icon(palette, colorlib.ICON_MUTED_RATIO)}


class ConstantParityTests(unittest.TestCase):
    def test_qml_constants_match_colorlib(self):
        """The taste knob is three numbers written down twice. They must agree."""
        qml = qml_reals()
        self.assertEqual(qml["iconTint"], colorlib.ICON_TINT,
                         "Theme.qml iconTint drifted from colorlib ICON_TINT")
        self.assertEqual(qml["iconRatio"], colorlib.ICON_RATIO,
                         "Theme.qml iconRatio drifted from colorlib ICON_RATIO")
        self.assertEqual(qml["iconMutedRatio"], colorlib.ICON_MUTED_RATIO,
                         "Theme.qml iconMutedRatio drifted from colorlib ICON_MUTED_RATIO")
        self.assertEqual(qml["floorEps"], colorlib.FLOOR_EPS,
                         "Theme.qml floorEps drifted from colorlib FLOOR_EPS")


@unittest.skipIf(NODE.returncode != 0, "node is required to run Theme.qml's own functions")
class QmlPythonParityTests(unittest.TestCase):
    def test_qml_and_python_agree_on_every_palette(self):
        """The shipped QML and the shipped Python must return the same 8-bit triple."""
        self.assertGreaterEqual(len(ALL), 15, "palette extraction regressed")
        for name, palette in sorted(ALL.items()):
            with self.subTest(palette=name):
                python = [colorlib.rgb(colorlib.neutral_icon(palette, ratio))
                          for ratio in (colorlib.ICON_RATIO, colorlib.ICON_MUTED_RATIO)]
                self.assertEqual(qml_pin(palette, colorlib.ICON_RATIO), python,
                                 "Theme.qml _pinIcon and colorlib.neutral_icon "
                                 "disagree on %s" % name)


class RampPropertyTests(unittest.TestCase):
    def test_both_steps_clear_their_floor_against_bg(self):
        """The whole point of pinning: an icon cannot be invisible on a wallpaper."""
        for name, palette in sorted(ALL.items()):
            bg = colorlib.rgb(palette["bg"])
            with self.subTest(palette=name):
                for key, ratio in (("icon", colorlib.ICON_RATIO),
                                   ("iconMuted", colorlib.ICON_MUTED_RATIO)):
                    got = colorlib.contrast(colorlib.rgb(icon_colors(palette)[key]), bg)
                    self.assertGreaterEqual(
                        got, ratio - colorlib.FLOOR_EPS,
                        "%s %s is %.3f:1 on bg %s, floor %.2f"
                        % (name, key, got, palette["bg"], ratio))

    def test_the_ramp_is_two_weights_not_one_colour_twice(self):
        """iconMuted has to be quieter, or "muted"/"off" states read as normal."""
        for name, palette in sorted(ALL.items()):
            with self.subTest(palette=name):
                colors = icon_colors(palette)
                self.assertNotEqual(colors["icon"], colors["iconMuted"],
                                    "%s: the two steps collapsed to one colour" % name)

    def test_icon_is_neutral_but_carries_the_accent_hue(self):
        """Neutral AND tinted. Either half alone would fail the brief."""
        for name, palette in sorted(ALL.items()):
            accent = colorlib.rgb(palette["accent"])
            icon = colorlib.rgb(icon_colors(palette)["icon"])
            if colorlib.saturation(accent) < 1e-6:
                continue  # an achromatic accent has no hue to inherit, by definition
            with self.subTest(palette=name):
                self.assertLess(colorlib.saturation(icon),
                                colorlib.saturation(accent),
                                "%s: icon is not more neutral than the accent" % name)
                hue_gap = abs(colorlib.hue(icon) - colorlib.hue(accent))
                self.assertLess(min(hue_gap, 1 - hue_gap), 0.09,
                                "%s: icon drifted off the accent's hue" % name)

    def test_icon_depends_only_on_accent_and_bg(self):
        """Moving a surface must not restyle the chrome drawn on top of it.

        Locks the derivation's input set: if `icon` ever reads `panel`/`row`/
        `muted`, the bar's icons would shift whenever a popup's background did.
        """
        base = colorlib.DEFAULT_PALETTE
        reference = icon_colors(base)
        for key in colorlib.KEYS:
            if key in ("accent", "bg"):
                continue
            moved = colorlib.complete({**base, key: "#3A2F2C"})
            with self.subTest(token=key):
                self.assertEqual(icon_colors(moved), reference,
                                 "icon colour moved when %s changed" % key)

    def test_icon_is_not_merely_the_accent(self):
        """Guards the regression that motivated this: the tray read as alerts."""
        for name, palette in sorted(ALL.items()):
            colors = icon_colors(palette)
            with self.subTest(palette=name):
                self.assertNotEqual(colors["icon"], palette["accent"].upper(),
                                    "%s: icon is just the accent again" % name)
                self.assertNotEqual(colors["icon"], palette["text"].upper(),
                                    "%s: icon is body text weight" % name)


class RenderedIconTests(unittest.TestCase):
    """What actually lands on disk in assets/icons/theme/<fp>/."""

    def rendered(self, name):
        return sync.render_icon((ICON_DIR / name).read_text(),
                                colorlib.DEFAULT_PALETTE, icon_colors(colorlib.DEFAULT_PALETTE))

    def strokes(self, name):
        return re.findall(r'(?:stroke|fill)="(#[0-9A-Fa-f]{6})"',
                          self.rendered(name).replace('="#000000"', '="#000000"'))

    def test_stateful_pairs_keep_two_distinct_weights(self):
        """`dim` is the only role with its own step, and it is load-bearing.

        These are the only pairs in the set where colour is the only thing
        carrying the state; collapse them and a muted sink looks like a working
        one. The repeat off/on trio counts: `repeat-off` has to stay at
        iconMuted while `repeat`/`repeat-one` ride the normal icon weight, or
        "not looping" is only distinguishable by a fill the SVG cannot carry.
        """
        for normal, off in (("volume.svg", "volume-muted.svg"),
                            ("wifi.svg", "wifi-off.svg"),
                            ("repeat.svg", "repeat-off.svg"),
                            ("repeat-one.svg", "repeat-off.svg"),
                            ("pin.svg", "pin-off.svg")):
            with self.subTest(pair=normal):
                self.assertNotEqual(set(self.strokes(normal)), set(self.strokes(off)))

    def test_no_chrome_icon_is_left_on_a_frozen_sunset_hex(self):
        """Regression: the tray read waybar/icons/, whose strokes never move.

        Any hex still in the rendered output has to be either the derived icon
        colour, the bg cut-out, or a literal multi-colour in palette.svg.
        """
        allowed = {icon_colors(colorlib.DEFAULT_PALETTE)["icon"],
                   icon_colors(colorlib.DEFAULT_PALETTE)["iconMuted"],
                   colorlib.DEFAULT_PALETTE["bg"].upper()}
        for svg in sorted(ICON_DIR.glob("*.svg")):
            for value in re.findall(r'(?:stroke|fill)="(#[0-9A-Fa-f]{6})"',
                                    self.rendered(svg.name)):
                with self.subTest(icon=svg.name, stroke=value):
                    if svg.name == "palette.svg":
                        continue  # four literal swatches, that is the whole icon
                    self.assertIn(value.upper(), allowed,
                                  "%s still renders %s" % (svg.name, value))

    def test_bar_widgets_read_the_themed_icon_set(self):
        """No component may point at waybar/icons/: those strokes are frozen.

        They are the rollback gold and every colour in them is a literal sunset
        hex, so a widget reading from there ignores the palette entirely and
        renders a different colour from its neighbour.
        """
        for qml in sorted((REPO / "quickshell" / "sunset").rglob("*.qml")):
            body = qml.read_text()
            code = "\n".join(line for line in body.splitlines()
                             if not line.lstrip().startswith("//"))
            with self.subTest(component=qml.name):
                self.assertNotIn("waybar/icons", code,
                                 "%s still loads waybar/icons/*.svg" % qml.name)

    def test_launcher_glyph_column_uses_the_icon_token(self):
        """The glyph column must be Theme.icon, not body text.

        The glyph Text and the IconImage beside it are the two ways a row draws
        an icon, one row apart; if the glyph uses `text` and the SVG uses the
        baked icon colour, one list shows two greys.
        """
        launcher = (REPO / "quickshell" / "sunset" / "components" / "Launcher.qml").read_text()
        self.assertIn("readonly property color iconCol: Theme.icon", launcher)
        marker = "visible: !!(row.rowData && row.rowData.glyph)"
        start = launcher.index(marker)
        glyph = launcher[start:launcher.index("\n                                IconImage {", start)]
        # The glyph's own colour binding. "IconImage" also appears in the comment
        # explaining WHY this is the icon token, hence the code-anchored slice.
        colour = [line.strip() for line in glyph.splitlines()
                  if line.strip().startswith("color:")]
        self.assertEqual(
            colour,
            ["color: appList.currentIndex === index ? root.selText : root.iconCol"],
            "the launcher glyph colour changed; an icon weight and a body-text "
            "weight in one column is what this test exists to prevent")


if __name__ == "__main__":
    unittest.main()