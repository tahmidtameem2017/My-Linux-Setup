#!/usr/bin/env bash
# wallpaper-process.sh — read/write store for the wallpaper change process.
#
# The change process (scripts/wallpaper.sh) and the daemon (scripts/auto-wallpaper.sh)
# both read this file. It was edited live from the Quickshell "Wallpaper process"
# editor pane; that pane is gone (deleted with Settings Center on 2026-10-02), so
# this script is the only way in — which is why it validates before writing.
#
# Usage:
#   wallpaper-process.sh get            Print every setting as KEY=VALUE
#   wallpaper-process.sh get KEY        Print one value (validates the key)
#   wallpaper-process.sh set KEY VALUE  Validate + persist one setting
#   wallpaper-process.sh reset          Restore built-in defaults
#   wallpaper-process.sh validate       Print "OK" or an error, exit 1 on error
#   wallpaper-process.sh path           Print the config file path
#
# File format: one KEY=VALUE per line, '#' comments. Parsed with a case loop —
# never `source`d, so a stray line cannot execute code in the wallpaper path.

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
CONF="${WALLPAPER_PROCESS_CONF:-$NIKI_HOME/.state/wallpaper-process.conf}"

# --- Schema: key -> default. Order defines `get` output order. ---
defaults() {
    cat <<'EOF'
INTERVAL=5m
DOWNSCALE=1920x1080
FORMAT=keep
JPEG_QUALITY=92
PNG_COMPRESSION=6
CANVAS_COLOR=auto
WALLUST=on
POST_CMD=
AUTOSTART=on
EOF
}

KEYS="INTERVAL DOWNSCALE FORMAT JPEG_QUALITY PNG_COMPRESSION CANVAS_COLOR WALLUST POST_CMD AUTOSTART"

err() {
    echo "[ERROR] $*" >&2
    exit 1
}

# --- Validation. Prints the canonical value on success. ---
validate() {
    local key="$1" val="$2"
    case "$key" in
    INTERVAL)
        # Positive sleep duration (1.5s, 30s, 5m, 1h, 1d) — same rule the daemon uses.
        [[ "$val" =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]] || err "INTERVAL must be a sleep duration like 5m or 30s (got '$val')"
        [[ ! "$val" =~ ^0+(\.0+)?[smhd]?$ ]] || err "INTERVAL must be greater than zero (got '$val')"
        printf '%s' "$val"
        ;;
    DOWNSCALE)
        [[ "$val" == "none" ]] && { printf '%s' "$val"; return; }
        # WxH with sane bounds; ">" suffix is appended at use time.
        [[ "$val" =~ ^[0-9]{2,5}x[0-9]{2,5}$ ]] || err "DOWNSCALE must be WxH (e.g. 1920x1080) or 'none' (got '$val')"
        local w="${val%x*}" h="${val#*x}"
        ((w >= 320 && h >= 240)) || err "DOWNSCALE is too small (min 320x240)"
        printf '%s' "$val"
        ;;
    FORMAT)
        case "$val" in keep | jpeg | png) printf '%s' "$val" ;; *) err "FORMAT must be keep, jpeg or png (got '$val')" ;; esac
        ;;
    JPEG_QUALITY)
        [[ "$val" =~ ^[0-9]{1,3}$ ]] || err "JPEG_QUALITY must be 1-100 (got '$val')"
        ((val >= 1 && val <= 100)) || err "JPEG_QUALITY must be 1-100 (got '$val')"
        printf '%s' "$val"
        ;;
    PNG_COMPRESSION)
        [[ "$val" =~ ^[0-9]{1,2}$ ]] || err "PNG_COMPRESSION must be 0-9 (got '$val')"
        ((val >= 0 && val <= 9)) || err "PNG_COMPRESSION must be 0-9 (got '$val')"
        printf '%s' "$val"
        ;;
    CANVAS_COLOR)
        case "$val" in
        auto | none) printf '%s' "$val" ;;
        \#*) [[ "$val" =~ ^#[0-9A-Fa-f]{6}$ ]] && { printf '%s' "$val"; return; }
            err "CANVAS_COLOR hex must be #RRGGBB (got '$val')" ;;
        *) err "CANVAS_COLOR must be auto, none or #RRGGBB (got '$val')" ;;
        esac
        ;;
    WALLUST | AUTOSTART)
        case "$val" in
        on) printf 'on' ;;
        off) printf 'off' ;;
        *) err "$key must be on or off (got '$val')" ;;
        esac
        ;;
    POST_CMD)
        # Free-form single line, run via bash -c. Newlines are rejected so the
        # setting stays one line and `get` output stays parseable.
        [[ "$val" != *$'\n'* ]] || err "POST_CMD must be a single line"
        printf '%s' "$val"
        ;;
    *) err "Unknown setting '$key' (valid: $KEYS)" ;;
    esac
}

known_key() {
    case " $KEYS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Absorb "KEY=VALUE" lines into the associative array `vals` on stdin.
# Comments, blanks and unknown keys are skipped; later lines win.
absorb() {
    local -n _out="$1"
    local k v
    while IFS='=' read -r k v || [[ -n "${k:-}" ]]; do
        k="${k%%[[:space:]]*}"
        [[ -n "$k" && "$k" != \#* ]] || continue
        known_key "$k" || continue
        _out["$k"]="$v"
    done
    return 0
}

# --- Load every setting as canonical KEY=VALUE lines (defaults, then overrides). ---
load() {
    local -A vals=()
    absorb vals < <(defaults)
    if [[ -f "$CONF" ]]; then
        absorb vals <"$CONF"
    fi
    local k out=""
    for k in $KEYS; do
        out+="$k=${vals[$k]-}"$'\n'
    done
    printf '%s' "$out"
    return 0
}

# One setting's current value.
value_of() {
    local want="$1" line
    while IFS= read -r line; do
        [[ "$line" == "$want="* ]] || continue
        printf '%s' "${line#*=}"
        return 0
    done <<<"$(load)"
    return 0
}

do_get() {
    if [[ $# -ge 1 ]]; then
        known_key "$1" || err "Unknown setting '$1' (valid: $KEYS)"
        value_of "$1"
        return 0
    fi
    load
}

do_setmany() {
    (( $# > 0 && $# % 2 == 0 )) || err "Usage: $0 setmany KEY VALUE [KEY VALUE ...]"
    local -a pairs=("$@")
    local -A canon=()
    local i k v c
    # Validate everything first: a rejected value must not leave a half-applied
    # file behind.
    for ((i = 0; i < ${#pairs[@]}; i += 2)); do
        k="${pairs[i]}"
        v="${pairs[i + 1]}"
        known_key "$k" || err "Unknown setting '$k' (valid: $KEYS)"
        c=$(validate "$k" "$v")
        canon["$k"]="$c"
    done

    local -A vals=()
    absorb vals <<<"$(load)"
    for k in "${!canon[@]}"; do
        vals["$k"]="${canon[$k]}"
    done

    write_conf vals

    for k in "${!canon[@]}"; do
        [[ "$k" == "AUTOSTART" ]] && sync_autostart "${canon[$k]}"
    done
    return 0
}

write_conf() {
    local -n _v="$1"
    mkdir -p "$(dirname "$CONF")"
    local tmp="${CONF}.$$" cur
    {
        echo "# wallpaper-process.sh settings — edited by"
        echo "# scripts/wallpaper-process.sh set|setmany. Parsed as data only."
        for cur in $KEYS; do
            printf '%s=%s\n' "$cur" "${_v[$cur]}"
        done
    } >"$tmp"
    mv -f "$tmp" "$CONF"
}

do_set() {
    [[ $# -eq 2 ]] || err "Usage: $0 set KEY VALUE"
    known_key "$1" || err "Unknown setting '$1' (valid: $KEYS)"
    local canon
    canon=$(validate "$1" "$2")

    local -A vals=()
    absorb vals <<<"$(load)"
    vals["$1"]="$canon"
    write_conf vals

    [[ "$1" == "AUTOSTART" ]] && sync_autostart "$canon"
    return 0
}

# Add or remove the daemon's spawn-at-startup line in every live spawn variant.
# Two shapes, matching each file's existing conventions:
#   repo files  -> "sleep 3; $NIRICONF/..."  ($NIRICONF is substituted by setup.sh;
#                  quickshell variant already stores the absolute path)
#   live file   -> absolute path, no placeholder (it is the copied, installed form)
sync_autostart() {
    local want="$1"
    local live="$HOME/.config/niri/spawn-at-startup.kdl"
    local f line
    for f in "$NIKI_HOME/niri/spawn-at-startup.kdl" "$NIKI_HOME/niri/spawn-quickshell.kdl" "$NIKI_HOME/niri/spawn-waybar.kdl"; do
        [[ -f "$f" ]] || continue
        if [[ "$f" == *spawn-quickshell.kdl ]]; then
            line="spawn-sh-at-startup \"sleep 3; $NIKI_HOME/scripts/auto-wallpaper.sh\""
        else
            line='spawn-sh-at-startup "sleep 3; $NIRICONF/scripts/auto-wallpaper.sh"'
        fi
        if [[ "$want" == "on" ]]; then
            grep -q 'auto-wallpaper\.sh' "$f" || printf '%s\n' "$line" >>"$f"
        else
            sed -i '/auto-wallpaper\.sh/d' "$f"
        fi
    done
    if [[ -f "$live" ]]; then
        if [[ "$want" == "on" ]]; then
            grep -q 'auto-wallpaper\.sh' "$live" || printf '%s\n' \
                "spawn-sh-at-startup \"sleep 3; $NIKI_HOME/scripts/auto-wallpaper.sh\"" >>"$live"
        else
            sed -i '/auto-wallpaper\.sh/d' "$live"
        fi
    fi
}

do_validate() {
    local canon
    local k v rc=0 canon
    while IFS='=' read -r k v; do
        if ! canon=$(validate "$k" "$v" 2>&1); then
            printf '%s\n' "$canon" >&2
            rc=1
        fi
    done <<<"$(load)"
    [[ $rc -eq 0 ]] && echo "OK"
    return $rc
}

case "${1:-}" in
get) shift; do_get "$@" ;;
set) shift; do_set "$@" ;;
setmany) shift; do_setmany "$@" ;;
reset)
    rm -f "$CONF"
    echo "[OK] Reset to defaults"
    ;;
validate) do_validate ;;
path) printf '%s\n' "$CONF" ;;
*) err "Usage: $0 {get|get KEY|set KEY VALUE|reset|validate|path}" ;;
esac