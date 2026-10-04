#!/usr/bin/env python3
"""Map a raw wallust palette onto the 11 taste.md theme tokens.

    wallust-palette.py <variant> <raw.json> <output.json>

<variant> is one of dark / darkcomp / softdark / light and only applies a small
tone nudge on top of the wallust palette. The real hue diversity between the
four wallpaper themes comes from which wallust palette scripts/wallust-theme.sh
asks wallust for, not from here — this module stays a pure mapper so both the
naming and the distinctness can be reasoned about in one place.

Mapping (wallust -> token), all on the colour space wallust handed us:

    background                 -> bg            page / bar background
    color0                     -> panel         cards
    color0 lifted toward fg    -> row           buttons / list rows
    background lifted          -> border        faint borders / slider tracks
    color8 deepened toward bg  -> borderStrong  card / button borders
    most-saturated color1..6   -> accent        primary actions / selected row
    accent lifted toward fg    -> accentHover   hover text / highlights
    foreground                 -> text          body text
    color8 (lifted if too dark)-> muted         secondary text
    color8 deepened toward bg  -> dim           disabled / placeholder
    fixed red, contrast-fitted -> danger        destructive accents

Every token that ends up carrying meaning is run through ensure_contrast /
cap_contrast so a wallpaper can never produce unreadable UI.
"""

import colorsys
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from colorlib import (  # noqa: E402
    FLOORS, KEYS, blend, cap_contrast, contrast, enforce_floors, ensure_contrast,
    force_dark, hex_color, hls_color, rgb, saturation,
)

# Per-variant tone nudge. Applied AFTER wallust chose the hue, so the four
# wallpaper themes are distinct by hue family (wallust's dark / darkcomp /
# softdark / light) and additionally separated in weight here.
VARIANT_TONE = {
    "dark": (1.00, 0.00),   # vivid base tone, as extracted
    "darkcomp": (1.18, 0.03),  # brighter, more saturated
    "softdark": (0.45, 0.00),  # same hue, desaturated to a muted pastel
    "light": (0.70, 0.09),  # lighter accent tint on dark surfaces
}


def map_palette(raw, variant):
    if variant not in VARIANT_TONE:
        raise ValueError("unknown wallpaper variant")

    def source(key, fallback):
        try:
            return rgb(raw.get(key, fallback))
        except (ValueError, TypeError, AttributeError):
            return rgb(fallback)

    bg = source("background", "#000000")
    foreground = source("foreground", "#F7C7A1")
    panel_source = source("color0", "#0A0A0A")
    muted_source = source("color8", "#7C8A6A")
    candidates = [source("color%d" % i, "#E85D2F") for i in range(1, 7)]
    base_accent = max(candidates, key=lambda color: (saturation(color),))
    hue, base_lightness, base_saturation = colorsys.rgb_to_hls(
        *(channel / 255 for channel in base_accent))

    # Keep the wallpaper's background hue but force every variant into dark mode.
    # wallust's softdark/light palettes deliberately return a LIGHT background;
    # the shell is a dark UI, so the bg is scaled down and only its hue survives.
    bg = force_dark(bg)

    saturation_scale, lightness_delta = VARIANT_TONE[variant]
    accent = hls_color(hue, max(0.24, min(0.70, base_lightness + lightness_delta)),
                       min(0.82, base_saturation * saturation_scale))
    accent = ensure_contrast(accent, bg, 3.0)
    accent_hue, accent_lightness, accent_saturation = colorsys.rgb_to_hls(
        *(channel / 255 for channel in accent))
    accent_hover = ensure_contrast(
        hls_color(accent_hue, min(0.82, accent_lightness + 0.18),
                  min(0.88, accent_saturation)), bg, 3.0)

    # Surfaces stay neutral and consistently dark: the wallpaper only ever
    # shows through as a hue tint, never as a literal colour, because every
    # surface has to keep text readable on it.
    foreground = ensure_contrast(foreground, bg, 4.5)
    panel = blend(bg, panel_source, 0.28)
    panel = cap_contrast(panel, bg, 1.45)
    row = ensure_contrast(blend(panel, (255, 255, 255), 0.045), panel, 1.08)
    border = ensure_contrast(blend(bg, (255, 255, 255), 0.13), bg, 1.35)
    border_strong = ensure_contrast(blend(panel, (255, 255, 255), 0.30), panel, 2.0)
    text = ensure_contrast(foreground, bg, 4.5)
    muted = ensure_contrast(blend(muted_source, text, 0.16), bg, 3.0)
    muted = cap_contrast(muted, bg, min(4.1, contrast(rgb(hex_color(text)), bg) - 0.45))
    dim = ensure_contrast(blend(muted_source, bg, 0.46), bg, 2.0)
    danger = ensure_contrast((220, 48, 48), bg, 3.0)

    theme = {
        "bg": hex_color(bg),
        "panel": hex_color(panel),
        "row": hex_color(row),
        "border": hex_color(border),
        "borderStrong": hex_color(border_strong),
        "accent": hex_color(accent),
        "accentHover": hex_color(accent_hover),
        "text": hex_color(text),
        "muted": hex_color(muted),
        "dim": hex_color(dim),
        "danger": hex_color(danger),
    }
    if set(theme) != set(KEYS):
        raise ValueError("palette schema mismatch")

    # The per-token numbers above are the *tuning* (how vivid, how muted); this
    # is the *contract*. They disagree on purpose: tuning picks a colour, the
    # floors decide whether you are allowed to ship it. Enforcing the shared
    # table here means the file on disk is already legible, so the ThemePicker
    # swatches, palette.sh and sync-external-theme.py are all reading the same
    # numbers the shell will end up drawing. Theme.qml re-runs the identical
    # table as a safety net for the hand-written palettes.
    theme = enforce_floors(theme)
    return theme



def main(argv):
    if len(argv) != 4:
        raise SystemExit("usage: wallust-palette.py <dark|darkcomp|softdark|light> <raw.json> <output.json>")
    variant, raw_path, output_path = argv[1:]
    raw = json.loads(Path(raw_path).read_text())
    theme = map_palette(raw, variant)
    target = Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w") as output:
        json.dump(theme, output, indent=2)
        output.write("\n")
        output.flush()
    print(json.dumps({"accent": theme["accent"], "bg": theme["bg"]}))


if __name__ == "__main__":
    main(sys.argv)