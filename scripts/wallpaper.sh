#!/usr/bin/env bash
# wallpaper.sh <path>
#
# Set `path` as the wallpaper using the settings from scripts/wallpaper-process.sh
# (editable live from the shell's "Wallpaper process" pane). Single source of
# truth for tuning; this file holds no hardcoded policy.
#
# Performance notes (the whole point of the rewrite):
#   * The blurred `backdrop.*` file is NOT generated. Nothing reads it — the
#     overview is solid black (see niri/wallpapers.kdl) — and it cost ~1.4s per
#     change decoding a second time for nothing. A stale backdrop is removed.
#   * Images already within the downscale cap take a plain `cp` (~10ms). Most
#     wallpaper libraries are mostly <=1080p, so this is the common case.
#   * When a resize IS needed it is one magick pass that writes the workspace
#     *and* derives the canvas colour from it, instead of three separate
#     invocations (three full decodes of a 4K PNG).
#   * The niri KDL is rewritten only when the swaybg line actually changes.
#   * Re-setting the wallpaper that is already current is a no-op.

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
PROC_SH="$NIKI_HOME/scripts/wallpaper-process.sh"

image="${1:-}"
[[ -n "$image" ]] || {
    echo "[ERROR] Usage: $0 <path-to-image>" >&2
    exit 1
}
[[ -f "$image" ]] || {
    echo "[ERROR] Image not found: $image" >&2
    exit 1
}

WALLPAPER_DIR="$NIKI_HOME/wallpapers"
WALLPAPERS_KDL="$NIKI_HOME/niri/wallpapers.kdl"
STATE_FILE="$NIKI_HOME/.state/current_wallpaper"
FINGERPRINT_FILE="$NIKI_HOME/.state/current_wallpaper.fp"
COLOR_FILE="$NIKI_HOME/.state/current_wallpaper.color"

mkdir -p "$WALLPAPER_DIR" "$NIKI_HOME/.state"

t0="${EPOCHREALTIME/[.,]/}"
elapsed_ms() {
    local now="${EPOCHREALTIME/[.,]/}"
    echo $(((now - t0) / 1000))
}

# --- Settings: one fork, parsed into an array. Validated at `set` time. ---
declare -A S=()
while IFS='=' read -r k v; do
    [[ -n "$k" ]] && S["$k"]="$v"
done < <("$PROC_SH" get)

DOWNSCALE="${S[DOWNSCALE]:-1920x1080}"
FORMAT="${S[FORMAT]:-keep}"
JPEG_QUALITY="${S[JPEG_QUALITY]:-92}"
PNG_COMPRESSION="${S[PNG_COMPRESSION]:-6}"
CANVAS_COLOR="${S[CANVAS_COLOR]:-auto}"
WALLUST="${S[WALLUST]:-on}"
POST_CMD="${S[POST_CMD]:-}"

# --- Output target ---
norm_ext() {
    local e="${1,,}"
    [[ "$e" == "jpeg" ]] && e="jpg"
    printf '%s' "$e"
}

src_ext="$(norm_ext "${image##*.}")"
case "$FORMAT" in
    jpeg) out_ext="jpg" ;;
    png) out_ext="png" ;;
    *) out_ext="$src_ext" ;;
esac
case "$out_ext" in
    jpg | png | webp | avif) ;;
    *) out_ext="png" ;;
esac

workspace="$WALLPAPER_DIR/workspace.$out_ext"

# Fingerprint of every setting that affects the rendered bytes. If it is
# unchanged and the image is already current, there is nothing to redo.
fingerprint=$(printf '%s|%s|%s|%s|%s|%s' "$DOWNSCALE" "$FORMAT" "$JPEG_QUALITY" "$PNG_COMPRESSION" "$out_ext" "$src_ext" | md5sum | cut -d' ' -f1)

# Convert ImageMagick's `srgba(r%,g%,b%,a)` (or 0-255 form) to #RRGGBB.
to_hex() {
    local s="${1#srgba(}" r g b
    s="${s%%)*}"
    IFS=, read -r r g b _ <<<"$s"
    local out="" c ip n
    for c in "$r" "$g" "$b"; do
        # "48.4144%" -> 48 (percent form); "122.5" -> 122 (absolute form).
        ip="${c%%[^0-9]*}"
        [[ -n "$ip" ]] || ip=0
        if [[ "$c" == *% ]]; then
            n=$((ip * 255 / 100))
        else
            n=$((ip))
        fi
        ((n < 0)) && n=0
        ((n > 255)) && n=255
        printf -v c '%02X' "$n"
        out+="$c"
    done
    printf '#%s' "$out"
}

# Sample the top-left pixel of an existing image as #RRGGBB.
sample_color() {
    local raw
    raw=$(magick "$1" -resize 1x1 -format '%[pixel:p{0,0}]' info: 2>/dev/null || true)
    [[ -n "$raw" ]] && to_hex "$raw"
}

# Prune stale workspace variants: FORMAT (and the source extension) decide which
# workspace.* exists, so switching format would otherwise leave megabytes of dead
# files. Only image extensions are touched — other sidecars (e.g. a downloader's
# workspace.json) are none of this script's business. Safe to run on the no-op
# path too: the variant swaybg is using is always the one preserved.
prune_stale() {
    local f
    for f in "$WALLPAPER_DIR"/workspace.*; do
        [[ -e "$f" ]] || continue
        [[ "$f" == "$workspace" ]] && continue
        case "${f##*.}" in
        jpg | jpeg | png | webp | avif) rm -f "$f" ;;
        esac
    done
    return 0
}

# Restart swaybg on a given workspace and keep the niri config in sync.
apply_wallpaper() {
    local ws="$1" color="$2"
    pkill -x swaybg 2>/dev/null || true
    # Redirect swaybg's stdio: a backgrounded child holding the inherited stdout
    # keeps a pipe open, so callers that pipe or capture this script's output
    # (e.g. `wallpaper.sh ... | grep OK`) would hang until swaybg exits.
    swaybg -i "$ws" -m fill -c "$color" >>"$NIKI_HOME/.state/swaybg.log" 2>&1 &
    disown

    # The dead backdrop: drop it rather than leaving a stale multi-MB file around.
    rm -f "$WALLPAPER_DIR"/backdrop.* 2>/dev/null || true

    # Persist the swaybg line in niri config — only rewritten when it really
    # changes. Both the repo copy and the live ~/.config/niri copy are updated:
    # the live file is a separate file (not a symlink) and is the one niri
    # actually includes, so a stale colour there would be respawned at login.
    local live_kdl="$HOME/.config/niri/wallpapers.kdl"
    local f
    for f in "$WALLPAPERS_KDL" "$live_kdl"; do
        [[ -f "$f" ]] || continue
        # Skip if this is the same file reached twice (symlinked setups).
        [[ "$f" == "$WALLPAPERS_KDL" && "$f" == "$live_kdl" ]] && continue
        persist_swaybg_line "$f" "$ws" "$color"
    done
}

# Rewrite the single `spawn-sh-at-startup "swaybg ...` line in $1, in place.
persist_swaybg_line() {
    local file="$1" ws="$2" color="$3"
    local desired tmp line
    desired="spawn-sh-at-startup \"swaybg -i $ws -m fill -c '$color'\""
    grep -qxF "$desired" "$file" && return 0
    tmp="${file}.$$"
    local seen=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == 'spawn-sh-at-startup "swaybg'* ]]; then
            printf '%s\n' "$desired"
            seen=1
        else
            printf '%s\n' "$line"
        fi
    done <"$file" >"$tmp"
    # Only replace if a swaybg line actually existed; never clobber a file that
    # does not manage swaybg.
    if ((seen == 1)); then
        mv -f "$tmp" "$file"
    else
        rm -f "$tmp"
    fi
    return 0
}


# An explicit CANVAS_COLOR hex must reach swaybg even when the rendered image is
# byte-identical (the colour is not part of the fingerprint). Any CANVAS_COLOR
# change re-applies: reverting an explicit hex back to `auto` has to restore the
# sampled colour, not leave the override in place.
if [[ "$(cat "$STATE_FILE" 2>/dev/null || true)" == "$image" ]] \
    && [[ -f "$workspace" ]] \
    && [[ "$(cat "$FINGERPRINT_FILE" 2>/dev/null || true)" == "$fingerprint" ]]; then
    prune_stale
    if [[ "$(cat "$COLOR_FILE" 2>/dev/null || true)" != "$CANVAS_COLOR" ]]; then
        reapply=""
        case "$CANVAS_COLOR" in
        \#*) reapply="$CANVAS_COLOR" ;;
        none) reapply="#010102" ;;
        *) reapply="$(sample_color "$workspace")" ;;
        esac
        [[ -z "$reapply" ]] && reapply="#010102"
        apply_wallpaper "$workspace" "$reapply"
        printf '%s\n' "$CANVAS_COLOR" >"$COLOR_FILE"
        echo "[OK] Canvas colour updated to $reapply ($(elapsed_ms)ms)"
        exit 0
    fi
    echo "[OK] Wallpaper unchanged: $workspace ($(elapsed_ms)ms)"
    exit 0
fi

# --- Canvas colour ---

canvas_color=""
case "$CANVAS_COLOR" in
    none) canvas_color="none" ;;
    \#*) canvas_color="$CANVAS_COLOR" ;;
    *)
        canvas_color="auto"
        want_color=1
        ;;
esac

# --- Decide whether a resize is needed at all ---
need_resize=1
dims=""
if [[ "$DOWNSCALE" == "none" ]]; then
    need_resize=0
elif dims=$(magick identify -ping -format '%w %h' "$image" 2>/dev/null) && [[ -n "$dims" ]]; then
    read -r iw ih <<<"$dims"
    cw="${DOWNSCALE%x*}"
    ch="${DOWNSCALE#*x}"
    if ((iw <= cw && ih <= ch)); then
        need_resize=0
    fi
else
    # Probe failed (unreadable header): fall through to magick, which will
    # produce a proper error if the file really is broken.
    need_resize=1
fi

# A plain copy is possible when no resize is needed AND no format conversion.
pure_copy=0
if ((need_resize == 0)); then
    if [[ "$FORMAT" == "keep" ]] || [[ "$out_ext" == "$src_ext" ]]; then
        pure_copy=1
    fi
fi

if ((pure_copy == 1)); then
    cp -f "$image" "$workspace"
    if [[ "${want_color:-0}" == "1" ]]; then
        canvas_color=$(magick "$workspace" -resize 1x1 -format '%[pixel:p{0,0}]' info: 2>/dev/null || true)
        [[ -n "$canvas_color" ]] && canvas_color=$(to_hex "$canvas_color")
    fi
else
    # Single decode: resize (if needed) -> write workspace -> sample colour.
    margs=("$image")
    ((need_resize == 1)) && margs+=(-resize "${DOWNSCALE}>")
    [[ "$out_ext" == "jpg" ]] && margs+=(-quality "$JPEG_QUALITY")
    [[ "$out_ext" == "png" ]] && margs+=(-define "png:compression-level=$PNG_COMPRESSION")
    margs+=(-write "$workspace")
    if [[ "${want_color:-0}" == "1" ]]; then
        raw=$(magick "${margs[@]}" -resize 1x1 -format '%[pixel:p{0,0}]' info: 2>/dev/null || true)
        [[ -n "$raw" ]] && canvas_color=$(to_hex "$raw")
    else
        magick "${margs[@]}" -format '%w' info: >/dev/null 2>&1 || true
    fi
fi
[[ -z "$canvas_color" || "$canvas_color" == "auto" || "$canvas_color" == "none" ]] && canvas_color="#010102"

prune_stale

# --- Publish ---
printf '%s\n' "$image" >"$STATE_FILE"
printf '%s\n' "$fingerprint" >"$FINGERPRINT_FILE"
printf '%s\n' "$canvas_color" >"$COLOR_FILE"

apply_wallpaper "$workspace" "$canvas_color"

mode="magick"
((pure_copy == 1)) && mode="copy"
((need_resize == 1)) && mode="magick-resize"
echo "[OK] Wallpaper set: $workspace (color: $canvas_color, ${mode}, $(elapsed_ms)ms)"

# Wallust re-theme: fire-and-forget so it never slows or fails the change.
if [[ "$WALLUST" == "on" && -x "$NIKI_HOME/scripts/wallust-theme.sh" ]]; then
    { "$NIKI_HOME/scripts/wallust-theme.sh" "$image" >>"$NIKI_HOME/.state/wallust-theme.log" 2>&1 || true; } &
    disown || true
fi

# Optional user hook: runs after the wallpaper is live. Logged, never fatal.
if [[ -n "$POST_CMD" ]]; then
    { bash -c "$POST_CMD" >>"$NIKI_HOME/.state/wallpaper-post.log" 2>&1 || true; } &
    disown || true
fi