#!/usr/bin/env bash
# swaylock-bg.sh — the pixels *behind* the lock screen.
#
# Prints the path of a finished, full-screen JPG on stdout and nothing else, so
# `bg=$(./scripts/swaylock-bg.sh)` is safe. Exits 0 whenever any image came out;
# non-zero only when it genuinely cannot produce one (no magick, every render
# failed) — scripts/swaylock.sh then falls back to a flat colour. Never exit
# non-zero for a cosmetic reason: the user is standing there waiting to lock.
#
# WHY THE WHOLE LAYOUT IS BAKED IN HERE
# -------------------------------------
# swaylock takes the output with ext-session-lock-v1, which is exclusive: it is
# the only client allowed to draw, so *nothing* can be layered on top of it — no
# quickshell overlay, no second surface, not even a layer-shell panel. The only
# live pixels it owns are its own unlock ring and the keyboard-layout box.
# Therefore the designed lock screen (big clock top-left, date under it, a phone
# style widget row under that) has to be composited into the background image by
# this script, and only the ring is left live on top of it. The flip side: baked
# text goes stale if the screen stays locked past the minute it was rendered for,
# which is why the text stage is cached per-minute and drawn in ~0.3s rather than
# being part of a slow render.
#
# THE BACKDROP
# ------------
# The current wallpaper, blurred enough that no detail survives (it is on screen
# the whole time the session is locked) but *not* so far that it becomes a flat
# blob — a lock screen that hides its own wallpaper is just a black rectangle.
# Two darkening passes, with two different jobs:
#
#   DARKEN=0.40   a flat scrim over the whole frame. Low, because this is a
#                 scrim and not a blackout; 0.75 left the picture at 25% and
#                 that is what made the wallpaper look "not applied".
#   SCRIM=0.55    a left-to-right ramp that fades to nothing at SCRIM_SPAN=64%
#                 of the width. This is the pass that makes the baked clock,
#                 date and widget row readable, and it stops there: the right
#                 two thirds of the wallpaper keeps its brightness.
#
# On top of that a gentle vignette, and a fixed-seed film grain which is not
# decoration — a near-black gradient bands horribly on an AMOLED panel and
# dither is the only cure. Fixed seed because the grain is *texture*, not noise:
# two locks on an unchanged wallpaper must produce identical bytes.
# Colours come from scripts/palette.sh (the shell's live theme, so wallust and
# ThemePicker both feed the lock screen) — never a hex literal in this file.
#
# PERFORMANCE — two stages, two caches
# ------------------------------------
# Everything expensive is static, everything volatile is cheap, so the work is
# split:
#
#   plate (.state/swaylock-plate.jpg)  wallpaper + blur + scrims + vignette +
#                                      grain. Cached on wallpaper path/mtime/
#                                      size, the palette, the screen size and
#                                      the blur/geometry knobs.
#   final (.state/swaylock-bg.jpg)     plate + freshly drawn text, cached on the
#                                      plate key *plus the minute* and the
#                                      widget-row text, so re-locking inside the
#                                      same minute is a stat plus a read.
#
# The text pass is a single magick over the plate. All blur/gradient work runs on
# a SCALE-divisor canvas and is upscaled: a full-res `-blur 0x110` measured 13.5s
# on this machine, the same thing at a quarter of the size takes ~0.2s and looks
# identical (it is smooth by construction — there is no detail left to lose).
# Grain is the one exception: it is applied at full resolution, because upscaled
# noise turns into 4x4 blocks and stops reading as film.
# Measured on this machine (1920x1080, idle): plate ~0.7s, text pass ~0.2s, the
# stat-and-compare cache hit ~0.05s of real work (the rest is bash forking and
# palette.sh, which is 0.16s on its own). The clock the user waits for is
# therefore the text pass on every lock but the first after a wallpaper, theme
# or minute change.
#
# ImageMagick gotchas this file obeys (all of them cost real debugging time):
#   * `magick A B -compose Over -composite` puts B (the LAST image) on top. No
#     `-swap` needed — and no `-swap` wanted, it silently produced wrong output.
#   * A parenthesised group must end with exactly one image on the stack, or the
#     next -composite dies with "image sequence is required".
#   * Flat colour + shape as its alpha = `-alpha off -compose CopyOpacity
#     -composite`. A three-image masked composite does not do what it looks like.
#   * `gradient:` takes exactly TWO colours; a three-stop fade is one gradient
#     mirrored with +append.
#   * `+repage` after any resize inside a group, or the offsets drift.
#   * Every temp file gets a real extension (.jpg) — ImageMagick cannot infer a
#     format from a dotless name and fails with "no decode delegate".
#   * `-evaluate set 0.75` does *not* mean 75% (it divides by QuantumRange and
#     gives you 1e-5), and `-evaluate add 0.65` is the same trap in the other
#     direction — add/subtract want a percentage ("65%"), multiply wants a
#     fraction ("0.75"). Both fail silently, which is worse than an error.
#
# Every knob below is overridable from the environment and is part of the cache
# key, so an override renders a fresh image instead of silently reusing the old
# one. Two knobs that are *not* here on purpose: no CLOCK toggle (the whole point
# is the clock) and no ring — swaylock draws that.
#
#   BACKDROP=none          skip the wallpaper entirely (plain palette bg + grain)
#   ./scripts/swaylock-bg.sh && swaylock --image "$(./scripts/swaylock-bg.sh)"

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
STATE_DIR="$NIKI_HOME/.state"

# Each stage is "<image>.jpg" plus "<image>.fp" next to it (see cache_hit).
PLATE="$STATE_DIR/swaylock-plate.jpg"
FINAL="$STATE_DIR/swaylock-bg.jpg"

# --- Knobs ------------------------------------------------------------------
# [stage] P = painted into the plate (invalidates the plate cache),
#         F = drawn on top of the plate (only the per-minute cache).
BACKDROP="${BACKDROP:-wallpaper}" # [P] wallpaper | none
SCALE="${SCALE:-4}"               # [P] working canvas divisor: everything is computed at W/SCALE and upscaled once
BLUR_SIGMA="${BLUR_SIGMA:-9}"     # [P] gaussian sigma *at that canvas* (9 at /4 ≈ sigma 36 on screen)
DARKEN="${DARKEN:-0.40}"          # [P] black scrim over the blurred wallpaper; 0.75 was so dark the wallpaper vanished
SCRIM="${SCRIM:-0.55}"            # [P] extra darkening on the left, for the baked text
SCRIM_SPAN="${SCRIM_SPAN:-64}"    # [P] width of that left gradient, % of the screen (it fades to nothing by here)
DOT_GLOW="${DOT_GLOW:-0.42}"      # [P] centred darkening so the password dots read on any wallpaper
VIGNETTE="${VIGNETTE:-0.26}"      # [P] 0 = no vignette, 0.26 = subtly darker corners
GRAIN="${GRAIN:-0.06}"             # [P] film grain amplitude; 0 disables (banding risk)
SEED="${SEED:-42}"                 # [P] fixed so an unchanged wallpaper is byte-identical
PLATE_QUALITY="${PLATE_QUALITY:-92}" # [P]
QUALITY="${QUALITY:-92}"           # [F] JPEG quality of the finished image

PAD_X="${PAD_X:-110}"              # [F] left padding, px
PAD_Y="${PAD_Y:-96}"               # [F] top padding = top of the clock digits, px
TIME_SIZE="${TIME_SIZE:-168}"      # [F] clock pointsize (bold)
DATE_SIZE="${DATE_SIZE:-44}"       # [F] date pointsize (regular)
ROW_SIZE="${ROW_SIZE:-32}"         # [F] widget-row pointsize (regular)
DATE_GAP="${DATE_GAP:-30}"         # [F] clock baseline -> top of the date, px
ROW_GAP="${ROW_GAP:-38}"           # [F] baseline-to-baseline between widget lines, px (1.19em; 26 was tried and the date's descenders collided with row 1)
ROWS="${ROWS:-4}"                  # [F] max widget lines drawn. 4, not 3: weather is
                                  # two lines, so a third slot would push the
                                  # battery off the bottom the moment music
                                  # started playing.
RULE="${RULE:-1}"                  # [F] 0 = no accent rule above the clock
RULE_W="${RULE_W:-220}"            # [F] accent rule width, px
RULE_H="${RULE_H:-3}"              # [F] accent rule height, px
RULE_GAP="${RULE_GAP:-34}"         # [F] gap between the rule and the top of the clock
RULE_ALPHA="${RULE_ALPHA:-0.9}"    # [F] rule opacity; it wears out to nothing on the right
CAP_RATIO="${CAP_RATIO:-74}"       # [F] cap height above the baseline, % of pointsize (measured: 124/168 on JetBrainsMono NF)
TIMESTR="${TIMESTR:-%H:%M}"        # [F] strftime for the clock
DATESTR="${DATESTR:-%A, %B %-d}"   # [F] strftime for the date

# The hint is the lock screen's only *resting* affordance. Without --indicator,
# swaylock draws nothing at all until the first keypress, so on its own the
# screen is a wallpaper with a clock and no invitation to type — and because
# this build renders no password dots, there is nothing else that can say where
# the input goes. It sits above where the hairline appears, centred, and it is
# baked in because the same ext-session-lock-v1 constraint that hides the bar
# from us also stops a live overlay.
HINT="${HINT:-1}"                   # [F] 0 = no hint
HINT_TEXT="${HINT_TEXT:-$'\uF023  enter password'}" # [F] nf-fa-lock, then the words
HINT_SIZE="${HINT_SIZE:-26}"        # [F] pointsize
HIND_RADIUS="${HIND_RADIUS:-100}"   # [F] must match RADIUS in scripts/swaylock.sh
HINT_GAP="${HINT_GAP:-40}"          # [F] gap between the hairline's BOTTOM edge and the hint. Below,
                                  # not above: the top of the circle is where the fourth
                                  # widget row lands (its baseline is H/2-144), so a hint
                                  # up there overlapped "artist — title" text.
MAX_COLS="${MAX_COLS:-70}"          # [F] hard cap on a widget row, characters. Keeps a long
                                  # track name from running to the right edge and out of
                                  # the column; the ellipsis is applied by the trimmer.
LOCK_INFO="${LOCK_INFO:-$NIKI_HOME/scripts/lock-info.sh}" # [F] widget-row source
# Sections to ask for, passed straight through as lock-info.sh's one
# argument (it takes a comma/space list). Empty = its default set, which is
# "weather media battery". Set it to e.g. "weather,battery" to drop the
# now-playing row. Part of the cache key: changing it must re-render.
LOCK_INFO_SECTIONS="${LOCK_INFO_SECTIONS:-}" # [F]

FONT_BOLD="${FONT_BOLD:-JetBrainsMono-NF-Bold}"    # [F] ImageMagick font *names*
FONT_REGULAR="${FONT_REGULAR:-JetBrainsMono-NF-Regular}" # [F] (not the fontconfig "Family:weight=" form — magick -font cannot parse that)

# A typo'd knob must not take the lock screen down with it: every number falls
# back to its default instead of failing the arithmetic below.
numvar() {
    local -n _nref="$1"
    [[ "$_nref" =~ ^[0-9]+$ ]] || _nref="$2"
}
numvar SCALE 4
numvar BLUR_SIGMA 9
numvar DARKEN 0.40
numvar SCRIM 0.55
numvar SCRIM_SPAN 64
numvar DOT_GLOW 0.42
numvar VIGNETTE 0.26
numvar GRAIN 0.06
numvar SEED 42
numvar PLATE_QUALITY 92
numvar QUALITY 92
numvar PAD_X 110
numvar PAD_Y 96
numvar TIME_SIZE 168
numvar DATE_SIZE 44
numvar ROW_SIZE 32
numvar DATE_GAP 30
numvar ROW_GAP 38
numvar ROWS 4
numvar RULE_W 220
numvar RULE_H 3
numvar RULE_GAP 34
numvar RULE_ALPHA 0.9
numvar CAP_RATIO 74
numvar HINT_SIZE 26
numvar HIND_RADIUS 100
numvar HINT_GAP 40
numvar MAX_COLS 70

# True for every spelling of zero: 0, 0.0, 0.00, .0, 000.
#
# Implemented by stripping everything that is not a digit and comparing the
# integer. The obvious version — strip everything that is not 0 or '.' and test
# for empty — is wrong in the dangerous direction: "1" and "26" contain no 0 or
# '.', so both strip to "" and both come back as zero. That silently switched off
# the accent rule (RULE=1) and the resting hint (HINT=1) and nobody noticed,
# because the failure mode was "feature quietly absent".
is_zero() {
    local digits="${1//[!0-9]/}"
    [[ -z "$digits" ]] && return 0
    ((10#$digits == 0))
}

# The widget-row source, called with the optional sections list as ONE extra
# argument. A helper rather than inline so the array stays word-split correctly
# (the path may contain spaces, and ${arr[@]+...} is the only way to expand an
# empty array safely under `set -u`).
run_lock_info() {
    local -a args=()
    [[ -n "$LOCK_INFO_SECTIONS" ]] && args=("$LOCK_INFO_SECTIONS")
    "$LOCK_INFO" ${args[@]+"${args[@]}"} 2>/dev/null || true
}

# mix <hex> <hex> <weight> -> hex, blending the second colour into the first by
# weight percent. Needed because the theme's `muted` is tuned for a bar sitting on
# a dark panel, and here the same token has to stay readable over an arbitrary
# blurred photograph — brightening it by hand per theme would just move the
# problem, and hardcoding a lighter grey would ignore the live palette.
#
# Defined up here, before the palette block, because the very first thing the
# palette block does is call it.
mix() {
    local a=$1 b=$2 w=$3
    printf '%02X%02X%02X' \
        $(((0x${a:0:2} * (100 - w) + 0x${b:0:2} * w) / 100)) \
        $(((0x${a:2:2} * (100 - w) + 0x${b:2:2} * w) / 100)) \
        $(((0x${a:4:2} * (100 - w) + 0x${b:4:2} * w) / 100))
}

case "$BACKDROP" in
none) BACKDROP=none ;;
*) BACKDROP=wallpaper ;;
esac

# --- Palette (live theme; taste.md tokens, never literals here) --------------
declare -A C=()
while IFS='=' read -r k v; do
    [[ -n "$k" ]] && C["$k"]="${v//#/}"
done < <("$NIKI_HOME/scripts/palette.sh" get 2>/dev/null || true)

hex() {
    local v="${C[$1]:-}"
    [[ "$v" =~ ^[0-9a-fA-F]{6}$ ]] && printf '%s' "${v,,}" || printf '%s' "$2"
}
ACCENT="$(hex accent e85d2f)"
TEXT="$(hex text f7c7a1)"
MUTED="$(hex muted 7c8a6a)"
BG="$(hex bg 000000)"
# Hierarchy by brightness rather than by hue: the date reads closer to full text
# and the widget rows stay a step quieter, but neither is allowed to sink into a
# bright wallpaper.
DATE_FG="$(mix "$MUTED" "$TEXT" 60)"
ROW_FG="$(mix "$MUTED" "$TEXT" 45)"
HINT_FG="$(mix "$MUTED" "$TEXT" 50)"

# --- Cache keys -------------------------------------------------------------

mkdir -p "$STATE_DIR"

# --- Screen size (primary output) -------------------------------------------
# One image for every output (swaylock has one --image for all of them), so this
# is the *first* output in niri's dump: right for the single-laptop setup here,
# and stretching rather than cropping on a mixed-DPI multi-monitor desk.
W=1920 H=1080
if outputs=$(niri msg outputs 2>/dev/null); then
    # "Current mode: 1920x1080 @ 60.049 Hz" is the live one; the fallback picks
    # up the first WxH anywhere in the dump if niri ever stops printing it.
    if [[ $outputs =~ Current[[:space:]]mode:[[:space:]]([0-9]{3,5})x([0-9]{3,5}) ]]; then
        W="${BASH_REMATCH[1]}" H="${BASH_REMATCH[2]}"
    elif [[ $outputs =~ ([0-9]{3,5})x([0-9]{3,5}) ]]; then
        W="${BASH_REMATCH[1]}" H="${BASH_REMATCH[2]}"
    fi
fi
# Working canvas: every blur, scrim and gradient is computed here and upscaled
# once at the end. It is derived from SCALE and — this matters — the base image
# is forced to exactly these dimensions *before* anything is composited onto it.
# An earlier version blurred to a "BLUR_WIDTH" of its own and then laid a
# w×h scrim over a wider base; the uncovered strip on the right, and the
# -extent crop on the vignette, both baked visible rectangular seams into the
# wallpaper. One canvas, sized once, is the whole fix.
((SCALE >= 1)) || SCALE=1
w=$((W / SCALE)) h=$((H / SCALE))
((w > 32)) || w=32
((h > 32)) || h=32

# --- Source image -----------------------------------------------------------
# workspace.* is format-swapped by scripts/wallpaper.sh (jpg/png/webp), so glob
# it; the .json sidecar a downloader drops next to it is not an image.
src=""
if [[ "$BACKDROP" != "none" ]]; then
    for f in "$NIKI_HOME"/wallpapers/workspace.*; do
        [[ -f "$f" ]] || continue
        case "${f##*.}" in
        jpg | jpeg | png | webp | avif) src="$f" ;;
        esac
    done
    # No wallpaper is not a reason to skip the pretty path; it is a reason to
    # skip the wallpaper.
    [[ -n "$src" ]] || BACKDROP=none
fi

# --- Text to bake ------------------------------------------------------------
clock_str=$(date +"$TIMESTR" 2>/dev/null || true)
date_str=$(date +"$DATESTR" 2>/dev/null || true)

# Widget row: scripts/lock-info.sh prints one short line per widget, ready to
# draw. It may not exist yet (it is optional), may print nothing, or may fail —
# all of that just means fewer lines, never a failed lock. Quotes and backslashes
# are stripped because the text goes through MVG (-draw), where they would end
# the string.
rows=()
if [[ -x "$LOCK_INFO" || -r "$LOCK_INFO" ]]; then
    # MIN() semantics by hand: MAX_COLS is the typographic limit (a track name
    # should not run to the right edge), the width-derived one is the hard limit.
    max_chars=$(((W - 2 * PAD_X) / (ROW_SIZE * 6 / 10))) # JetBrains Mono advance = 0.6em
    ((max_chars > MAX_COLS)) && max_chars=$MAX_COLS
    ((max_chars > 8)) || max_chars=8
    n=0
    while IFS= read -r line; do
        ((n >= ROWS)) && break
        # Bash-only trimming: this loop runs on every lock, and a sed per line is
        # three forks of pure waste. Quotes and backslashes go because the text is
        # drawn through MVG, where they would close the string.
        line="${line//$'\r'/ }"
        line="${line//[$'\x01'-$'\x1f']/ }"
        line="${line//\\/ }"
        line="${line//\'/ }"
        line="${line//\"/ }"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        if ((${#line} > max_chars)); then
            line="${line:0:max_chars}"
            # Bash slices characters under a UTF-8 locale but bytes under LANG=C,
            # where a cut can land inside a glyph like ° — drop the stray
            # continuation byte if there is one (a no-op in UTF-8). case, not
            # =~: bash's regex engine rejects that byte range as a collation
            # character in a UTF-8 locale.
            case "${line: -1}" in
            [$'\x80'-$'\xbf']) line="${line%?}" ;;
            esac
            line+="…"
        fi
        rows+=("$line")
        n=$((n + 1))
    done < <(run_lock_info)
fi

# --- Baselines --------------------------------------------------------------
# -draw "text x,y" puts y on the *baseline* (verified: digits at 168px span
# 124px above it), so every line is placed on a baseline grid derived from the
# measured cap height. That keeps the widget lines evenly spaced whatever
# glyphs they happen to contain, which ink-anchored top alignment would not.
time_base=$((PAD_Y + TIME_SIZE * CAP_RATIO / 100))
date_base=$((time_base + DATE_GAP + DATE_SIZE * CAP_RATIO / 100))
rule_y=$((PAD_Y - RULE_GAP - RULE_H))

# --- Cache keys -------------------------------------------------------------
# The whole palette goes into the key, not just the colours the plate paints:
# wallust and ThemePicker repaint the lock screen, and a stale plate would
# quietly ignore them. It is free — palette.sh has already run by now.
palette_key=""
for k in bg panel row border borderStrong accent accentHover text muted dim danger; do
    palette_key+="${C[$k]:-}|"
done

knobs="v3|$BACKDROP|$SCALE|$BLUR_SIGMA|$DARKEN|$SCRIM|$SCRIM_SPAN|$DOT_GLOW|$VIGNETTE|$GRAIN|$SEED|$PLATE_QUALITY|$W|$H|$palette_key|${FONT_BOLD}|${FONT_REGULAR}"
if [[ -n "$src" ]]; then
    plate_fp="$knobs|$(stat -c '%n:%s:%Y' "$src" 2>/dev/null || printf '%s' "$src")"
else
    plate_fp="$knobs|none"
fi
# The text stage changes every minute and whenever a widget line changes value.
final_fp="$plate_fp|$(date +%Y%m%d%H%M)|$TIMESTR|$DATESTR|$clock_str|$date_str|${#rows[@]}|${rows[*]-}|$LOCK_INFO_SECTIONS|$HIND_RADIUS|$HINT_GAP|$HINT_TEXT"

# A cache file that exists is not a cache file that works. `magick identify` on a
# truncated JPEG still exits 0 ("premature end of file" is a warning, and
# -regard-warnings does not change the exit code), so it cannot be used to prove
# the file is intact. What does work is recording the byte size next to the
# fingerprint and comparing: one stat, exact, and a truncated or garbage cache
# file misses and gets re-rendered.
cache_hit() {
    local file=$1 key=$2 stored size
    [[ -s "$file" && -s "$file.fp" ]] || return 1
    stored=$(cat "$file.fp" 2>/dev/null || true)
    [[ "$stored" == "$key|"* ]] || return 1
    size=${stored##*|}
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    [[ "$(stat -c%s "$file" 2>/dev/null || printf 0)" == "$size" ]]
}

if cache_hit "$FINAL" "$final_fp"; then
    printf '%s\n' "$FINAL"
    exit 0
fi

command -v magick >/dev/null 2>&1 || exit 1
have_plate=0
cache_hit "$PLATE" "$plate_fp" && have_plate=1

# Every render writes the temp file, renames it into place and only then records
# the fingerprint plus the size that must match it next time. A crash between the
# two leaves a stale fp and a missing hit, never a stale hit.
stamp() { printf '%s|%s' "$2" "$(stat -c%s "$1" 2>/dev/null || printf 0)" >"$1.fp"; }

render_plate() {
    local tmp="$STATE_DIR/.swaylock-plate.$$.jpg"
    local args=()

    # Everything except the grain happens on the working canvas. The scrims and
    # the vignette are flat/gradient maths on an already-blurred image —
    # computing them small and upscaling once is identical on screen and saves
    # ~0.4s of full-resolution compositing.
    if [[ "$BACKDROP" == "none" ]]; then
        args=(-size "${w}x${h}" "xc:#$BG" -alpha off)
    else
        # Only W/SCALE pixels of this wallpaper ever survive, so ask the decoders
        # for a scaled read. Best-effort and format-specific (libjpeg scales by
        # powers of two, libpng only honours it for images written with a resize
        # chunk), so it can only ever save work — never change the result, since
        # the resize and the blur run afterwards either way.
        #
        # BLUR_SIGMA is read as "sigma at this canvas", so the on-screen blur
        # scales with SCALE: 9 at /4 is sigma 36 on screen, which still reads as
        # a photograph but loses the detail a shoulder-surfer could read. The
        # old 18-at-480 was sigma 72 and turned every wallpaper into one flat
        # colour blob, which is what "I can't see my wallpaper" actually was.
        args=(
            -define jpeg:size=1024x1024
            -define png:size=1024x1024
            -define webp:size=1024x1024
            "$src"
            -resize "${w}x${h}^" +repage -gravity center -extent "${w}x${h}" +repage
            -blur "0x${BLUR_SIGMA}" -alpha off
        )

        # DARKEN: a flat black layer at this opacity over the whole frame.
        # Copying alpha with -evaluate multiply is the honest way to say that
        # (see gotchas). Kept low on purpose — this is a *lock* screen, so the
        # picture is on display the whole time and must not be a privacy leak,
        # but DARKEN is a scrim, not a blackout.
        if ! is_zero "$DARKEN"; then
            args+=(
                '(' -size "${w}x${h}" xc:black -alpha set
                -channel A -evaluate multiply "$DARKEN" +channel ')'
                -compose Over -composite
            )
        fi

        # SCRIM: the same trick again, but masked by a left-to-right ramp so the
        # baked clock/date/widget block always has contrast to sit on while the
        # right-hand two thirds of the wallpaper stays bright. A flat scrim over
        # the whole frame is what made the text readable *and* the wallpaper
        # invisible; this splits the two jobs.
        if ! is_zero "$SCRIM" && ! is_zero "$SCRIM_SPAN"; then
            span=$(((w * SCRIM_SPAN) / 100))
            ((span > 8)) || span=8
            args+=(
                '(' -size "${w}x${h}" xc:black -alpha set
                # gradient: is vertical; rotate 270 puts white at the left, which
                # becomes full opacity under CopyOpacity.
                '(' -size "1x${span}" gradient:white-black -rotate 270 +repage
                -resize "${w}x${h}!" +repage ')'
                -alpha off -compose CopyOpacity -composite
                -channel A -evaluate multiply "$SCRIM" +channel ')'
                -compose Over -composite
            )
        fi
    fi

    # DOT_GLOW: a centred ellipse of extra darkening, and the only reason the
    # password dots are readable on *any* wallpaper. swaylock is now
    # --no-unlock-indicator, so there is no ring and no filled disc behind the
    # text — just the picture — and pale text over a pale photograph is
    # unreadable. It is symmetric and soft, so it reads as one more layer of the
    # vignette stack rather than as a panel someone drew.
    if ! is_zero "$DOT_GLOW"; then
        # Same remap as the vignette, inverted: multiply alone would grey the
        # frame as well, so scale the raw ramp down by DOT_GLOW and lift it back
        # up to 1-DOT_GLOW at the edges. Centre lands on 1-DOT_GLOW (darkened by
        # exactly DOT_GLOW), edges land on 1.0 (untouched).
        glow_floor=$(awk -v g="$DOT_GLOW" 'BEGIN{printf "%.2f%%", (1 - g) * 100}')
        args+=(
            '(' -size "${w}x${h}" radial-gradient:black-white
            -resize "${w}x${h}!" +repage
            -evaluate multiply "$DOT_GLOW" -evaluate add "$glow_floor" ')'
            -compose Multiply -composite
        )
    fi

    # Vignette: white in the middle fading to black past the corners. Built by
    # stretching a radial gradient straight onto the canvas — the old
    # "-resize 160% + -extent" version cropped the middle out of the oversized
    # gradient and stopped the multiply at a hard rectangle. The ramp is
    # remapped so 1.0 stays 1.0 and 0 becomes 1-VIGNETTE: multiplying the raw
    # gradient by VIGNETTE would dim the whole picture by VIGNETTE as well,
    # which is a second scrim on top of DARKEN, not a vignette.
    if ! is_zero "$VIGNETTE"; then
        # -evaluate add takes a *percentage*, not a fraction: -evaluate add 0.65
        # adds 1e-5 and silently does nothing (same family of trap as set 0.75).
        vig_floor=$(awk -v v="$VIGNETTE" 'BEGIN{printf "%.2f%%", (1 - v) * 100}')
        args+=(
            '(' -size "${w}x${h}" radial-gradient:white-black
            -resize "${w}x${h}!" +repage
            -evaluate multiply "$VIGNETTE" -evaluate add "$vig_floor" ')'
            -compose Multiply -composite
        )
    fi

    # The single upscale to the screen: cover it, then centre-crop, because the
    # wallpaper can be any aspect and swaylock is told --scaling fill.
    args+=(-resize "${W}x${H}^" +repage -gravity center -extent "${W}x${H}" +repage -alpha off)

    # Grain last, at full resolution and with a fixed seed: it dithers the
    # gradient the scrim just made, which is exactly where the banding lives.
    # Upscaled noise would be 4x4 blocks, so this one is not cheapened.
    if ! is_zero "$GRAIN"; then
        args+=(-seed "$SEED" -attenuate "$GRAIN" +noise Gaussian)
    fi

    args+=(-quality "$PLATE_QUALITY" -sampling-factor 4:4:4 "$tmp")
    if magick "${args[@]}" 2>/dev/null && [[ -s "$tmp" ]]; then
        mv -f "$tmp" "$PLATE"
        stamp "$PLATE" "$plate_fp"
        return 0
    fi
    rm -f "$tmp"

    # Last resort, and the one case where a *failure* is still a lock: a
    # half-written workspace.jpg from the wallpaper daemon, an unreadable file,
    # a missing delegate. Fall back to the palette's own background plus the same
    # grain — the clock and the date still render, only the wallpaper is gone.
    local flat=(-size "${W}x${H}" "xc:#$BG" -alpha off)
    if ! is_zero "$GRAIN"; then
        flat+=(-seed "$SEED" -attenuate "$GRAIN" +noise Gaussian)
    fi
    if magick "${flat[@]}" -quality "$PLATE_QUALITY" -sampling-factor 4:4:4 "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        mv -f "$tmp" "$PLATE"
        stamp "$PLATE" "$plate_fp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

render_final() {
    local tmp="$STATE_DIR/.swaylock-bg.$$.jpg"
    # No -gravity anywhere in here on purpose: gravity changes what a -draw point
    # means (with NorthWest it becomes the text's bounding-box corner instead of
    # the baseline) and the layout below is computed on baselines. Gravity None
    # also leaves -geometry offsets measured from the top-left, which is what the
    # accent rule wants.
    local args=("$PLATE")

    # Accent rule: taste.md restraint, one hairline that wears out to nothing so
    # it never ends in a hard edge.
    if ! is_zero "$RULE"; then
        if ! is_zero "$RULE_ALPHA"; then
            args+=(
                '(' -size "${RULE_W}x${RULE_H}" "xc:#$ACCENT"
                # gradient: is vertical; rotate 270 puts white at the left, which
                # becomes full opacity under CopyOpacity.
                '(' -size "1x${RULE_W}" gradient:white-black -rotate 270 +repage
                -resize "${RULE_W}x${RULE_H}!" +repage ')'
                -alpha off -compose CopyOpacity -composite
                -channel A -evaluate multiply "$RULE_ALPHA" +channel ')'
                -geometry "+${PAD_X}+${rule_y}" -compose Over -composite
            )
        else
            args+=(-fill "#$ACCENT" -draw "rectangle ${PAD_X},${rule_y} $((PAD_X + RULE_W)),$((rule_y + RULE_H))")
        fi
    fi

    if [[ -n "$clock_str" ]]; then
        args+=(-font "$FONT_BOLD" -pointsize "$TIME_SIZE" -fill "#$TEXT" \
            -draw "text ${PAD_X},${time_base} '$clock_str'")
    fi
    if [[ -n "$date_str" ]]; then
        args+=(-font "$FONT_REGULAR" -pointsize "$DATE_SIZE" -fill "#$DATE_FG" \
            -draw "text ${PAD_X},${date_base} '$date_str'")
    fi
    local i=0
    while ((i < ${#rows[@]})); do
        args+=(-font "$FONT_REGULAR" -pointsize "$ROW_SIZE" -fill "#$ROW_FG" \
            -draw "text ${PAD_X},$((date_base + ROW_GAP * (i + 1))) '${rows[i]}'")
        i=$((i + 1))
    done

    # The resting hint, last, because it is the one draw that needs -gravity: with
    # gravity North the x offset is measured from the horizontal centre, so "0" is
    # the middle of the screen and the string does not have to be measured here.
    # Placed above the hairline swaylock will draw when you press a key, so the two
    # never overlap.
    if ! is_zero "$HINT" && [[ -n "$HINT_TEXT" ]]; then
        hint_y=$(((H / 2) + HIND_RADIUS + HINT_GAP))
        hint_text="${HINT_TEXT//[$'\x01'-$'\x1f']/ }"
        hint_text="${hint_text//\\/ }"
        hint_text="${hint_text//\'/ }"
        hint_text="${hint_text//\"/ }"
        hint_text="${hint_text#"${hint_text%%[![:space:]]*}"}"
        hint_text="${hint_text%"${hint_text##*[![:space:]]}"}"
        if [[ -n "$hint_text" ]]; then
            args+=(-gravity North -font "$FONT_REGULAR" -pointsize "$HINT_SIZE" \
                -fill "#$HINT_FG" -draw "text 0,${hint_y} '$hint_text'")
        fi
    fi

    args+=(-quality "$QUALITY" -sampling-factor 4:4:4 "$tmp")
    if magick "${args[@]}" 2>/dev/null && [[ -s "$tmp" ]]; then
        mv -f "$tmp" "$FINAL"
        stamp "$FINAL" "$final_fp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

if ((have_plate == 0)); then
    # render_plate only returns non-zero if even the flat fallback failed, in
    # which case there is genuinely nothing to hand swaylock.
    render_plate || :
fi

if ! render_final; then
    # A corrupt plate (or anything else that made the text pass fail) gets one
    # clean retry from scratch before giving up.
    rm -f "$PLATE" "$PLATE.fp" "$FINAL" "$FINAL.fp"
    render_plate || exit 1
    render_final || exit 1
fi

printf '%s\n' "$FINAL"