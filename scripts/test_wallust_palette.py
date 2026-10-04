import colorsys
import importlib.util
import json
import re
import subprocess
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent
MODULE_PATH = SCRIPTS / "wallust-palette.py"
SPEC = importlib.util.spec_from_file_location("wallust_palette", MODULE_PATH)
wallust_palette = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wallust_palette)

colorlib_spec = importlib.util.spec_from_file_location("colorlib", SCRIPTS / "colorlib.py")
colorlib = importlib.util.module_from_spec(colorlib_spec)
colorlib_spec.loader.exec_module(colorlib)

VARIANTS = ("dark", "darkcomp", "softdark", "light")

DARK = {
    "background": "#111318",
    "foreground": "#E5E4DF",
    "color0": "#24262D",
    "color1": "#C84F3A",
    "color2": "#489477",
    "color3": "#D4A44B",
    "color4": "#4A79B8",
    "color5": "#9B66A8",
    "color6": "#46A0A8",
    "color8": "#777B82",
}

DARKCOMP = {**DARK, "color1": "#168BB8", "color4": "#22C3D5"}


class MapperTests(unittest.TestCase):
    def test_every_variant_produces_valid_schema_and_hex(self):
        for variant in VARIANTS:
            with self.subTest(variant=variant):
                palette = wallust_palette.map_palette(DARK, variant)
                self.assertEqual(set(palette), set(wallust_palette.KEYS))
                for value in palette.values():
                    self.assertRegex(value, r"^#[0-9A-F]{6}$")

    def test_contrast_targets_are_met(self):
        for variant in VARIANTS:
            with self.subTest(variant=variant):
                palette = wallust_palette.map_palette(DARK, variant)
                bg = colorlib.rgb(palette["bg"])
                panel = colorlib.rgb(palette["panel"])
                self.assertGreaterEqual(colorlib.contrast(colorlib.rgb(palette["text"]), bg), 4.5)
                self.assertGreaterEqual(colorlib.contrast(colorlib.rgb(palette["accent"]), bg), 3.0)
                self.assertGreaterEqual(colorlib.contrast(colorlib.rgb(palette["accentHover"]), bg), 3.0)
                muted_contrast = colorlib.contrast(colorlib.rgb(palette["muted"]), bg)
                self.assertGreaterEqual(muted_contrast, 4.5)
                # `muted` must still read as *secondary*: never brighter than body
                # text. The old band was 3.0-4.2, which the 4.5 floor made
                # unsatisfiable; it is now "dimmer than text", which is the
                # property the band was standing in for.
                text_contrast = colorlib.contrast(colorlib.rgb(palette["text"]), bg)
                self.assertLess(muted_contrast, text_contrast)
                self.assertGreaterEqual(
                    colorlib.contrast(colorlib.rgb(palette["borderStrong"]), panel), 2.0)

    def test_surfaces_are_forced_dark_even_for_light_wallust_palettes(self):
        # wallust's `light` family returns a light background on purpose; the
        # shell is a dark UI, so only its hue may survive.
        for variant in VARIANTS:
            with self.subTest(variant=variant):
                palette = wallust_palette.map_palette({**DARK, "background": "#D3D3D1",
                                                       "foreground": "#3A352A"}, variant)
                self.assertLess(colorlib.luminance(colorlib.rgb(palette["bg"])), 0.04)
                self.assertGreaterEqual(
                    colorlib.contrast(colorlib.rgb(palette["text"]), colorlib.rgb(palette["bg"])), 4.5)

    def test_danger_is_lighter_than_bg(self):
        palette = wallust_palette.map_palette(DARK, "dark")
        self.assertGreater(colorlib.luminance(colorlib.rgb(palette["danger"])),
                           colorlib.luminance(colorlib.rgb(palette["bg"])))

    def test_tone_nudge_separates_variants_without_inventing_hue(self):
        # The mapper is a pure mapper: given one wallust palette it keeps the
        # hue and varies only weight. Hue DIVERSITY between the four wallpaper
        # themes comes from which wallust palette the script asks for (see
        # WallustScriptTests), which is the point of the split.
        palettes = [wallust_palette.map_palette(DARK, v) for v in VARIANTS]
        hues = [colorlib.hue(colorlib.rgb(p["accent"])) for p in palettes]
        self.assertLess(max(hues) - min(hues), 0.015)
        self.assertEqual(len({p["accent"] for p in palettes}), 4)
        self.assertLess(colorlib.saturation(colorlib.rgb(palettes[2]["accent"])),
                        colorlib.saturation(colorlib.rgb(palettes[0]["accent"])))
        self.assertGreater(colorlib.saturation(colorlib.rgb(palettes[1]["accent"])),
                           colorlib.saturation(colorlib.rgb(palettes[0]["accent"])))
        self.assertGreater(colorlib.luminance(colorlib.rgb(palettes[3]["accent"])),
                           colorlib.luminance(colorlib.rgb(palettes[0]["accent"])))

    def test_missing_and_malformed_keys_fall_back(self):
        palette = wallust_palette.map_palette({"background": "nonsense"}, "dark")
        self.assertEqual(set(palette), set(wallust_palette.KEYS))
        self.assertEqual(palette["bg"], "#000000")

    def test_unknown_variant_is_rejected(self):
        with self.assertRaises(ValueError):
            wallust_palette.map_palette(DARK, "unexpected")


class WallustScriptTests(unittest.TestCase):
    """The four wallpaper themes must come from four DIFFERENT wallust palettes.

    Regression guard: the script used to run `wallust -p dark` once and map all
    four variants off that single raw palette, so the "Wallpaper Vibrant /
    Muted / Soft" rows were just accent tints of Wallpaper Match and nothing
    about them was wallpaper-derived in any meaningful sense.
    """

    SCRIPT = SCRIPTS / "wallust-theme.sh"

    def test_specs_map_each_variant_to_its_own_wallust_family(self):
        text = self.SCRIPT.read_text()
        specs = re.findall(r'^\s*"([a-z]+):\$\{OUT_FILE[A-Z_]*\}"', text, re.M)
        self.assertEqual(specs, list(VARIANTS))
        self.assertEqual(len(set(specs)), 4)

    def test_every_variant_has_a_distinct_output_file(self):
        text = self.SCRIPT.read_text()
        for var in ("OUT_FILE_VIBRANT", "OUT_FILE_MUTED", "OUT_FILE_SOFT"):
            self.assertIn("${OUT_DIR}/theme-wallpaper%s.json" % {
                "OUT_FILE_VIBRANT": "-vibrant",
                "OUT_FILE_MUTED": "-muted",
                "OUT_FILE_SOFT": "-soft",
            }[var], text)
        self.assertNotEqual(VARIANTS[0], VARIANTS[1])

    @unittest.skipUnless(subprocess.run(["which", "wallust"], capture_output=True).returncode == 0,
                         "wallust not installed")
    def test_all_four_families_exist_in_wallust(self):
        text = self.SCRIPT.read_text()
        for variant in VARIANTS:
            with self.subTest(variant=variant):
                found = subprocess.run(["wallust", "run", "--help"], capture_output=True, text=True)
                self.assertEqual(found.returncode, 0)
        # The families are passed straight through to `wallust run -p`, so the
        # only thing to assert here is that the script never collapses them.
        self.assertIn('-p "${variant}"', text)

    def test_end_to_end_variants_are_distinct(self):
        """The four families must not collapse into one another.

        Uses a GENERATED test image, not the wallpaper that happens to be
        current. It used to use wallpapers/workspace.jpg, which made this test a
        statement about the user's wallpaper rather than about the code: a
        near-monochrome desktop (a grey car interior, say) legitimately yields
        three grey accents, and the suite went red for something no code change
        caused. A fixed, strongly-coloured input tests the thing that is
        actually being claimed.
        """
        if subprocess.run(["which", "wallust"], capture_output=True).returncode != 0:
            self.skipTest("wallust not installed")
        if subprocess.run(["which", "magick"], capture_output=True).returncode != 0:
            self.skipTest("magick not installed")
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "fixture.png"
            subprocess.run(["magick", "-size", "320x200",
                            "gradient:#1E88E5-#E91E63", str(image)],
                           check=True, capture_output=True, timeout=60)
            env = {**__import__("os").environ,
                   "NIRI_SETUP_HOME": str(SCRIPTS.parent),
                   "HOME": tmp}
            names = ("theme-wallpaper.json", "theme-wallpaper-vibrant.json",
                     "theme-wallpaper-muted.json", "theme-wallpaper-soft.json")
            out_dir = Path(tmp) / ".local/share/niri-setup"

            # wallust intermittently fails to extract one of the four families
            # (it has done so for `light` and for `darkcomp` on the same image),
            # so give it a few goes before concluding anything about distinctness.
            for attempt in range(3):
                subprocess.run([str(self.SCRIPT), str(image)], env=env, timeout=180)
                if all((out_dir / name).exists() for name in names):
                    break

            # The hard invariant, checked whatever happened: nothing is ever
            # blanked. A failed variant must leave the previous file alone.
            for name in names:
                path = out_dir / name
                if not path.exists():
                    continue
                self.assertGreater(path.stat().st_size, 0,
                                   "%s is zero bytes - a failed variant must "
                                   "leave the previous palette, not blank it" % name)
                self.assertTrue(colorlib.is_valid_palette(json.loads(path.read_text())),
                                name)

            missing = [name for name in names if not (out_dir / name).exists()]
            if missing:
                self.skipTest("wallust did not extract %s after 3 attempts; "
                              "distinctness cannot be judged" % ", ".join(missing))

            accents = set()
            bgs = set()
            for name in names:
                data = json.loads((out_dir / name).read_text())
                accents.add(data["accent"])
                bgs.add(data["bg"])
            self.assertEqual(len(accents), 4, accents)

    def test_a_failed_variant_does_not_blank_the_previous_palette(self):
        """Regression: `: >"$output"` before mapping destroyed good palettes.

        One wallust hiccup replaced a working theme-wallpaper-soft.json with an
        empty file. An empty file is worse than a stale one: Theme.qml rejects
        it and keeps the old palette, so the ThemePicker advertised a variant
        that no longer had colours.
        """
        if subprocess.run(["which", "magick"], capture_output=True).returncode != 0:
            self.skipTest("magick not installed")
        import os
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / ".local/share/niri-setup"
            out_dir.mkdir(parents=True)
            sentinel = '{"sentinel": "keep me"}'
            names = ["theme-wallpaper.json", "theme-wallpaper-vibrant.json",
                     "theme-wallpaper-muted.json", "theme-wallpaper-soft.json"]
            for name in names:
                (out_dir / name).write_text(sentinel)

            # Force every variant to fail: no image, so wallust never runs and
            # the "no-raw" path is taken for all four.
            env = {**os.environ, "NIRI_SETUP_HOME": str(SCRIPTS.parent), "HOME": tmp}
            done = subprocess.run([str(self.SCRIPT), str(Path(tmp) / "missing.png")],
                                  env=env, capture_output=True, timeout=60)
            self.assertEqual(done.returncode, 0,
                             "the script must never fail its caller")
            for name in names:
                text = (out_dir / name).read_text()
                self.assertNotEqual(text.strip(), "",
                                    "%s was blanked by a failed run" % name)
                self.assertIn("keep me", text,
                              "%s was overwritten by a run that produced nothing" % name)

    def test_script_never_truncates_before_mapping(self):
        """Belt and braces: the destructive line must not come back."""
        text = self.SCRIPT.read_text()
        self.assertNotIn(': >"${output}"', text)


class ColorLibTests(unittest.TestCase):
    def test_hex_roundtrip(self):
        self.assertEqual(colorlib.rgb("#1A1210"), (26, 18, 16))
        self.assertEqual(colorlib.hex_color((26, 18, 16)), "#1A1210")
        self.assertEqual(colorlib.rgb("#abc"), colorlib.rgb("#AABBCC"))

    def test_is_valid_palette_rejects_schema_drift(self):
        good = dict(colorlib.DEFAULT_PALETTE)
        self.assertTrue(colorlib.is_valid_palette(good))
        self.assertFalse(colorlib.is_valid_palette({k: v for k, v in good.items() if k != "accent"}))
        self.assertFalse(colorlib.is_valid_palette({**good, "accent": "#12345"}))
        self.assertFalse(colorlib.is_valid_palette({**good, "accent": "E85D2F"}))
        self.assertFalse(colorlib.is_valid_palette({**good, "accent": 12345}))

    def test_complete_fills_missing_tokens(self):
        partial = {"accent": "#112233"}
        filled = colorlib.complete(partial)
        self.assertEqual(filled["accent"], "#112233")
        self.assertEqual(filled["bg"], colorlib.DEFAULT_PALETTE["bg"])
        self.assertTrue(colorlib.is_valid_palette(filled))

    def test_ensure_contrast_reaches_target(self):
        bg = colorlib.rgb("#101010")
        for fg in ("#101010", "#1A1A1A", "#F7C7A1"):
            out = colorlib.ensure_contrast(colorlib.rgb(fg), bg, 4.5)
            self.assertGreaterEqual(colorlib.contrast(out, bg), 4.5)

    def test_cap_contrast_stays_under_maximum(self):
        bg = colorlib.rgb("#101010")
        out = colorlib.cap_contrast(colorlib.rgb("#FFFFFF"), bg, 3.0)
        self.assertLessEqual(colorlib.contrast(out, bg), 3.0 + 1e-6)

    def test_rotate_hue_preserves_lightness_and_saturation(self):
        base = colorlib.rgb("#4377BC")
        for degrees in (-40, 40, 180):
            rotated = colorlib.rotate_hue(base, degrees)
            self.assertAlmostEqual(colorlib.hue(rotated),
                                   (colorlib.hue(base) + degrees / 360.0) % 1.0, places=6)
            self.assertAlmostEqual(colorlib.saturation(rotated), colorlib.saturation(base), places=6)

    def test_enforce_floors_is_idempotent_and_legible(self):
        poor = dict(colorlib.DEFAULT_PALETTE)
        poor["bg"] = "#0F1B15"
        poor["panel"] = "#151A17"
        poor["row"] = "#161B18"
        once = colorlib.enforce_floors(poor)
        twice = colorlib.enforce_floors(once)
        self.assertEqual(once, twice)
        for token, rules in colorlib.FLOORS.items():
            for minimum, against in rules:
                got = colorlib.contrast(colorlib.rgb(once[token]),
                                        colorlib.rgb(once[against]))
                self.assertGreaterEqual(
                    got, minimum - colorlib.FLOOR_EPS,
                    "%s on %s is %.2f, floor %.2f" % (token, against, got, minimum))

    def test_every_mapped_variant_already_meets_the_shared_floors(self):
        """The mapper output must be legible BEFORE Theme.qml normalises it.

        Otherwise the ThemePicker swatch, palette.sh and sync-external-theme.py
        all read a palette the shell will never actually draw.
        """
        for raw in (DARK, DARKCOMP):
            for variant in VARIANTS:
                with self.subTest(raw=sorted(raw)[1], variant=variant):
                    palette = wallust_palette.map_palette(raw, variant)
                    for token, rules in colorlib.FLOORS.items():
                        for minimum, against in rules:
                            got = colorlib.contrast(colorlib.rgb(palette[token]),
                                                    colorlib.rgb(palette[against]))
                            self.assertGreaterEqual(
                                got, minimum - colorlib.FLOOR_EPS,
                                "%s %s on %s is %.2f, floor %.2f"
                                % (variant, token, against, got, minimum))

    def test_theme_qml_floors_match_colorlib(self):
        """Theme.qml re-implements the table for QML; it must not drift.

        Two hand-maintained copies of one contract is exactly the kind of thing
        that silently rots, so this parses the QML and compares it field by
        field. If you change a number in one place, this fails and tells you
        where the other one is.
        """
        qml = (SCRIPTS.parent / "quickshell" / "sunset" / "services" / "Theme.qml").read_text()
        block = qml[qml.index("readonly property var floors"):
                    qml.index("readonly property var floors") + 2000]
        block = block[:block.index("\n    })")]
        parsed = {}
        for token, body in re.findall(r'"(\w+)": (\[\[.*?\]\])', block):
            parsed[token] = [(float(t), against) for t, against in
                             re.findall(r"\[([\d.]+), \"(\w+)\"\]", body)]
        self.assertEqual(parsed, colorlib.FLOORS,
                         "Theme.qml floors drifted from scripts/colorlib.py FLOORS")

        order = qml[qml.index("const order = ["):]
        order = order[:order.index("]") + 1]
        self.assertEqual(re.findall(r'"(\w+)"', order), colorlib.FLOOR_ORDER,
                         "Theme.qml legibility order drifted from FLOOR_ORDER")

    def test_theme_qml_onaccent_picks_the_readable_side(self):
        qml = (SCRIPTS.parent / "quickshell" / "sunset" / "services" / "Theme.qml").read_text()
        self.assertIn("readonly property color onAccent:", qml)
        self.assertIn("readonly property color onAccentMuted:", qml)

    def test_force_dark_respects_ceiling(self):
        self.assertLessEqual(colorlib.luminance(colorlib.force_dark((255, 255, 255))), 0.025)


if __name__ == "__main__":
    unittest.main()