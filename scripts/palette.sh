#!/usr/bin/env bash
# palette.sh get
#
# Print the active shell palette as KEY=VALUE lines on stdout, so anything
# outside quickshell can match the bar/popups. Keys and hex values are the ones
# services/Theme.qml publishes (bg, panel, row, border, borderStrong, accent,
# accentHover, text, muted, dim, danger) — same vocabulary as taste.md.
#
# Output contract (other scripts parse this — do not reorder, rename, or add
# lines): 11 lines, `key=RRGGBB`, no '#', no trailing chatter.
#
# Source of truth, in order:
#   1. active-theme.json — written by Theme.qml's publishPalette() on every
#      palette change. Works for every theme, built-in or wallust-derived.
#   2. theme.txt + theme-<name>.json — the older per-theme files, in case the
#      shell has not republished yet (fresh boot, quickshell restarting).
#   3. The Sunset Orange AMOLED defaults baked in below.
#
# Sources are consulted per key rather than "first file that exists", so a torn
# or hand-mangled active-theme.json degrades key-by-key instead of blanking the
# whole palette back to Sunset.
#
# Deliberately grep/tr/head only: the lock screen runs before/independently of
# the shell and must not need an interpreter to start. grep -o and [[:space:]]
# are the common subset of GNU and busybox, so no GNU-only flags.
#
# Nothing but KEY=VALUE lines goes to stdout.

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
THEME_DIR="${NIRI_THEME_DIR:-$HOME/.local/share/niri-setup}"
ACTIVE_JSON="$THEME_DIR/active-theme.json"

# The 11 published tokens, in publication order. Both loops iterate this, so the
# output order is defined in exactly one place.
KEYS=(bg panel row border borderStrong accent accentHover text muted dim danger)

# taste.md — Sunset Orange AMOLED. Last resort: a key no source resolved.
# An assoc array (not ${!DEFAULT_$k}, which is not valid indirect expansion
# and aborts the script the moment any single key is missing from the JSON).
declare -A DEFAULT=(
    [bg]=000000
    [panel]=0A0A0A
    [row]=141010
    [border]=1A1210
    [borderStrong]=3D2B24
    [accent]=E85D2F
    [accentHover]=FF8B4A
    [text]=F7C7A1
    [muted]=7C8A6A
    [dim]=555555
    [danger]=C30505
)

# Pull "key": "#aabbcc" out of a palette JSON. Tolerates whitespace, key order
# and stray keys; returns nothing when the key or the hex is missing, which is
# the signal to fall through to the next source.
pick() {
    local json="$1" key="$2"
    printf '%s' "$json" |
        tr -d '\n' |
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"#[0-9a-fA-F]\{6\}\"" |
        head -n1 |
        grep -o '#[0-9a-fA-F]\{6\}' |
        head -n1 |
        tr -d '#' |
        tr 'a-f' 'A-F' || true
}

# The selected theme name, or nothing. Theme.qml's save() writes it without a
# trailing newline, so strip any that appear.
theme_name() {
    [[ -r "$THEME_DIR/theme.txt" ]] || return 0
    tr -d '\r\n' <"$THEME_DIR/theme.txt" 2>/dev/null || true
}

cmd_get() {
    local -a blobs=()
    local s name k v

    [[ -s "$ACTIVE_JSON" ]] && blobs+=("$(cat "$ACTIVE_JSON" 2>/dev/null || true)")

    name=$(theme_name)
    if [[ -n "$name" ]]; then
        s="$THEME_DIR/theme-$name.json"
        [[ -s "$s" ]] && blobs+=("$(cat "$s" 2>/dev/null || true)")
    fi

    local -A out=()
    for k in "${KEYS[@]}"; do
        v=""
        for s in "${blobs[@]}"; do
            [[ -n "$v" ]] && break
            v=$(pick "$s" "$k")
        done
        [[ -n "$v" ]] || v="${DEFAULT[$k]}"
        out["$k"]="$v"
    done

    for k in "${KEYS[@]}"; do
        printf '%s=%s\n' "$k" "${out[$k]}"
    done
}

case "${1:-get}" in
get) cmd_get ;;
*)
    echo "Usage: $0 get" >&2
    exit 1
    ;;
esac
