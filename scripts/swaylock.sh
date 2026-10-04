#!/usr/bin/env bash
# swaylock.sh — the lock screen (Mod+L, and the swayidle timeout).
#
# Look, in three places:
#   * scripts/palette.sh    — every colour comes from the shell's *active*
#                             theme, so the lock follows ThemePicker/wallust
#                             instead of being frozen at Sunset Orange.
#   * scripts/swaylock-bg.sh — the rendered backdrop: the current wallpaper,
#                             blurred just enough to read as colour rather than
#                             detail, dimmed on the left so the baked clock/date/
#                             widget row stay legible, and (top-left) that whole
#                             block of text. It replaces swaylock's
#                             --screenshots, which freezes the bar and window
#                             text into the lock.
#   * the flags below        — the indicator states. taste.md: JetBrainsMono
#                             everywhere, black/orange, restraint at rest, white
#                             only ever for the wrong password.
#
# WHY THERE IS A (SMALL) RING, AND WHY THERE ARE NO DOTS
# ------------------------------------------------------
# Both of these are forced by what this locker can actually draw. Verified against
# the installed swaylock-effects 1.8.1 (render.c, v1.8.1 tag):
#
#   * The ring, the inside fill, the state message, the rotating "typing" arc, the
#     inner/outer border circles and the layout box are all inside ONE block:
#         if (args.indicator || (show_indicator && auth_state != GRACE)) { ... }
#     So --no-unlock-indicator does not "hide the circle and leave the dots" — it
#     removes the indicator surface entirely and you get a completely inert
#     screen: no dots, no arc, no messages. That was a wrong turn.
#
#   * There is no password-dot rendering in this build at all. render.c never
#     reads state->password; password.c only consumes key events and moves the
#     auth_state along. The only things it can draw are the five above. So "show
#     me how many characters I have typed" is not reachable from this locker —
#     there is no option for it, and no value of any flag invents one.
#
#     Verified live, not just in the source: with --no-unlock-indicator the ring
#     is gone AND nothing replaces it, and with the ring on, typing draws the arc
#     and nothing else. Swapping the locker (gtklock renders dots in a real GTK
#     entry) is the only way to get a character count, and that is a bigger
#     change than this lock screen is worth on its own.
#
# So the per-keystroke feedback is the one thing this build does have: the
# TYPE_INDICATOR_RANGE arc, a 60 degree segment that jumps to a new random angle
# on every keypress, stroked in --key-hl-color. That is why the ring stays — a
# hairline for the arc to sit on — but it stays at 2px on radius 100 instead of
# 5px on radius 150, and the filled disc is gone entirely (--inside-color is
# fully transparent), so what is left is a hairline and a moving highlight rather
# than a big empty plate.
#
# No --show-keyboard-layout: it printed a big "English (US)" chip in the middle of
# the screen while typing, which was the other thing that made this look
# unfinished. -K is passed as well so swaylock cannot decide to show it on its
# own. Caps lock still shows, because that one is a real state warning.
#
# No --clock, either. The clock is baked into the background image, and swaylock
# has no ext-layer-shell: it grabs the output through ext-session-lock-v1, so
# nothing can be drawn over it. Passing --clock as well used to put a second,
# centred clock inside the ring — that was the ugly screen.
#
# --show-failed-attempts is deliberately NOT passed. With this build it hijacks
# the message while typing and prints a bare attempt count, which on a lock screen
# with no dots reads exactly like a character count. Confusing feedback is worse
# than none; add it back if you want the escalation and know what the number is.
#
# Security: --ignore-empty-password is NOT passed, and must never be. Per the
# man page it means "when an empty password is provided, do not validate it" —
# i.e. pressing Enter on an empty field unlocks the screen. Nothing else in here
# is allowed to weaken that, and if the background cannot be rendered we lock on
# a flat colour rather than not locking at all.
#
# Knobs (all env-overridable, so you can try a size without editing this file):
#   RADIUS=100      indicator radius, px. 2*RADIUS is also the widest the state
#                   messages can be, so keep the words short (see TEXT_*)
#   THICKNESS=2     the hairline, px. This is also the stroke width of the
#                   keystroke arc, so it doubles as the reaction's visibility
#   FONT_SIZE=20    state-message size, px. Deliberately independent of RADIUS
#   FONT="JetBrainsMono NF:weight=bold"
#   TEXT_VER / TEXT_WRONG / TEXT_CLEAR / TEXT_CAPS   the four state messages
#   FADE_IN=0.6    seconds; 0 disables
#   DAEMONIZE=1    0 keeps swaylock in the foreground (tests, `timeout 8 ...`)
#   DRYRUN=1       print the swaylock argv, one argument per line, lock nothing

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"

RADIUS="${RADIUS:-100}"
THICKNESS="${THICKNESS:-2}"
FONT="${FONT:-JetBrainsMono NF:weight=bold}"
FONT_SIZE="${FONT_SIZE:-20}"
TEXT_VER="${TEXT_VER-checking…}"
TEXT_WRONG="${TEXT_WRONG-wrong password}"
TEXT_CLEAR="${TEXT_CLEAR-cleared}"
TEXT_CAPS="${TEXT_CAPS-caps lock}"
FADE_IN="${FADE_IN:-0.6}"
DAEMONIZE="${DAEMONIZE:-1}"
DRYRUN="${DRYRUN:-0}"

# Alpha 00 on purpose, and not a palette token: "invisible" is structural, not a
# theme decision. The inside fill and the inner/outer border circles are the parts
# that made the old lock screen read as a big solid plate.
INVISIBLE="00000000"

# --- Palette (taste.md tokens, straight from the shell) ----------------------
declare -A C=()
if palette=$("$NIKI_HOME/scripts/palette.sh" get 2>/dev/null); then
    while IFS='=' read -r k v; do
        if [[ -n "$k" ]]; then C["$k"]="$v"; fi
    done <<<"$palette"
fi

# col <palette-key> [alpha] -> RRGGBB or RRGGBBAA, upper case, never empty.
# The alpha is appended rather than derived so a state can be exactly as quiet
# or as loud as it needs to be. Anything unusable falls back to Sunset Orange's
# token, so a half-published palette can never produce an invalid colour.
col() {
    local v="${C[$1]:-}" alpha="${2:-}"
    case "$v" in
        [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *)
            case "${1:-}" in
                bg) v=000000 ;;
                panel) v=0A0A0A ;;
                row) v=141010 ;;
                border) v=1A1210 ;;
                borderStrong) v=3D2B24 ;;
                accent) v=E85D2F ;;
                accentHover) v=FF8B4A ;;
                text) v=F7C7A1 ;;
                muted) v=7C8A6A ;;
                dim) v=555555 ;;
                danger) v=C30505 ;;
                *) v=000000 ;;
            esac
            ;;
    esac
    case "$alpha" in
        "" | [0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) alpha="" ;;
    esac
    printf '%s%s' "${v^^}" "$alpha"
}

# --- Background --------------------------------------------------------------
# Cosmetic, and strictly best-effort: the fallback below still locks.
bg=()
bg_image=""
if [[ -x "$NIKI_HOME/scripts/swaylock-bg.sh" ]]; then
    if bg_image=$("$NIKI_HOME/scripts/swaylock-bg.sh" 2>/dev/null | tail -n1); then
        [[ -s "$bg_image" ]] || bg_image=""
    fi
fi
if [[ -n "$bg_image" ]]; then
    bg=(--image "$bg_image" --scaling fill)
else
    # No wallpaper, no magick, or a failed render: lock on the canvas colour.
    # Never let the pretty path become the security path.
    bg=(--color "$(col bg)")
fi

# --- Flags -------------------------------------------------------------------
# No circle: --no-unlock-indicator keeps swaylock's indicator surface (which is
# what renders the password dots, the caps-lock note and the wrong-password
# flash) but skips the ring and the filled disc. Every ring-*/inside-* colour is
# therefore dropped from here — leaving them would be a lie about what the
# screen shows, and the state colours that still do something are the text ones.
args=(
    --fade-in "$FADE_IN"
    --font "$FONT"
    --font-size "$FONT_SIZE"

    # Backdrop, built above: --image ... --scaling fill, or --color.
    # No --clock — the clock is baked into that image (see header).
    "${bg[@]}"

    # A hairline to carry the keystroke arc, and nothing else. No --indicator:
    # without it swaylock draws nothing at all until the first keypress, so the
    # resting screen is just the wallpaper and the baked clock.
    --indicator-radius "$RADIUS"
    --indicator-thickness "$THICKNESS"

    # Belt and braces on the layout chip: -k is gone, and -K guarantees swaylock
    # cannot decide to show "English (US)" on its own either.
    --hide-keyboard-layout
    --submit-on-touch

    # The plate is gone — that opaque disc was most of what made the old screen
    # feel heavy. Same for the inner/outer border circles, which sit at
    # arc_radius +/- thickness/2 and would otherwise draw a second pair of rings.
    --inside-color "$INVISIBLE"
    --inside-clear-color "$INVISIBLE"
    --inside-ver-color "$INVISIBLE"
    --inside-wrong-color "$INVISIBLE"
    --inside-caps-lock-color "$INVISIBLE"
    --line-color "$INVISIBLE"
    --line-clear-color "$INVISIBLE"
    --line-ver-color "$INVISIBLE"
    --line-wrong-color "$INVISIBLE"
    --line-caps-lock-color "$INVISIBLE"

    # The hairline. Low alpha at rest so it reads as a hairline and not a shape.
    --ring-color "$(col accent a6)"
    --ring-clear-color "$(col accent 59)"
    --ring-ver-color "$(col accentHover ff)"
    --ring-wrong-color "$(col danger ff)"
    --ring-caps-lock-color "$(col accentHover ff)"

    # ---- the keystroke reaction ----------------------------------------------
    # This is the whole of "I can see that I'm typing", because this build draws
    # no dots: a 60 degree arc that jumps to a new random angle on every keypress.
    # It is stroked with --indicator-thickness, so THICKNESS is also this
    # reaction's visibility, which is why it is not 1. Backspace gets a dimmer
    # colour than a letter, so you can see the difference without reading it.
    --key-hl-color "$(col accentHover ff)"
    --bs-hl-color "$(col muted ff)"
    --caps-lock-key-hl-color "$(col accentHover ff)"
    --caps-lock-bs-hl-color "$(col muted ff)"
    --separator-color "$(col accentHover ff)"

    # ---- the state messages --------------------------------------------------
    # One word per state, each in that state's colour, so "what just happened" is
    # always answerable without guessing:
    #   Enter pressed -> accent      "checking…" while PAM runs
    #   wrong password -> danger     "wrong password"
    #   field emptied  -> muted      "cleared" (Escape, backspace on empty, or
    #                                 the auto-clear after a failed attempt)
    #   caps lock on   -> accent     "caps lock"
    # Kept short on purpose: 2*RADIUS is the widest they can be before the
    # indicator surface has to grow past the hairline.
    --text-color "$(col text ff)"
    --text-clear-color "$(col muted ff)"
    --text-ver-color "$(col accentHover ff)"
    --text-wrong-color "$(col danger ff)"
    --text-caps-lock-color "$(col accentHover ff)"

    --text-ver "$TEXT_VER"
    --text-wrong "$TEXT_WRONG"
    --text-clear "$TEXT_CLEAR"
    --text-caps-lock "$TEXT_CAPS"
)

if [[ "$DAEMONIZE" == 1 ]]; then
    args+=(--daemonize)
fi

if [[ "$DRYRUN" == 1 ]]; then
    printf '%s\n' swaylock "${args[@]}"
    exit 0
fi

# A short screen transition under the fade-in; swaylock covers the screen
# immediately either way, so a failure here must not cost us the lock.
niri msg action do-screen-transition --delay-ms 300 >/dev/null 2>&1 || true

exec swaylock "${args[@]}"