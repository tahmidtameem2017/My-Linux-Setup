#!/usr/bin/env python3
"""Push the active sunset palette out to everything that has no palette of its own.

    sync-external-theme.py --palette '<json>'
    sync-external-theme.py                 # read the published palette instead

services/Theme.qml owns the palette and already publishes it to
~/.local/share/niri-setup/active-theme.json. That covers quickshell, and
scripts/swaylock*.sh + scripts/palette.sh which read it back. It does NOT cover
the programs that were carrying a hand-copied copy of the sunset hexes:

  tmux/theme.conf        status bar, pane borders, popups, 16 pane-colours
  alacritty/*.toml       terminal fg/bg/cursor + the 16 ANSI slots, BOTH profiles
  niri/layout.kdl        focus ring + tab indicator (compositor)
  help/theme.css         the HTML guide (Mod+Alt+H)

Each target is rendered and written ONLY when its bytes actually change, so a
palette that barely moved costs four stat()s and nothing else. `niri` is named
on stdout only when the compositor file changed, which is the shell's cue to
hot-reload: load-config-file is a whole-config operation and must not fire for a
no-op repaint.

The 16 ANSI slots have no taste.md tokens of their own, so they are DERIVED from
the palette (see derive_ansi). The three hues the theme does not name — blue,
magenta, cyan — come from rotating the accent, which keeps the terminal's colour
output in the same family as the shell instead of freezing stale literals.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from colorlib import (  # noqa: E402
    complete, contrast, ensure_contrast, hex_color, icon_colors, is_valid_palette,
    lighten, rgb, rotate_hue,
)

# Minimum contrast every generated ANSI slot must clear against bg, so
# `ls --color` output stays readable whatever the wallpaper did.
ANSI_MIN_CONTRAST = 3.0


# --------------------------------------------------------------------------
# palette input
# --------------------------------------------------------------------------

def read_published_palette(setup_home, theme_dir):
    """active-theme.json first, then `palette.sh get`, then the baked defaults.

    Same order scripts/palette.sh itself uses, so the shell and its exported
    copies can never disagree about what "the active palette" means. Both
    sources are run through complete(), so a hand-mangled or half-written file
    degrades token-by-token to the sunset defaults instead of being discarded
    whole.
    """
    published = Path(theme_dir) / "active-theme.json"
    if published.is_file():
        try:
            data = json.loads(published.read_text())
            if isinstance(data, dict):
                return complete(data)
        except (ValueError, OSError):
            pass

    script = Path(setup_home) / "scripts" / "palette.sh"
    try:
        out = subprocess.run([str(script), "get"], capture_output=True, text=True,
                             timeout=15, check=False).stdout
        parsed = {}
        for line in out.splitlines():
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            parsed[key.strip()] = "#" + value.strip().lstrip("#")
        if parsed:
            return complete(parsed)
    except (OSError, subprocess.SubprocessError):
        pass

    return complete(None)


# --------------------------------------------------------------------------
# derived colours
# --------------------------------------------------------------------------

def derive_ansi(palette):
    """16 ANSI slots + cursor colours from the 11 theme tokens.

    Slots that have a token use it directly. blue/magenta/cyan are hue rotations
    of the accent, so they are guaranteed to be in the palette's family and to
    differ from each other no matter what the wallpaper was. Every slot is then
    contrast-fitted against bg, because a wallpaper-derived accent can be
    arbitrarily dark and an unreadable ANSI slot is worse than an ugly one.
    """
    bg = rgb(palette["bg"])
    accent = rgb(palette["accent"])

    def fit(value, minimum=ANSI_MIN_CONTRAST):
        # Slots are a mix of palette tokens (hex strings) and derived rotations
        # (rgb triples); normalise before measuring.
        color = rgb(value) if isinstance(value, str) else tuple(value)
        return hex_color(ensure_contrast(color, bg, minimum))

    slots = {
        "N_BLACK": palette["border"],
        "N_RED": palette["accent"],
        "N_GREEN": palette["muted"],
        "N_YELLOW": palette["accentHover"],
        "N_BLUE": rotate_hue(accent, 180),
        "N_MAGENTA": rotate_hue(accent, -60),
        "N_CYAN": rotate_hue(accent, 60),
        "N_WHITE": palette["text"],
        "B_BLACK": palette["borderStrong"],
        "B_RED": lighten(accent, 0.22),
        "B_GREEN": lighten(rgb(palette["muted"]), 0.22),
        "B_YELLOW": lighten(rgb(palette["accentHover"]), 0.18),
        "B_BLUE": lighten(rotate_hue(accent, 180), 0.22),
        "B_MAGENTA": lighten(rotate_hue(accent, -60), 0.22),
        "B_CYAN": lighten(rotate_hue(accent, 60), 0.22),
        "B_WHITE": lighten(rgb(palette["text"]), 0.35),
    }

    out = {name: fit(value) for name, value in slots.items()}
    # Body text is held to the stricter 4.5 it already meets as Theme.text.
    out["N_WHITE"] = fit(slots["N_WHITE"], 4.5)
    # Cursor text is deliberately NOT contrast-fitted against bg: it is the
    # colour of the character sitting inside the accent-coloured cursor, so
    # matching bg is the point.
    out["CURSOR_TEXT"] = hex_color(bg)
    out["CURSOR"] = fit(accent, 3.0)
    return out


def hex_triplet(color):
    """'#rrggbb' -> 'r,g,b' for CSS rgba()."""
    r, g, b = rgb(color)
    return "%d, %d, %d" % (round(r), round(g), round(b))


# --------------------------------------------------------------------------
# targets
# --------------------------------------------------------------------------

TMUX_HEADER = """\
# tmux theme — GENERATED FILE, do not edit.
#
# Written by scripts/sync-external-theme.py from the palette quickshell has
# active (services/Theme.qml -> ~/.local/share/niri-setup/active-theme.json).
# Source of truth for the colours is services/Theme.qml; edit the palette there
# or pick a theme in ThemePicker, never here. Re-sourcing tmux.conf (prefix + r)
# picks the current values up. If this file is missing, tmux.conf sources it
# with -q and simply keeps its own defaults.
#
# pane-colours is an array option in tmux 3.7 and can only be written one index
# at a time, so it is unset first: without that, every prefix + r would append
# another 16 entries.
setw -gu pane-colours
"""

# The tab-search glyph, U+F02A (Nerd Font private use). Substituted as a
# placeholder rather than written inline: this is a normal Python string, so a
# literal \U escape here would be parsed by Python rather than passed through,
# and an escape written for tmux ("\u{f02a}") is a hard parse error there.
TMUX_SEARCH_GLYPH = chr(0xF02A)

TMUX_BODY = """
# ── 16 ANSI slots (inherited by panes; mirrors alacritty/*.toml) ───────────
setw -g pane-colours[0] "{N_BLACK}"
setw -g pane-colours[1] "{N_RED}"
setw -g pane-colours[2] "{N_GREEN}"
setw -g pane-colours[3] "{N_YELLOW}"
setw -g pane-colours[4] "{N_BLUE}"
setw -g pane-colours[5] "{N_MAGENTA}"
setw -g pane-colours[6] "{N_CYAN}"
setw -g pane-colours[7] "{N_WHITE}"
setw -g pane-colours[8] "{B_BLACK}"
setw -g pane-colours[9] "{B_RED}"
setw -g pane-colours[10] "{B_GREEN}"
setw -g pane-colours[11] "{B_YELLOW}"
setw -g pane-colours[12] "{B_BLUE}"
setw -g pane-colours[13] "{B_MAGENTA}"
setw -g pane-colours[14] "{B_CYAN}"
setw -g pane-colours[15] "{B_WHITE}"

# ── status bar ──────────────────────────────────────────────────────────────
# No band: status-style keeps bg=default so the bar sits on the terminal's own
# background and is as translucent as the window (alacritty opacity).
set -g status-style "bg=default fg={dim}"
# The search glyph is U+F02A, written out literally: tmux's config parser
# rejects the `\\u{{...}}` escape ("invalid \\u argument") and STOPS at the first
# error, which silently discarded every line after it. A literal Nerd Font
# private-use codepoint is what tmux.conf always carried.
set -g status-left "#[fg={muted}]{searchGlyph}#[default] #[fg={muted}]#S#[default] "
set -g status-right " #[fg={muted}]+#[default]"   # search + new-window affordances

setw -g window-status-format "#[fg={dim}]#I:#W"
setw -g window-status-current-format "#[fg={accent}]#I:#W"
setw -g window-status-separator "#[fg={border}] · #[default]"
setw -g window-status-activity-style "fg={accentHover},bold"
setw -g window-status-bell-style "fg={danger},bold"
setw -g window-status-last-style "fg={dim}"
setw -g window-status-style "fg={muted}"

# ── pane borders ────────────────────────────────────────────────────────────
set -g pane-border-style "fg={border}"
set -g pane-active-border-style "fg={borderStrong}"

# ── popups (cheat sheet), messages, copy-mode indicator ─────────────────────
set -g message-style "bg={panel} fg={text}"
set -g mode-style "bg={accent} fg={bg} bold"
setw -g popup-style "bg={panel} fg={text}"
setw -g popup-border-style "fg={borderStrong}"
"""

# niri layout.kdl: only the focus ring and the tab indicator carry theme
# colours, and both live inside these two nodes.
NIRI_NODES = ("focus-ring", "tab-indicator")
NIRI_GRADIENT = re.compile(
    r'(?P<indent>\s*)active-gradient\s+from="[^"]*"\s+to="[^"]*"(?P<tail>\s+angle=\d+)')
NIRI_COLOR = re.compile(r'(?P<indent>\s*)(?P<name>active-color|inactive-color)\s+"[^"]*"')
# The layout background is the workspace showing through window gaps. Same
# treatment as the ring: it is a theme surface, not a compositor constant.
NIRI_BACKGROUND = re.compile(r'(?P<indent>\s*)background-color\s+"[^"]*"')


def render_tmux(palette, ansi):
    body = TMUX_BODY.format(searchGlyph=TMUX_SEARCH_GLYPH,
                            dim=palette["dim"], muted=palette["muted"],
                            accent=palette["accent"], accentHover=palette["accentHover"],
                            danger=palette["danger"], border=palette["border"],
                            borderStrong=palette["borderStrong"], panel=palette["panel"],
                            text=palette["text"], bg=palette["bg"], **ansi)
    return TMUX_HEADER + body


def render_help_css(palette):
    """The 11 tokens plus the drifted extras help/index.html had hand-picked.

    help/index.html grew its own vocabulary (--bg-soft, --panel-warm, --olive,
    --text-2, …) whose values had drifted away from taste.md. Those are derived
    here instead, as fixed mixes of the tokens, so they can never drift again.
    """
    bg = rgb(palette["bg"])
    text = rgb(palette["text"])
    muted = rgb(palette["muted"])
    accent = rgb(palette["accent"])

    def mix(share):
        return hex_color(ensure_contrast(
            tuple(c + (text[i] - c) * share for i, c in enumerate(bg)), bg, 1.0))

    return """\
/* GENERATED FILE, do not edit.
 *
 * Written by scripts/sync-external-theme.py from the palette quickshell has
 * active (services/Theme.qml). Re-run it (or switch theme / change wallpaper)
 * and reload the page. If it is missing the pages fall back to their inlined
 * :root block, which is the sunset palette.
 *
 * The first block is the 11 taste.md tokens. The second re-derives the extra
 * names help/index.html invented, which used to be hand-picked and had drifted
 * out of sync with taste.md (a different --panel, --line and --text).
 */

:root {
  --bg: %(bg)s;
  --panel: %(panel)s;
  --row: %(row)s;
  --border: %(border)s;
  --border-strong: %(borderStrong)s;
  --accent: %(accent)s;
  --accent-hover: %(accentHover)s;
  --text: %(text)s;
  --muted: %(muted)s;
  --dim: %(dim)s;
  --danger: %(danger)s;

  --accent-rgb: %(accentRgb)s;
  --text-rgb: %(textRgb)s;
  --muted-rgb: %(mutedRgb)s;
  --olive-rgb: %(oliveRgb)s;
}

:root {
  /* index.html vocabulary, derived from the tokens above. */
  --bg-soft: %(bgSoft)s;
  --panel-warm: %(panelWarm)s;
  --line: %(line)s;
  --line-strong: %(lineStrong)s;
  --olive: %(olive)s;
  --olive-dim: rgba(%(oliveRgb)s, 0.16);
  --text-hi: %(textHi)s;
  --text-2: %(text2)s;
  --text-3: %(text3)s;
}
""" % {
        "bg": palette["bg"], "panel": palette["panel"], "row": palette["row"],
        "border": palette["border"], "borderStrong": palette["borderStrong"],
        "accent": palette["accent"], "accentHover": palette["accentHover"],
        "text": palette["text"], "muted": palette["muted"], "dim": palette["dim"],
        "danger": palette["danger"],
        "accentRgb": hex_triplet(palette["accent"]),
        "textRgb": hex_triplet(palette["text"]),
        "mutedRgb": hex_triplet(palette["muted"]),
        "oliveRgb": hex_triplet(hex_color(lighten(muted, 0.35))),
        "bgSoft": mix(0.03),
        "panelWarm": mix(0.08),
        "line": mix(0.14),
        "lineStrong": mix(0.29),
        "olive": hex_color(lighten(muted, 0.35)),
        "textHi": hex_color(lighten(text, 0.60)),
        "text2": hex_color(tuple(c + (bg[i] - c) * 0.22 for i, c in enumerate(text))),
        "text3": hex_color(tuple(c + (bg[i] - c) * 0.42 for i, c in enumerate(text))),
    }


def render_niri_layout(text, palette):
    """Rewrite only the theme colours in the focus ring, tab indicator and the
    layout background.

    In-place by design, like scripts/wallpaper.sh does for the swaybg line: the
    compositor reads one niri/layout.kdl and there is no include that could carry
    a generated palette, so the colours are substituted where they live. Only the
    named properties are touched, so nothing else in the file can be caught by
    an over-eager substitution.

    A proper node STACK is needed, not a single "current node": `layout {` is
    still the enclosing node for `background-color` even though a dozen sibling
    nodes open and close in between, so a one-slot tracker silently skipped it.
    """
    stack = []
    out = []
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        # A line that closes and opens (`} node {`) nets zero; only a leading
        # `}` pops, and only a trailing `{` pushes.
        closes = 1 if stripped.startswith("}") else 0
        opens = 1 if stripped.endswith("{") else 0
        for _ in range(closes):
            if stack:
                stack.pop()
        node = stack[-1] if stack else None

        if node in NIRI_NODES:
            if "active-gradient" in stripped:
                # accent -> text: the ring fades from the highlight to body text.
                line = NIRI_GRADIENT.sub(
                    lambda m: '%sactive-gradient from="%s" to="%s"%s'
                              % (m.group("indent"), palette["accent"], palette["text"],
                                 m.group("tail")), line)
            else:
                value = palette["accent"] if stripped.startswith("active-color") \
                    else palette["borderStrong"]
                line = NIRI_COLOR.sub(
                    lambda m: '%s%s "%s"' % (m.group("indent"), m.group("name"), value), line)
        elif node == "layout":
            line = NIRI_BACKGROUND.sub(
                lambda m: '%sbackground-color "%s"' % (m.group("indent"), palette["bg"]), line)

        for _ in range(opens):
            stack.append(stripped[:-1].strip() if opens else stripped)
        out.append(line)
    return "".join(out)


def render_template(text, values):
    """Fill {{TOKEN}} placeholders; anything else is passed through untouched."""
    return re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: values.get(m.group(1), m.group(0)), text)


# --------------------------------------------------------------------------
# writing
# --------------------------------------------------------------------------

def write_if_changed(path, content):
    """Write only on a real change. Returns True when the file was rewritten."""
    path = Path(path)
    try:
        if path.is_file() and path.read_text() == content:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    # Staged write + replace: the HTML guide is opened by a browser that may
    # read the stylesheet at any moment, and tmux sources this file mid-session.
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(content)
    os.replace(tmp, path)
    return True


def write_watched(path, content):
    """Write IN PLACE, never staged+renamed. For files quickshell watches.

    quickshell's FileView sits on QFileSystemWatcher, which watches the *inode*.
    The os.replace() above therefore silently kills the watch the first time the
    content really changes: the shell keeps whatever it read at startup and every
    later edit is invisible until it restarts. Truncate+write keeps the inode, at
    the cost of a reader being able to catch a half-written file -- fine for the
    one file written this way (a 10-char directory name that the shell only
    follows to a directory it has just seen fully written).
    """
    path = Path(path)
    try:
        if path.is_file() and path.read_text() == content:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as handle:
        handle.write(content)
    return True


# The stroke icon set is monochrome SVG with its colour baked into every
# `stroke`/`fill` attribute. There is no tint property to bind at runtime
# (quickshell's IconImage has no `color`), so the icons are re-emitted into
# assets/icons/theme/ with the palette substituted.
#
# Classification is by value against the taste.md sunset tokens, so an SVG whose
# stroke was hand-edited to some other theme's accent (the set already carried
# #bd93f9 and #7aa2f7 alongside the sunset hexes) is not silently rewritten into
# the wrong role — an unrecognised colour is left exactly as it is.
#
# Four of those roles collapse onto ONE icon colour on purpose. An icon is
# chrome, not state: while the set mapped accent -> accent and text -> text, the
# bar's own tray read as a row of orange alerts next to the one thing that IS an
# alert (a critical battery), and the bar icon and the same icon in the launcher
# were different colours because the launcher draws a Nerd Font glyph from a QML
# token while the bar draws an SVG baked here. Now both read
# colorlib.neutral_icon(): a grey carrying a slight tint of the palette's accent.
#
# `dim` is the one role that keeps its own step, and that is load-bearing rather
# than decorative: it is the "off" state of both stateful pairs in the set --
# volume.svg/volume-muted.svg and wifi.svg/wifi-off.svg. Collapsing it onto the
# normal step would leave a muted sink and a disconnected link looking identical
# to working ones.
#
# Where an icon's state is drawn by its SHAPE instead, colour is not repeated:
# battery.svg/battery-charging.svg differ by the bolt, and play.svg/pause.svg are
# mutually exclusive, so both pairs correctly collapse to one colour.
ICON_ROLE_BY_SUNSET_HEX = {
    "#E85D2F": "icon",
    "#FF8B4A": "icon",
    "#F7C7A1": "icon",
    "#7C8A6A": "icon",
    "#555555": "iconMuted",
    "#3D2B24": "borderStrong",
    "#000000": "bg",   # the cut-out inside logo.svg, not a stroke
}
ICON_ATTR = re.compile(r'(?P<head>(?:stroke|fill)\s*=\s*")(?P<hex>#[0-9A-Fa-f]{6})(?P<tail>")')


def render_icon(text, palette, derived):
    def swap(match):
        role = ICON_ROLE_BY_SUNSET_HEX.get(match.group("hex").upper())
        if role is None:
            return match.group(0)
        value = derived[role] if role in derived else palette[role]
        return "%s%s%s" % (match.group("head"), value, match.group("tail"))
    return ICON_ATTR.sub(swap, text)


def sync_icons(setup_home, theme_dir, palette):
    """Re-emit assets/icons/*.svg into assets/icons/theme/<fp>/.

    The fingerprinted directory is load-bearing, not decoration: Qt caches a
    decoded image per source URL, so rewriting an SVG in place under the same
    path leaves every IconImage showing the PREVIOUS theme's raster until the
    shell restarts. Hashing the palette into the path changes the URL exactly
    when the bytes change, so Qt reloads only the icons that actually moved.

    Returns True when any icon was written.
    """
    import hashlib

    source_dir = Path(setup_home) / "quickshell" / "sunset" / "assets" / "icons"
    if not source_dir.is_dir():
        return False
    # The derived icon roles go INTO the hash, not just the palette they came
    # from. The palette alone is not enough: the first time this ran, the
    # derivation changed (accent/text/muted all collapsed onto one neutral) with
    # the palette untouched, so the fingerprint stayed put and Qt went on serving
    # the old raster from the same URLs until the shell was restarted. Hashing
    # what is actually painted makes "the path changes exactly when the bytes
    # change" true even when the change is to this script rather than to a theme.
    derived = icon_colors(palette)
    fingerprint = hashlib.sha1(
        json.dumps({**{k: palette[k] for k in sorted(palette)}, **derived},
                   sort_keys=True).encode()).hexdigest()[:10]
    theme_root = source_dir / "theme"
    target_dir = theme_root / fingerprint
    changed = False
    for svg in sorted(source_dir.glob("*.svg")):
        rendered = render_icon(svg.read_text(), palette, derived)
        # An icon with no recognisable stroke is copied verbatim rather than
        # skipped: components fall back to logo.svg on a load error, so every
        # file in the set has to exist under the new directory too.
        if write_if_changed(target_dir / svg.name, rendered):
            changed = True

    # Publish the pointer LAST, once the directory it names is complete, and in
    # place so the shell's watcher survives. Both halves matter: announcing the
    # new name before the SVGs are written makes the shell resolve icons that
    # are not there yet (Image.Error -> blank), and a rename-replace here means
    # the watcher dies on the first theme change and never fires again -- after
    # which Theme.iconDir keeps naming the PREVIOUS directory, which the prune
    # below deletes, and every icon in the shell goes blank until a restart.
    write_watched(Path(theme_dir) / "icon-dir.txt", fingerprint + "\n")

    # Prune superseded fingerprinted directories, otherwise every theme switch
    # would leave a full copy of the icon set behind.
    for stale in theme_root.iterdir() if theme_root.is_dir() else []:
        if stale.is_dir() and stale.name != fingerprint:
            shutil.rmtree(stale, ignore_errors=True)
    return changed


def sync(setup_home, home, palette):
    setup_home = Path(setup_home)
    theme_dir = Path(home) / ".local" / "share" / "niri-setup"
    ansi = derive_ansi(palette)
    values = dict(palette)
    values.update(ansi)
    changed = []

    # tmux: generated next to tmux.conf (which is itself a symlink into the
    # repo), so setup.sh can symlink it the same way it symlinks tmux.conf.
    tmux_conf = setup_home / "tmux" / "theme.conf"
    if write_if_changed(tmux_conf, render_tmux(palette, ansi)):
        changed.append("tmux")

    # alacritty: both profiles are rendered from *.toml.in into the SAME paths
    # the hand-written files used to occupy, so ~/.config/alacritty/alacritty.toml
    # and every `--config-file .../float.toml` caller keep working untouched.
    values["FG"] = palette["text"]
    values["BG"] = palette["bg"]
    for name in ("default", "float"):
        template = setup_home / "alacritty" / ("%s.toml.in" % name)
        if not template.is_file():
            continue
        if write_if_changed(setup_home / "alacritty" / ("%s.toml" % name),
                            render_template(template.read_text(), values)):
            changed.append("alacritty")

    # niri: the repo copy plus the live one. ~/.config/niri/*.kdl are separate
    # files, not symlinks, so editing only the repo copy would leave the running
    # compositor on the old colours until login.
    layout = setup_home / "niri" / "layout.kdl"
    if layout.is_file():
        updated = render_niri_layout(layout.read_text(), palette)
        touched = write_if_changed(layout, updated)
        live = Path(home) / ".config" / "niri" / "layout.kdl"
        if live.is_file():
            live_updated = render_niri_layout(live.read_text(), palette)
            if write_if_changed(live, live_updated):
                touched = True
        if touched:
            changed.append("niri")

    css = setup_home / "help" / "theme.css"
    if write_if_changed(css, render_help_css(palette)):
        changed.append("help")

    if sync_icons(setup_home, theme_dir, palette):
        changed.append("icons")

    return changed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--palette", help="palette JSON; omit to read the published one")
    parser.add_argument("--setup-home", default=os.environ.get("NIRI_SETUP_HOME", str(Path.home() / "niri-setup")))
    parser.add_argument("--home", default=os.environ.get("HOME", str(Path.home())))
    parser.add_argument("--theme-dir", default=None)
    args = parser.parse_args(argv)

    if args.palette:
        try:
            candidate = json.loads(args.palette)
        except ValueError:
            candidate = None
        palette = complete(candidate if is_valid_palette(candidate) else None)
    else:
        theme_dir = args.theme_dir or (Path(args.home) / ".local" / "share" / "niri-setup")
        palette = read_published_palette(args.setup_home, theme_dir)

    changed = sync(args.setup_home, args.home, palette)
    # One line, space separated, on stdout. Theme.qml watches for "niri" in here
    # to decide whether to hot-reload the compositor config.
    print("changed: " + " ".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())