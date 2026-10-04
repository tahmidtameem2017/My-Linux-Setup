pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Theme.qml — dynamic theme tokens (taste.md Sunset default).
// Single source of truth for colors / font / radius.
// All other QML must use Theme.* — no per-file hex literals.
// Omarchy-style curated themes: `current` selects a palette in `palettes`;
// `active` is the resolved palette (fallback sunset). Color tokens below
// stay bound to `active` so bar + menus follow live on setTheme/next/prev.
// Persistence: ~/.local/share/niri-setup/theme.txt (plain name).
Singleton {
    id: root

    // Wallpaper Match: live palette generated from the last-set wallpaper
    // by scripts/wallust-theme.sh (wallust -> theme-wallpaper.json, see
    // wallpaperThemePath below). Default is a sunset copy so the picker
    // row always renders, even before the first wallpaper Set or when the
    // JSON is missing/invalid.
    property var wallpaperPalette: ({
        "bg": "#000000",
        "panel": "#0a0a0a",
        "row": "#141010",
        "border": "#1a1210",
        "borderStrong": "#3D2B24",
        "accent": "#E85D2F",
        "accentHover": "#FF8B4A",
        "text": "#F7C7A1",
        "muted": "#7C8A6A",
        "dim": "#555555",
        "danger": "#c30505"
    })

    // Wallpaper Vibrant: darkcomp palette variant (complementary vivid, hue 180° shift) from
    // scripts/wallust-theme.sh -> theme-wallpaper-vibrant.json. Default is
    // sunset copy for picker liveness before first Set.
    property var wallpaperVibrantPalette: ({
        "bg": "#000000",
        "panel": "#0a0a0a",
        "row": "#141010",
        "border": "#1a1210",
        "borderStrong": "#3D2B24",
        "accent": "#E85D2F",
        "accentHover": "#FF8B4A",
        "text": "#F7C7A1",
        "muted": "#7C8A6A",
        "dim": "#555555",
        "danger": "#c30505"
    })

    // Wallpaper Muted: softdark palette variant (soft muted pastel) ->
    // theme-wallpaper-muted.json. Sunset copy fallback.
    property var wallpaperMutedPalette: ({
        "bg": "#000000",
        "panel": "#0a0a0a",
        "row": "#141010",
        "border": "#1a1210",
        "borderStrong": "#3D2B24",
        "accent": "#E85D2F",
        "accentHover": "#FF8B4A",
        "text": "#F7C7A1",
        "muted": "#7C8A6A",
        "dim": "#555555",
        "danger": "#c30505"
    })

    // Wallpaper Soft: light palette variant (light soft pastel, inverted) ->
    // theme-wallpaper-soft.json. Sunset copy fallback; watcher maps light
    // bg/dark text automatically via wallust light palette.
    property var wallpaperSoftPalette: ({
        "bg": "#000000",
        "panel": "#0a0a0a",
        "row": "#141010",
        "border": "#1a1210",
        "borderStrong": "#3D2B24",
        "accent": "#E85D2F",
        "accentHover": "#FF8B4A",
        "text": "#F7C7A1",
        "muted": "#7C8A6A",
        "dim": "#555555",
        "danger": "#c30505"
    })

    // Custom: user-editable palette at theme-custom.json. Default is a
    // sunset copy so the row always renders. Edit the JSON to define any
    // 11-key palette (bg/panel/row/border/borderStrong/accent/accentHover/
    // text/muted/dim/danger) — changes apply live without restart.
    // Example: cp theme-wallpaper.json theme-custom.json then tweak.
    property var customPalette: ({
        "bg": "#000000",
        "panel": "#0a0a0a",
        "row": "#141010",
        "border": "#1a1210",
        "borderStrong": "#3D2B24",
        "accent": "#E85D2F",
        "accentHover": "#FF8B4A",
        "text": "#F7C7A1",
        "muted": "#7C8A6A",
        "dim": "#555555",
        "danger": "#c30505"
    })

    readonly property var palettes: ({
        "sunset": {
            "bg": "#000000",
            "panel": "#0a0a0a",
            "row": "#141010",
            "border": "#1a1210",
            "borderStrong": "#3D2B24",
            "accent": "#E85D2F",
            "accentHover": "#FF8B4A",
            "text": "#F7C7A1",
            "muted": "#7C8A6A",
            "dim": "#555555",
            "danger": "#c30505"
        },
        "tokyo-night": {
            "bg": "#1a1b26",
            "panel": "#16161e",
            "row": "#1f2335",
            "border": "#292e42",
            "borderStrong": "#3b4261",
            "accent": "#7aa2f7",
            "accentHover": "#7dcfff",
            "text": "#c0caf5",
            "muted": "#737aa2",
            "dim": "#4a5170",
            "danger": "#f7768e"
        },
        "catppuccin-mocha": {
            "bg": "#1e1e2e",
            "panel": "#181825",
            "row": "#313244",
            "border": "#282838",
            "borderStrong": "#45475a",
            "accent": "#cba6f7",
            "accentHover": "#f5c2e7",
            "text": "#cdd6f4",
            "muted": "#7f849c",
            "dim": "#585b70",
            "danger": "#f38ba8"
        },
        "gruvbox-dark": {
            "bg": "#282828",
            "panel": "#3c3836",
            "row": "#504945",
            "border": "#3c3836",
            "borderStrong": "#7c6f64",
            "accent": "#fe8019",
            "accentHover": "#fabd2f",
            "text": "#ebdbb2",
            "muted": "#a89984",
            "dim": "#665c54",
            "danger": "#fb4934"
        },
        "everforest": {
            "bg": "#2d353b",
            "panel": "#343f44",
            "row": "#3d484d",
            "border": "#3a454b",
            "borderStrong": "#859289",
            "accent": "#a7c080",
            "accentHover": "#dbbc7f",
            "text": "#d3c6aa",
            "muted": "#859289",
            "dim": "#56635f",
            "danger": "#e67e80"
        },
        "kanagawa-wave": {
            "bg": "#1f1f28",
            "panel": "#2a2a37",
            "row": "#363646",
            "border": "#2a2a37",
            "borderStrong": "#54546d",
            "accent": "#7e9cd8",
            "accentHover": "#ffa066",
            "text": "#dcd7ba",
            "muted": "#727169",
            "dim": "#4b4a57",
            "danger": "#e46876"
        },
        "nord": {
            "bg": "#2e3440",
            "panel": "#3b4252",
            "row": "#434c5e",
            "border": "#3b4252",
            "borderStrong": "#4c566a",
            "accent": "#88c0d0",
            "accentHover": "#8fbcbb",
            "text": "#eceff4",
            "muted": "#8a93a8",
            "dim": "#3f4759",
            "danger": "#bf616a"
        },
        "rose-pine": {
            "bg": "#191724",
            "panel": "#1f1d2e",
            "row": "#26233a",
            "border": "#26233a",
            "borderStrong": "#403d52",
            "accent": "#c4a7e7",
            "accentHover": "#ebbcba",
            "text": "#e0def4",
            "muted": "#908caa",
            "dim": "#6e6a86",
            "danger": "#eb6f92"
        },
        "dracula": {
            "bg": "#282a36",
            "panel": "#343746",
            "row": "#44475a",
            "border": "#343746",
            "borderStrong": "#6272a4",
            "accent": "#bd93f9",
            "accentHover": "#ff79c6",
            "text": "#f8f8f2",
            "muted": "#9a9bb3",
            "dim": "#4d4f68",
            "danger": "#ff5555"
        },
        "matte-black": {
            "bg": "#000000",
            "panel": "#0a0a0a",
            "row": "#161616",
            "border": "#1c1c1c",
            "borderStrong": "#3a3a3a",
            "accent": "#e8e8e8",
            "accentHover": "#ffffff",
            "text": "#ededed",
            "muted": "#8a8a8a",
            "dim": "#555555",
            "danger": "#c30505"
        },
        "wallpaper": wallpaperPalette,
        "wallpaper-vibrant": wallpaperVibrantPalette,
        "wallpaper-muted": wallpaperMutedPalette,
        "wallpaper-soft": wallpaperSoftPalette,
        "custom": customPalette
    })

    readonly property var names: ({
        "sunset": "Sunset Orange",
        "tokyo-night": "Tokyo Night",
        "catppuccin-mocha": "Catppuccin Mocha",
        "gruvbox-dark": "Gruvbox Dark",
        "everforest": "Everforest",
        "kanagawa-wave": "Kanagawa Wave",
        "nord": "Nord",
        "rose-pine": "Rosé Pine",
        "dracula": "Dracula",
        "matte-black": "Matte Black",
        "wallpaper": "Wallpaper Match",
        "wallpaper-vibrant": "Wallpaper Vibrant",
        "wallpaper-muted": "Wallpaper Muted",
        "wallpaper-soft": "Wallpaper Soft",
        "custom": "Custom"
    })

    readonly property var order: ["sunset", "tokyo-night", "catppuccin-mocha", "gruvbox-dark", "everforest", "kanagawa-wave", "nord", "rose-pine", "dracula", "matte-black", "wallpaper", "wallpaper-vibrant", "wallpaper-muted", "wallpaper-soft", "custom"]

    property string current: "sunset"
    readonly property var active: legibility(palettes[current] ?? palettes["sunset"])

    // ---------------------------------------------------------------------
    // Legibility guarantee
    //
    // Producers cannot be trusted to produce a legible palette, so none of them
    // is. Measured across all 15 palettes: sunset's own `--row` fill sits at
    // 1.11:1 against its background (invisible button), `--dim` ranged from
    // 1.34:1 (nord) to 3.42:1, and two wallpaper palettes had NO colour that
    // reached 4.5:1 on the accent fill, so selected-row text was unreadable.
    //
    // Rather than hand-tune 15 dictionaries and hope the next wallpaper behaves,
    // every palette is pushed to the same floors here. Because `active` is what
    // gets published to active-theme.json, the lock screen, tmux, alacritty,
    // niri and the guide all inherit the guarantee, not just this shell.
    //
    // Every threshold is a contrast ratio against a real background the colour
    // is actually drawn on: 7.0 body-ish, 4.5 the WCAG AA floor for normal text,
    // 3.0 for genuinely secondary text, and ~1.3 where the job is only to make
    // one surface distinguishable from another.
    readonly property var floors: ({
        // colour: [minimum contrast, the background it must clear it against]
        "text": [[7.0, "bg"]],
        "accent": [[4.5, "bg"]],
        "accentHover": [[7.0, "bg"]],
        "danger": [[4.5, "bg"]],
        "muted": [[4.5, "bg"], [3.0, "panel"]],
        "dim": [[3.5, "bg"], [3.0, "panel"]],
        "panel": [[1.30, "bg"]],
        "row": [[1.60, "bg"], [1.12, "panel"]],
        "border": [[1.25, "bg"]],
        "borderStrong": [[2.50, "panel"]]
    })

    function _rgb(hex) {
        const h = String(hex).trim().replace("#", "");
        return [parseInt(h.substring(0, 2), 16),
                parseInt(h.substring(2, 4), 16),
                parseInt(h.substring(4, 6), 16)];
    }

    function _hex(c) {
        const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)));
        return "#" + c.map((v) => clamp(v).toString(16).padStart(2, "0")).join("");
    }

    function _lum(c) {
        const f = (v) => {
            const s = v / 255;
            return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
        };
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
    }

    function _contrast(a, b) {
        const la = _lum(a), lb = _lum(b);
        const hi = Math.max(la, lb), lo = Math.min(la, lb);
        return (hi + 0.05) / (lo + 0.05);
    }

    function _mix(from, to, amount) {
        return [from[0] + (to[0] - from[0]) * amount,
                from[1] + (to[1] - from[1]) * amount,
                from[2] + (to[2] - from[2]) * amount];
    }

    // The one grey a palette has no token for: the achromatic colour with
    // exactly `l`'s relative luminance, i.e. the accent's weight with none of
    // its hue. Used as the anchor for the icon ramp below.
    function _greyAt(l) {
        const encode = (s) => (s <= 0.0031308 ? 12.92 * s : 1.055 * Math.pow(s, 1 / 2.4) - 0.055);
        const g = Math.max(0, Math.min(255, Math.floor(encode(l) * 255 + 0.5)));
        return [g, g, g];
    }

    // Push `colour` away from `bg` until it clears `target`, toward whichever of
    // black/white has more headroom.
    //
    // The binary search tests the ROUNDED 8-bit value, not the float, because
    // that is what actually gets drawn: searching the float and rounding the
    // result lands a channel just under the target and then plateaus, which is
    // how the accent kept publishing at 4.49:1 against a 4.50 floor. EPS absorbs
    // the sub-hundredth of a ratio that no display can resolve, and stops the
    // search chasing a fraction it can never represent.
    readonly property real floorEps: 0.005

    function _push(colour, bg, target) {
        const goal = target - floorEps;
        if (_contrast(colour, bg) >= goal)
            return colour;
        const toward = _lum(bg) > 0.18 ? [0, 0, 0] : [255, 255, 255];
        const at = (amount) => _rgb(_hex(_mix(colour, toward, amount)));
        let lo = 0, hi = 1;
        for (let i = 0; i < 24; ++i) {
            const mid = (lo + hi) / 2;
            if (_contrast(at(mid), bg) >= goal)
                hi = mid;
            else
                lo = mid;
        }
        // If nothing passes the goal, hi never leaves 1.0 and this is the far
        // end, i.e. the best available. (Do NOT add a "keep whichever is
        // better" fallback here: at(1) trivially has the most contrast, so that
        // comparison is always true and it collapses every colour to pure
        // black or pure white. hi is already the smallest amount that passes.)
        return at(hi);
    }

    // Order matters: the surfaces (panel/row/border) are settled before the text
    // colours that get measured against them, and body text before the secondary
    // tones so muted/dim are pushed against a bg, not against a moving target.
    // Memo for legibility(). A palette's normalised form never changes while the
    // palette itself does not, and ThemePicker asks for it once per swatch per
    // repaint (~150 calls), which is ~500 colour operations each time. Keyed on
    // the input's own JSON so a palette edit invalidates it for free.
    property var _legibilityCache: ({})

    function legibility(raw) {
        if (!raw)
            return raw;
        let cacheKey = null;
        try {
            cacheKey = JSON.stringify(raw);
        } catch (e) {
            cacheKey = null; // a live binding, not a plain object; skip caching
        }
        if (cacheKey !== null && _legibilityCache[cacheKey] !== undefined)
            return _legibilityCache[cacheKey];
        const out = _legibilityUncached(raw);
        if (cacheKey !== null) {
            const next = {};
            next[cacheKey] = out;
            for (const k in _legibilityCache)
                if (k !== cacheKey && Object.keys(next).length > 24)
                    delete _legibilityCache[k];
            Object.assign(_legibilityCache, next);
        }
        return out;
    }

    function _legibilityUncached(raw) {
        const out = {};
        for (const k in raw)
            out[k] = raw[k];
        const order = ["panel", "row", "border", "borderStrong", "text",
                       "accent", "accentHover", "danger", "muted", "dim"];
        for (const k of order) {
            const rules = floors[k];
            if (!rules)
                continue;
            let c = _rgb(out[k]);
            for (const rule of rules)
                c = _push(c, _rgb(out[rule[1]]), rule[0]);
            out[k] = _hex(c);
        }
        return out;
    }

    // --bg: page / bar background
    property color bg: active.bg ?? "#000000"
    // --panel: cards, bar section containers
    property color panel: active.panel ?? "#0a0a0a"
    // --row: buttons, list rows
    property color row: active.row ?? "#141010"
    // --border: faint borders, slider tracks
    property color border: active.border ?? "#1a1210"
    // --border-strong: card borders, button borders
    property color borderStrong: active.borderStrong ?? "#3D2B24"
    // --accent: primary actions, today/selected, active states
    property color accent: active.accent ?? "#E85D2F"
    // --accent-hover: hover text, highlights
    property color accentHover: active.accentHover ?? "#FF8B4A"
    // --text: body text
    property color text: active.text ?? "#F7C7A1"
    // --muted: secondary text, hints, device names
    property color muted: active.muted ?? "#7C8A6A"
    // --dim: overflow days, disabled, placeholder
    property color dim: active.dim ?? "#555555"
    // --danger: wrong-password, destructive confirm
    property color danger: active.danger ?? "#c30505"

    // --on-accent: text/icon drawn ON a solid --accent fill (selected row,
    // active toggle, mode chip). Never hardcode "bg" for this: an accent fill
    // is not always dark. Matte Black's accent is near-white, and a wallpaper
    // accent can land anywhere, so the two candidates are measured and the
    // readable one wins instead of being assumed.
    readonly property color onAccent:
        (_contrast(_rgb(active.bg), _rgb(active.accent)) >= _contrast(_rgb(active.text), _rgb(active.accent)))
        ? bg : text
    // Same choice, muted strength, for the dimmer hint line inside a selection.
    readonly property color onAccentMuted:
        (_contrast(_rgb(active.muted), _rgb(active.accent)) >= _contrast(_rgb(active.text), _rgb(active.accent)))
        ? muted : text

    // ---------------------------------------------------------------------
    // --icon / --icon-muted: the neutral chrome ramp
    //
    // The stroke icon set is monochrome SVG and quickshell's IconImage has no
    // `color` property, so an icon's colour cannot be a token at the call site —
    // it is baked in by sync-external-theme.py. That made the accent the de
    // facto icon colour, and the bar ended up shouting: the tray read as a row
    // of orange alerts competing with the one thing that IS an alert (a
    // critical battery). Worse, several tray widgets pointed straight at
    // waybar/icons/*.svg, whose strokes are frozen at the sunset hexes, so they
    // ignored the palette entirely and sat next to genuinely themed icons as a
    // different colour.
    //
    // So icons are neither the accent nor the text token: they are a NEUTRAL
    // grey carrying a slight tint of the palette's own accent. Three steps,
    // in order of deliberate weight:
    //
    //   anchor  the accent's luminance, zero saturation -- so the tint below
    //           cannot change how heavy the glyph looks versus what it
    //           replaced
    //   tint    iconTint of the accent mixed back in, which keeps the palette
    //           recognisable without any icon reading as "coloured"
    //   pin     exactly `ratio` against --bg, both directions
    //
    // The pin is why this is derived rather than authored per palette. The
    // accent only carries a 4.5 floor, so a wallpaper accent can land anywhere,
    // and an icon that inherited its luminance would be invisible on one
    // wallpaper and blinding on the next. Every icon clears 4.5:1 on the bar
    // and every *off* state clears 3.5:1 (the --dim floor, so an "off" state
    // keeps exactly the contrast it had before), so "quiet" is still legible.
    //
    // scripts/colorlib.py `neutral_icon()` is the Python twin of _pinIcon and
    // scripts/test_icon_colors.py asserts the two agree 8-bit-for-8-bit: it
    // extracts these functions out of this file and runs them under node beside
    // colorlib.neutral_icon(). It has to, because Python paints the SVGs and
    // this paints the launcher's Nerd Font glyphs, and those two sit in the same
    // list one row apart.
    readonly property real iconTint: 0.22
    readonly property real iconRatio: 4.5
    readonly property real iconMutedRatio: 3.5

    function _pinIcon(p, ratio) {
        const bg = _rgb(p.bg);
        const accent = _rgb(p.accent);
        let c = _mix(_greyAt(_lum(accent)), accent, iconTint);
        c = _push(c, bg, ratio);
        // _push only ever moves AWAY from bg, so on its own it cannot make an
        // icon quieter -- it can only leave a loud one loud. Pull the surplus
        // back so the ramp is two chosen weights rather than "whatever the
        // accent's luminance happened to be".
        //
        // The predicate is ">= goal", NOT "<= ratio", and that is the whole
        // subtlety. Contrast is only reachable in 8-bit steps, so aiming for
        // "<= ratio" settles on the last rung BELOW the floor -- 4.487:1 for a
        // 4.50 floor on sunset -- which is an icon meant to be guaranteed
        // readable failing its own guarantee by one rounding step. Aiming for
        // ">= goal" takes the quietest rung that actually clears, 4.51:1, which
        // is the intent.
        //
        // And the answer is `lo`, not `hi`: `lo` is the smallest mix still known
        // to clear, `hi` the largest known to MISS, which is the rung under the
        // floor -- exactly the value this search exists to avoid. With no
        // "keep whichever is better" fallback either: at(0) already clears, so
        // the search converges on the smallest mix, whereas that always-true
        // comparison would collapse every icon to bg.
        if (_contrast(c, bg) > ratio + floorEps) {
            const at = (amount) => _rgb(_hex(_mix(c, bg, amount)));
            let lo = 0, hi = 1;
            for (let i = 0; i < 24; ++i) {
                const mid = (lo + hi) / 2;
                if (_contrast(at(mid), bg) >= ratio - floorEps)
                    lo = mid;
                else
                    hi = mid;
            }
            c = at(lo);
        }
        return c;
    }

    readonly property color icon: _pinIcon(active, iconRatio)
    readonly property color iconMuted: _pinIcon(active, iconMutedRatio)

    // Alpha helper. Several surfaces inherited a baked-in alpha from the tool
    // they replaced (fuzzel `background=#000000f2`, dunst `#000000e6`,
    // `placeholder=#7c8a6aaa`) and that alpha has to survive a palette
    // switch: "black at 95%" is not a token, it is `bg` at 95%, and a wallpaper
    // palette's bg is not black at all. Writing `#f2000000` here would have
    // pinned every one of those surfaces to the sunset background.
    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Typography: JetBrainsMono Nerd Font everywhere (bar, popups, menus).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Shape: sharp rectangles on bar and popup cards.
    readonly property int radius: 0

    // Motion: hover color/opacity fades + one startup entrance slide only.
    // Scale is intentionally 1.0 (no hover/press zoom): scaling forces
    // texture re-raster every frame, the top QML cost on weak iGPUs
    // (Intel HD 5500). Press feedback is instant (no anim). Durations in
    // ms; easings are Easing.OutCubic at use sites.
    readonly property int animFast: 100
    readonly property int animHover: 120
    readonly property int animEnter: 180
    readonly property real hoverScale: 1.0
    readonly property real pressScale: 1.0
    // Future kill-switch for all bar motion (not wired to widgets yet).
    readonly property bool reduceMotion: false

    // Glow (taste.md): resting + hover/active. Kept here so builders
    // reuse these instead of inventing new shadows.
    readonly property string shadowResting: "0 0 15px rgba(232, 93, 47, 0.15)"
    readonly property string glowHover: "0 0 6px rgba(255,139,74,.9), 0 0 18px rgba(255,139,74,.6), 0 0 35px rgba(232,93,47,.35)"

    readonly property string homeDir: Quickshell.env("HOME") ?? "/home/me"
    readonly property string setupHome: Quickshell.env("NIRI_SETUP_HOME") ?? (homeDir + "/niri-setup")
    readonly property string themeDir: homeDir + "/.local/share/niri-setup"
    readonly property string themePath: themeDir + "/theme.txt"
    readonly property string wallpaperThemePath: themeDir + "/theme-wallpaper.json"
    readonly property string wallpaperVibrantThemePath: themeDir + "/theme-wallpaper-vibrant.json"
    readonly property string wallpaperMutedThemePath: themeDir + "/theme-wallpaper-muted.json"
    readonly property string wallpaperSoftThemePath: themeDir + "/theme-wallpaper-soft.json"
    readonly property string customThemePath: themeDir + "/theme-custom.json"
    readonly property string autoPath: themeDir + "/theme-auto"
    // Which palette-fingerprinted icon directory scripts/sync-external-theme.py
    // last built. Read here rather than recomputed: the fingerprint is a digest
    // over the palette and duplicating that in QML would guarantee the two
    // sides drifting into different directory names.
    readonly property string iconDirPath: themeDir + "/icon-dir.txt"
    property string iconFingerprint: ""
    // Derived export of whatever is ACTIVE right now, for readers outside the
    // shell (scripts/palette.sh -> lock screen, fastfetch, any script that
    // wants the bar's colors). Deliberately not a `theme-<name>.json` source
    // file: those are inputs the shell watches, this is an output the shell
    // writes and never reads back. Without it the built-in palettes exist
    // only inside `palettes` below and every external script has to guess.
    readonly property string activeThemePath: themeDir + "/active-theme.json"
    // Staging path for publishPalette()'s rename.
    readonly property string activeThemeTmpPath: themeDir + "/.active-theme.json.tmp"

    // Last applied raw JSON text. Change detection: identical content is
    // a no-op, so the refresh timer below never churns bindings.
    property string wallpaperJson: ""
    property string wallpaperVibrantJson: ""
    property string wallpaperMutedJson: ""
    property string wallpaperSoftJson: ""
    property string customJson: ""
    property bool autoTheming: true
    property bool autoPreferenceLoaded: false
    property bool themePreferenceLoaded: false
    property bool startupThemeResolved: false
    property string savedTheme: "sunset"
    // True when the current theme is the user's own explicit pick rather than
    // something auto-theming dragged us to. Auto only re-follows the wallpaper
    // while this is false, so picking Tokyo Night in ThemePicker sticks — the
    // wallpaper changing no longer yanks you off it. Any explicit pick sets it
    // true; turning auto on again clears it (that IS a request to follow).
    property bool manualTheme: false
    // Which wallpaper-derived palette auto-theming follows. Kept so that
    // explicitly picking "Wallpaper Muted" is not silently undone by the next
    // wallpaper change snapping back to the base "Wallpaper Match".
    property string autoVariant: "wallpaper"
    // Last palette handed to publishPalette(), so a no-op change costs a
    // string compare instead of a detached shell.
    property string publishedPalette: ""

    // Validate + apply the wallust-generated palette. Rejects torn writes
    // (empty/partial JSON) and schema drift (missing keys, non-hex
    // values) by keeping the current palette; the writer (in-place, same
    // inode) triggers another change event and the timer retries.
    function applyWallpaperJson(t) {
        const s = (t ?? "").trim();
        if (s === "" || s === wallpaperJson)
            return;
        try {
            const p = JSON.parse(s);
            const keys = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"];
            for (let i = 0; i < keys.length; ++i) {
                const v = p[keys[i]];
                if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v))
                    return;
            }
            wallpaperJson = s;
            wallpaperPalette = p;
            resolveStartupTheme();
            applyAutoIfWanted();
        } catch (e) {
        }
    }

    function applyWallpaperVibrantJson(t) {
        const s = (t ?? "").trim();
        if (s === "" || s === wallpaperVibrantJson)
            return;
        try {
            const p = JSON.parse(s);
            const keys = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"];
            for (let i = 0; i < keys.length; ++i) {
                const v = p[keys[i]];
                if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v))
                    return;
            }
            wallpaperVibrantJson = s;
            wallpaperVibrantPalette = p;
        } catch (e) {
        }
    }

    function applyWallpaperMutedJson(t) {
        const s = (t ?? "").trim();
        if (s === "" || s === wallpaperMutedJson)
            return;
        try {
            const p = JSON.parse(s);
            const keys = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"];
            for (let i = 0; i < keys.length; ++i) {
                const v = p[keys[i]];
                if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v))
                    return;
            }
            wallpaperMutedJson = s;
            wallpaperMutedPalette = p;
        } catch (e) {
        }
    }

    function applyWallpaperSoftJson(t) {
        const s = (t ?? "").trim();
        if (s === "" || s === wallpaperSoftJson)
            return;
        try {
            const p = JSON.parse(s);
            const keys = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"];
            for (let i = 0; i < keys.length; ++i) {
                const v = p[keys[i]];
                if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v))
                    return;
            }
            wallpaperSoftJson = s;
            wallpaperSoftPalette = p;
        } catch (e) {
        }
    }

    function applyCustomJson(t) {
        const s = (t ?? "").trim();
        if (s === "" || s === customJson)
            return;
        try {
            const p = JSON.parse(s);
            const keys = ["bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger"];
            for (let i = 0; i < keys.length; ++i) {
                const v = p[keys[i]];
                if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v))
                    return;
            }
            customJson = s;
            customPalette = p;
        } catch (e) {
        }
    }

    // Pick a theme. This is the *user action* entry point (ThemePicker rows, the
    // `themes set` IPC verb).
    //
    // Auto and an explicit pick used to be able to disagree: picking "Custom"
    // set manualTheme, which silently stopped the auto-follow, while the Auto
    // toggle still read ON. The picker then showed Auto ON + Custom ticked, and
    // changing the wallpaper did nothing — the toggle was lying. An explicit
    // pick is now the whole truth:
    //
    //   * a wallpaper variant  -> still following the wallpaper, so auto stays
    //     ON and this variant becomes the one auto follows. Picking "Wallpaper
    //     Muted" means "follow, muted", not "follow, but ignore me".
    //   * anything else        -> a real preference, so auto goes OFF.
    function setTheme(n) {
        if (palettes[n] === undefined)
            return;
        if (isWallpaperVariant(n)) {
            autoVariant = n;
            // Deliberately does not write the auto preference file: autoTheming
            // is unchanged (still on). If it was off, the user is choosing a
            // wallpaper variant, which is a request to follow.
            autoTheming = true;
            saveAutoPreference();
            pickTheme(n, false);
        } else {
            if (autoTheming)
                setAuto(false);
            pickTheme(n, true);
        }
    }

    // Wallpaper-derived palettes are the ones auto-theming can own. Matched on
    // the key prefix rather than a hardcoded list so adding a fifth variant to
    // wallust-theme.sh does not need a second edit here.
    function isWallpaperVariant(n) {
        return n === "wallpaper" || String(n).indexOf("wallpaper-") === 0;
    }

    function pickTheme(n, manual) {
        if (palettes[n] === undefined)
            return;
        manualTheme = manual;
        current = n;
        save();
    }

    // Startup theme resolution. Idempotent and order-independent.
    //
    // Three inputs arrive in whatever order FileView happens to deliver them
    // (theme.txt, theme-auto, the wallpaper palette), so this is called from
    // all of them and simply retries until it has what it needs:
    //   * both preferences read, and
    //   * the wallpaper palette, but only when auto is on and wants it.
    //
    // The resolved flag is set only at the moment the decision is actually
    // taken. That is the whole point: a caller that arrives early must not
    // consume the decision, or a later caller has nothing left to retry with.
    // (Previously `applyStartupTheme()` was gated on `wallpaperJson !== ""`
    // from the preference callbacks too, so if the preferences happened to be
    // read before the wallpaper palette, resolution silently never happened
    // and the shell sat on whatever `current` defaulted to.)
    function resolveStartupTheme() {
        if (startupThemeResolved)
            return;
        if (!themePreferenceLoaded || !autoPreferenceLoaded)
            return;
        if (autoTheming && wallpaperJson === "")
            return; // auto wants the wallpaper palette; it has not landed yet
        startupThemeResolved = true;
        const followWallpaper = autoTheming && wallpaperJson !== "";
        // With auto on, the saved theme IS the variant to follow, so a session
        // that ended on "Wallpaper Muted" resumes following muted instead of
        // silently snapping to the base variant.
        if (followWallpaper && isWallpaperVariant(savedTheme))
            autoVariant = savedTheme;
        pickTheme(followWallpaper ? autoVariant : savedTheme, !followWallpaper);
    }

    // The one place that decides "the wallpaper palette changed, do I follow?".
    // Both the wallpaper watcher and setAuto() land here, so enabling auto
    // before the wallpaper palette has been read is not a silent no-op.
    function applyAutoIfWanted() {
        if (!autoTheming || !startupThemeResolved || manualTheme)
            return;
        if (wallpaperJson === "")
            return;
        if (current !== autoVariant)
            pickTheme(autoVariant, false);
    }

    // Re-read every palette input. Used by setAuto() so a wallpaper palette
    // written since startup (a FileView only watches paths that existed when
    // it loaded) can still be picked up on demand.
    function reloadPaletteSources() {
        themeFile.reload();
        autoFile.reload();
        iconDirFile.reload();
        wallpaperThemeFile.reload();
        wallpaperVibrantThemeFile.reload();
        wallpaperMutedThemeFile.reload();
        wallpaperSoftThemeFile.reload();
        if (customExists)
            customThemeFile.reload();
    }

    // Directory holding the themed copies of the monochrome stroke icon set.
    //
    // It is fingerprinted with the palette and rebuilt by
    // scripts/sync-external-theme.py, and the fingerprint is what makes the
    // switch visible: Qt caches a decoded image per source URL, so rewriting an
    // SVG in place under a stable path leaves every IconImage on screen
    // rendering the PREVIOUS theme until the shell restarts. Changing the URL
    // is what makes the loader re-decode. The generator publishes the directory
    // name in icon-dir.txt (QML cannot compute the same digest itself), and the
    // originals in assets/icons/ remain the sunset-coloured fallback.
    readonly property string iconDir: setupHome + "/quickshell/sunset/assets/icons/"
            + (iconFingerprint === "" ? "" : "theme/" + iconFingerprint + "/")

    function nextTheme() {
        const i = order.indexOf(current);
        const n = (i === -1) ? 0 : (i + 1) % order.length;
        setTheme(order[n]);
    }

    function prevTheme() {
        const i = order.indexOf(current);
        const n = (i === -1) ? 0 : (i - 1 + order.length) % order.length;
        setTheme(order[n]);
    }

    function save() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"" + themeDir + "\" && printf '%s' \"" + current + "\" > \"" + themePath + "\""]);
    }

    function syncFastfetch() {
        fastfetchProc.paletteJson = JSON.stringify(active);
        if (!fastfetchProc.running) {
            fastfetchProc.submittedPalette = fastfetchProc.paletteJson;
            fastfetchProc.running = true;
        }
    }

    // Export the active palette so the world outside quickshell can read it.
    // Same JSON.stringify(active) payload as syncFastfetch() — the point is
    // that built-in palettes get published too, not just the wallust ones.
    function publishPalette() {
        const json = JSON.stringify(active);
        if (json === publishedPalette)
            return;
        publishedPalette = json;
        // Single-quoted payload: the JSON is full of double quotes, which
        // save()'s printf '"…"' cannot carry. '\'' is the POSIX escape for an
        // embedded quote; no hex token contains one today, but replacing keeps
        // that from ever being load-bearing.
        const payload = json.replace(/'/g, "'\\''");
        // Stage then rename: an external reader (palette.sh, lock screen) can
        // never observe a half-written file. Nothing watches this path, so the
        // inode swap costs nothing.
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"" + themeDir + "\" && printf '%s\\n' '" + payload + "' > \"" + activeThemeTmpPath + "\" && mv -f \"" + activeThemeTmpPath + "\" \"" + activeThemePath + "\""]);
    }

    function saveAutoPreference() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"" + themeDir + "\" && printf '%s' \"" + (autoTheming ? "1" : "0") + "\" > \"" + autoPath + "\""]);
    }

    function setAuto(enabled) {
        autoTheming = enabled;
        saveAutoPreference();
        if (!enabled)
            return;
        // Turning auto ON is a request to follow the wallpaper, so drop the
        // manual-pick lock and jump straight there when the palette is already
        // loaded. If it is not loaded yet, applyAutoIfWanted() picks it up the
        // moment the wallpaper palette lands — and re-reading the sources
        // covers the case where the file was written before the FileView ever
        // started watching it.
        manualTheme = false;
        if (wallpaperJson !== "")
            pickTheme(autoVariant, false);
        resolveStartupTheme();
        reloadPaletteSources();
    }

    function toggleAuto() {
        setAuto(!autoTheming);
    }

    onActiveChanged: paletteSyncTimer.restart()

    // One debounce for every exporter: a palette change fires exactly once
    // regardless of how many reads (theme.txt, auto, wallpaper JSONs) were
    // involved in getting there.
    Timer {
        id: paletteSyncTimer
        interval: 150
        repeat: false
        running: true
        onTriggered: {
            root.syncFastfetch();
            root.publishPalette();
            root.syncExternal();
        }
    }

    Process {
        id: fastfetchProc
        property string paletteJson: ""
        property string submittedPalette: ""
        command: ["python3", root.setupHome + "/scripts/sync-fastfetch-theme.py", root.setupHome + "/fastfetch/config.jsonc.in", submittedPalette, root.themeDir + "/fastfetch-config.jsonc"]
        running: false
        onExited: {
            if (submittedPalette !== paletteJson) {
                submittedPalette = paletteJson;
                running = true;
            }
        }
    }

    // Push the active palette to everything outside quickshell that has no
    // palette of its own: the tmux status bar, both alacritty profiles, the
    // niri focus ring and the HTML guide. Each target is generated from a
    // template and written only when its bytes actually change, so the common
    // case (a wallpaper tweak that barely moves the accent) costs nothing.
    //
    // stdout is one line naming the targets that changed; niri is only
    // hot-reloaded when its own colours moved, because load-config-file is a
    // whole-config operation and a wallpaper change must not trigger one for
    // a no-op repaint.
    Process {
        id: externalProc
        property string paletteJson: ""
        property string submittedPalette: ""
        stdout: StdioCollector {
            onStreamFinished: root.reloadNiriConfigIfNeeded(this.text)
        }
        command: ["python3", root.setupHome + "/scripts/sync-external-theme.py", "--palette", submittedPalette]
        running: false
        onExited: {
            if (submittedPalette !== paletteJson) {
                submittedPalette = paletteJson;
                running = true;
            }
        }
    }

    function syncExternal() {
        externalProc.paletteJson = JSON.stringify(active);
        if (!externalProc.running) {
            externalProc.submittedPalette = externalProc.paletteJson;
            externalProc.running = true;
        }
    }

    function reloadNiriConfigIfNeeded(stdout) {
        if ((stdout ?? "").split(/\s+/).indexOf("niri") === -1)
            return;
        Quickshell.execDetached(["niri", "msg", "action", "load-config-file"]);
    }

    FileView {
        id: themeFile
        path: root.themePath
        watchChanges: true
        onLoaded: {
            if (root.themePreferenceLoaded)
                return;
            const t = text().trim();
            root.savedTheme = root.palettes[t] !== undefined ? t : "sunset";
            root.themePreferenceLoaded = true;
            root.current = root.savedTheme;
            root.resolveStartupTheme();
        }
        onLoadFailed: {
            if (!root.themePreferenceLoaded) {
                root.savedTheme = "sunset";
                root.themePreferenceLoaded = true;
                root.resolveStartupTheme();
            }
        }
        onFileChanged: reload()
    }

    FileView {
        id: wallpaperThemeFile
        path: root.wallpaperThemePath
        watchChanges: true
        onLoaded: root.applyWallpaperJson(text())
        // Missing file (fresh install, no wallpaper Set yet): keep the
        // sunset-copy default in wallpaperPalette.
        onLoadFailed: {
        }
        onFileChanged: reload()
    }

    FileView {
        id: wallpaperVibrantThemeFile
        path: root.wallpaperVibrantThemePath
        watchChanges: true
        onLoaded: root.applyWallpaperVibrantJson(text())
        onLoadFailed: {
        }
        onFileChanged: reload()
    }

    FileView {
        id: wallpaperMutedThemeFile
        path: root.wallpaperMutedThemePath
        watchChanges: true
        onLoaded: root.applyWallpaperMutedJson(text())
        onLoadFailed: {
        }
        onFileChanged: reload()
    }

    FileView {
        id: wallpaperSoftThemeFile
        path: root.wallpaperSoftThemePath
        watchChanges: true
        onLoaded: root.applyWallpaperSoftJson(text())
        onLoadFailed: {
        }
        onFileChanged: reload()
    }

    // Tracks whether the optional custom file exists, so the backstop
    // below doesn't re-attempt (and re-warn) a missing-file read.
    // Missing is the normal state; the watcher picks up later creation
    // only if the path exists at startup, hence the periodic retry.
    property bool customExists: true

    FileView {
        id: customThemeFile
        path: root.customThemePath
        watchChanges: true
        onLoaded: {
            root.customExists = true;
            root.applyCustomJson(text());
        }
        // Missing file: keep sunset-copy default in customPalette.
        onLoadFailed: {
            root.customExists = false;
        }
        onFileChanged: reload()
    }

    // Written by scripts/sync-external-theme.py after it (re)builds the themed
    // icon set, and named in the SAME order (directory first, pointer second) so
    // this never resolves a directory whose SVGs do not exist yet. That writer
    // must keep the inode -- see write_watched() -- or this watcher dies on the
    // first theme change and, with the directory below pruned as superseded,
    // every icon in the shell goes blank until a restart.
    // Missing before the first sync, in which case iconDir points at
    // the sunset originals and the first palette change creates the themed copy.
    FileView {
        id: iconDirFile
        path: root.iconDirPath
        watchChanges: true
        onLoaded: root.iconFingerprint = text().trim()
        onFileChanged: reload()
    }

    FileView {
        id: autoFile
        path: root.autoPath
        watchChanges: true
        onLoaded: {
            if (root.autoPreferenceLoaded)
                return;
            const t = text().trim().toLowerCase();
            root.autoTheming = (t === "1" || t === "true" || t === "auto" || t === "on");
            root.autoPreferenceLoaded = true;
            root.resolveStartupTheme();
        }
        onLoadFailed: {
            if (!root.autoPreferenceLoaded) {
                root.autoTheming = true;
                root.autoPreferenceLoaded = true;
                root.resolveStartupTheme();
            }
        }
        onFileChanged: reload()
    }

    // Backstop for QFileSystemWatcher gaps: a path that does not exist at
    // startup is never watched (created-later file missed), and an atomic
    // rename-replace drops the watch (inode change). Every writer here is
    // supposed to write in place to keep its inode; this timer covers the rest
    // (a stray rename-replace, a race at startup). Change detection in the
    // apply*Json handlers makes idle ticks a no-op, and re-assigning
    // iconFingerprint its existing value emits no change, so this cannot churn
    // icon reloads.
    // 60s (was 15s): theme files change on user action, not on a schedule —
    // the watchers carry the live path, this only rescues missed events.
    // Skips the optional custom file while it is known-missing (its
    // absence is the normal state; retry hourly-ish via the flag reset).
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            wallpaperThemeFile.reload();
            wallpaperVibrantThemeFile.reload();
            wallpaperMutedThemeFile.reload();
            wallpaperSoftThemeFile.reload();
            autoFile.reload();
            // The icon pointer is the one file whose staleness is FATAL rather
            // than cosmetic: sync-external-theme.py prunes the superseded
            // fingerprinted icon directory, so a shell still holding the old name
            // resolves icons in a directory that no longer exists and the whole
            // bar's icon set renders blank.
            iconDirFile.reload();
            if (root.customExists)
                customThemeFile.reload();
            else
                root.customExists = true; // re-probe next round
        }
    }
}
