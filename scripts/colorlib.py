"""Colour maths shared by the theme producers.

Two scripts need the same primitives and must agree on them:

  * scripts/wallust-palette.py  — turns a wallust palette into the 11 taste.md
    tokens for a wallpaper-derived Theme.qml palette.
  * scripts/sync-external-theme.py — turns the ACTIVE 11 tokens into the derived
    colours other programs need (16 ANSI slots for alacritty/tmux, rgba() strings
    for CSS, focus-ring gradients for niri).

Keeping one implementation here means a palette that passed the contrast
targets in the wallust mapper also satisfies them once it reaches a terminal.

Everything works on 0-255 float RGB triples; `rgb()`/`hex_color()` convert at
the edges. Contrast handling is WCAG relative-luminance based, with the same
+0.08 slack the shell theme used, so "readable" means the same thing to both
sides.
"""

import colorsys
import math

# The 11 taste.md tokens, in the order services/Theme.qml publishes them.
KEYS = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover",
        "text", "muted", "dim", "danger"]

# Last-resort palette: taste.md Sunset Orange AMOLED. Used only when no palette
# can be read at all (first run, before quickshell ever published one).
DEFAULT_PALETTE = {
    "bg": "#000000",
    "panel": "#0A0A0A",
    "row": "#141010",
    "border": "#1A1210",
    "borderStrong": "#3D2B24",
    "accent": "#E85D2F",
    "accentHover": "#FF8B4A",
    "text": "#F7C7A1",
    "muted": "#7C8A6A",
    "dim": "#555555",
    "danger": "#C30505",
}


# The legibility contract. One source of truth for the whole repo.
#
# Each entry is a token -> list of (minimum contrast ratio, the token it is drawn
# on). Every producer (scripts/wallust-palette.py) and the shell itself
# (services/Theme.qml `floors`) must enforce exactly this table, so a wallpaper,
# a hand-written palette and the custom editor are all held to the same standard.
#
# scripts/test_colorlib.py parses Theme.qml and asserts the two never drift.
#
#   7.0  body / primary text
#   4.5  WCAG AA for normal text: accent fills, danger, secondary text
#   3.0  genuinely secondary text, and strong borders
#   ~1.3 the job is only to make one surface distinguishable from another
FLOORS = {
    "text": [(7.0, "bg")],
    "accent": [(4.5, "bg")],
    "accentHover": [(7.0, "bg")],
    "danger": [(4.5, "bg")],
    "muted": [(4.5, "bg"), (3.0, "panel")],
    "dim": [(3.5, "bg"), (3.0, "panel")],
    "panel": [(1.30, "bg")],
    "row": [(1.60, "bg"), (1.12, "panel")],
    "border": [(1.25, "bg")],
    "borderStrong": [(2.50, "panel")],
}

# Surfaces first (they are what the text colours get measured against), then the
# text colours. Getting this wrong lets a colour be pushed against a background
# that is itself about to move.
FLOOR_ORDER = ["panel", "row", "border", "borderStrong", "text",
               "accent", "accentHover", "danger", "muted", "dim"]

# Contrast is a float; a floor that lands a hundredth under its target is not a
# defect any display can show, and chasing it can make a push unsatisfiable.
FLOOR_EPS = 0.005


def enforce_floors(palette):
    """Return `palette` with every token in FLOORS pushed up to its minimum.

    Idempotent, and safe on any palette shaped like the 11 tokens. This is the
    Python twin of Theme.qml's legibility(): same table, same order, same
    "push toward whichever of black/white has headroom" rule.
    """
    out = dict(palette)
    for token in FLOOR_ORDER:
        rules = FLOORS.get(token)
        if not rules:
            continue
        color = rgb(out[token])
        for minimum, against in rules:
            color = ensure_contrast(color, rgb(out[against]), minimum)
        out[token] = hex_color(color)
    return out


def rgb(value):
    """'#rrggbb' | 'rrggbb' | '#rgb' -> (r, g, b) 0-255 floats."""
    value = str(value).strip().lstrip("#")
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    if len(value) != 6:
        raise ValueError("expected a six-digit color")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def hex_color(color):
    return "#" + "".join(f"{max(0, min(255, round(channel))):02X}" for channel in color)


def css_rgb(color):
    """'#rrggbb' for CSS/canvas consumers (lowercase is fine, upper kept here)."""
    return hex_color(color)


def blend(first, second, amount):
    return tuple(a + (b - a) * amount for a, b in zip(first, second))


def lighten(color, amount):
    """Mix toward white. The "bright ANSI" move."""
    return blend(color, (255, 255, 255), amount)


def darken(color, amount):
    return blend(color, (0, 0, 0), amount)


def luminance(color):
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
              for c in (v / 255 for v in color)]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(first, second):
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def ensure_contrast(foreground, background, minimum):
    """Push `foreground` away from `background` until it clears `minimum`.

    Toward black or toward white, whichever side has more headroom, so the
    result keeps its hue instead of being washed out toward the other pole.
    """
    minimum += 0.08
    if contrast(foreground, background) >= minimum:
        return foreground
    target = (0, 0, 0) if luminance(background) > 0.45 else (255, 255, 255)
    low, high = 0.0, 1.0
    for _ in range(24):
        mid = (low + high) / 2
        candidate = blend(foreground, target, mid)
        if contrast(candidate, background) >= minimum:
            high = mid
        else:
            low = mid
    return blend(foreground, target, high)


def cap_contrast(foreground, background, maximum):
    """Pull `foreground` toward `background` until it stops exceeding `maximum`.

    Used for muted/dim text, which has to read as *secondary*: clearing a floor
    is not enough, it also must not compete with body text.
    """
    if contrast(foreground, background) <= maximum:
        return foreground
    low, high = 0.0, 1.0
    for _ in range(24):
        mid = (low + high) / 2
        candidate = blend(foreground, background, mid)
        if contrast(candidate, background) > maximum:
            low = mid
        else:
            high = mid
    return blend(foreground, background, high)


def saturation(color):
    return colorsys.rgb_to_hls(*(channel / 255 for channel in color))[2]


def hue(color):
    return colorsys.rgb_to_hls(*(channel / 255 for channel in color))[0]


def hls_color(h, l, s):
    return tuple(channel * 255 for channel in colorsys.hls_to_rgb(h % 1.0, l, s))


def rotate_hue(color, degrees):
    """Same colour, hue shifted. Used to synthesise ANSI hues that have no token."""
    h, l, s = colorsys.rgb_to_hls(*(channel / 255 for channel in color))
    return hls_color(h + degrees / 360.0, l, s)


def force_dark(color, ceiling=0.025):
    """Scale a colour toward black until its luminance is under `ceiling`."""
    low, high = 0.0, 1.0
    for _ in range(24):
        scale = (low + high) / 2
        if luminance(tuple(channel * scale for channel in color)) > ceiling:
            high = scale
        else:
            low = scale
    return tuple(channel * low for channel in color)


def grey_at(level):
    """The achromatic colour with exactly `level` relative luminance.

    An sRGB grey always has R == G == B, so this is the inverse of
    `luminance()` for that special case: the accent's weight with none of its
    hue. Used as the anchor for the icon ramp.
    """
    linear = level
    encoded = 12.92 * linear if linear <= 0.0031308 else 1.055 * (linear ** (1 / 2.4)) - 0.055
    channel = max(0, min(255, math.floor(encoded * 255 + 0.5)))
    return (channel, channel, channel)


def _round8(color):
    """Round to 8-bit, half-up.

    Not `hex_color()`: that rounds half-to-even, and the icon ramp's binary
    searches land on .5 boundaries often enough for the two rules to disagree
    on the last bit. Theme.qml uses Math.floor(v + 0.5), so this does too.
    """
    return tuple(max(0, min(255, math.floor(channel + 0.5))) for channel in color)


# The neutral chrome ramp. These three constants are the whole taste knob for
# icon colour and are duplicated verbatim in services/Theme.qml
# (`iconTint` / `iconRatio` / `iconMutedRatio`), and scripts/test_icon_colors.py
# runs Theme.qml's real functions under node against this module's, failing on
# any 8-bit disagreement. It has to: QML paints the launcher's Nerd Font glyphs
# and this paints the stroke SVGs, and those two kinds of icon appear in the same
# list one row apart, so a drift shows up as two greys in one column.
ICON_TINT = 0.22
ICON_RATIO = 4.5
ICON_MUTED_RATIO = 3.5


def neutral_icon(palette, ratio=ICON_RATIO):
    """The neutral icon colour for `palette`: accent-tinted grey, pinned to `ratio`.

    Why this is derived instead of being two more palette keys: the stroke icon
    set is monochrome SVG with no runtime tint, so an icon colour has to be
    computed by whoever writes the files -- and the accent only carries a 4.5
    floor, so a wallpaper accent can put it anywhere. Pinning the *result* to a
    contrast ratio against `bg` is what keeps an icon from being invisible on
    one wallpaper and blinding on the next, and it means the 11-key palette
    contract (palette.sh, tmux, alacritty, niri, the guide) is untouched.

    Three steps, mirrored by Theme.qml `_pinIcon`:

      1. anchor  `grey_at(luminance(accent))` -- the accent's weight, no hue, so
         the tint cannot change how heavy the glyph looks
      2. tint    ICON_TINT of the accent mixed back in, so the palette stays
         recognisable without any icon reading as "coloured"
      3. pin     exactly `ratio` against `bg`, both directions: pushed AWAY if
         too quiet, pulled TOWARD bg if too loud. Step 3 has to be able to pull
         as well as push, which is why this does not reuse `ensure_contrast()`
         (that only pushes) or `cap_contrast()` (that does not round inside the
         search, so it can settle a channel just under the target).

    Every binary search below tests the ROUNDED 8-bit value, not the float:
    searching the float and rounding afterwards lands a hundredth under the
    target and then plateaus, which is the same bug that let the accent publish
    at 4.49:1 against a 4.50 floor.
    """
    bg = rgb(palette["bg"])
    accent = rgb(palette["accent"])
    goal = ratio - FLOOR_EPS

    color = blend(grey_at(luminance(accent)), accent, ICON_TINT)
    if contrast(color, bg) < goal:
        target = (0, 0, 0) if luminance(bg) > 0.18 else (255, 255, 255)
        low, high = 0.0, 1.0
        for _ in range(24):
            mid = (low + high) / 2
            candidate = _round8(blend(color, target, mid))
            if contrast(candidate, bg) >= goal:
                high = mid
            else:
                low = mid
        color = _round8(blend(color, target, high))

    # Pull the surplus back toward bg until the result is the QUIETEST colour
    # that still clears `ratio`. `_push` above can only make an icon louder,
    # never quieter, so without this the ramp would be "as loud as the accent
    # happened to be" instead of two chosen weights.
    #
    # The predicate is ">= goal", not "<= ratio", and that is the whole subtlety:
    # contrast is only reachable in 8-bit steps, so aiming for "<= ratio" settles
    # on the last rung BELOW the floor (4.487:1 for a 4.5 floor on this palette)
    # -- an icon that is meant to be guaranteed readable failing its own
    # guarantee by a rounding step. Aiming for ">= goal" takes the quietest rung
    # that clears instead, 4.51:1, which is the intent. `hi` and no
    # "keep whichever is better" fallback: at(0) already clears, so the search
    # converges on the smallest mix rather than collapsing to bg (that fallback's
    # comparison is always true, and it would paint every icon the background).
    # The answer is `low`, not `high`: `low` is the smallest mix still known to
    # clear, and `high` is the largest known to miss -- which is the rung UNDER
    # the floor, i.e. exactly the value this search exists to avoid.
    if contrast(color, bg) > ratio + FLOOR_EPS:
        low, high = 0.0, 1.0
        for _ in range(24):
            mid = (low + high) / 2
            candidate = _round8(blend(color, bg, mid))
            if contrast(candidate, bg) >= goal:
                low = mid
            else:
                high = mid
        color = _round8(blend(color, bg, low))

    return hex_color(color)


def icon_colors(palette):
    """{'icon': ..., 'iconMuted': ...} for sync-external-theme.py's icon roles."""
    return {"icon": neutral_icon(palette, ICON_RATIO),
            "iconMuted": neutral_icon(palette, ICON_MUTED_RATIO)}


def is_valid_palette(palette):
    """True when `palette` carries every token as a bare 6-digit hex.

    This is the same contract Theme.qml's applyWallpaperJson enforces, so a
    palette accepted here is one the shell would also accept.
    """
    if not isinstance(palette, dict):
        return False
    for key in KEYS:
        value = palette.get(key)
        if not isinstance(value, str) or not value.startswith("#") or len(value) != 7:
            return False
        try:
            int(value[1:], 16)
        except ValueError:
            return False
    return True


def complete(palette):
    """Fill any missing token from DEFAULT_PALETTE, keeping what is present."""
    filled = dict(DEFAULT_PALETTE)
    if isinstance(palette, dict):
        for key in KEYS:
            value = palette.get(key)
            if isinstance(value, str) and len(value) == 7 and value.startswith("#"):
                try:
                    int(value[1:], 16)
                    filled[key] = value
                except ValueError:
                    pass
    return filled