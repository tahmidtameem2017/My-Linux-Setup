import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("sync-fastfetch-theme.py")
SPEC = importlib.util.spec_from_file_location("sync_fastfetch_theme", MODULE_PATH)
sync_fastfetch_theme = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_fastfetch_theme)

PALETTE = {
    "bg": "#101010",
    "panel": "#181818",
    "row": "#202020",
    "border": "#282828",
    "borderStrong": "#383838",
    "accent": "#D06040",
    "accentHover": "#F08060",
    "text": "#F0D0B0",
    "muted": "#A09070",
    "dim": "#706050",
    "danger": "#D04040",
}


class FastfetchThemeTests(unittest.TestCase):
    def test_template_renders_valid_fastfetch_json(self):
        template = (Path(__file__).parents[1] / "fastfetch" / "config.jsonc.in").read_text()
        rendered = sync_fastfetch_theme.render(template, PALETTE)
        config = json.loads(rendered)
        self.assertEqual(config["logo"]["color"]["1"], PALETTE["accent"])
        self.assertEqual(config["display"]["color"]["title"], PALETTE["text"])
        self.assertEqual(config["display"]["color"]["separator"], PALETTE["muted"])
        self.assertEqual(config["modules"][0], "break")
        self.assertEqual(config["modules"][1]["keyColor"], PALETTE["accent"])
        self.assertEqual(config["modules"][4]["keyColor"], PALETTE["accentHover"])
        self.assertEqual(config["modules"][5]["keyColor"], PALETTE["muted"])

    def test_rejects_missing_or_malformed_palette_tokens(self):
        template = "{\"accent\": \"{{ACCENT}}\"}"
        invalid = dict(PALETTE)
        invalid["danger"] = "red"
        with self.assertRaises(ValueError):
            sync_fastfetch_theme.render(template, invalid)
        del invalid["danger"]
        with self.assertRaises(ValueError):
            sync_fastfetch_theme.render(template, invalid)


if __name__ == "__main__":
    unittest.main()
