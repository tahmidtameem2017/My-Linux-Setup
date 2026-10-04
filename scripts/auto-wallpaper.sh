#!/usr/bin/env bash
# auto-wallpaper.sh — Robust wallpaper rotator for niri
#
# Usage:
#   auto-wallpaper.sh           Start daemon (default)
#   auto-wallpaper.sh --stop    Stop running daemon
#   auto-wallpaper.sh --status  Show running status & last wallpapers
#   auto-wallpaper.sh --oneshot Set one random wallpaper and exit
#   auto-wallpaper.sh --next    Force a wallpaper change now
#
# Environment:
#   WALL_DIR         Wallpaper directory (default: $HOME/Pictures/Wallpapers)
#   INTERVAL         Rotation interval, any `sleep` duration (default: 5m)
#   NIRI_SETUP_HOME  Path to niri-setup repo (default: $HOME/niri-setup)

set -euo pipefail

# --- Configuration ---
WALL_DIR="${WALL_DIR:-$HOME/Pictures/Wallpapers}"
NIRI_SETUP_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
WALLPAPER_SH="$NIRI_SETUP_HOME/scripts/wallpaper.sh"
PROC_SH="$NIRI_SETUP_HOME/scripts/wallpaper-process.sh"

# INTERVAL precedence: environment override > the INTERVAL stored in
# .state/wallpaper-process.conf (see scripts/wallpaper-process.sh) >
# built-in default. wallpaper-process.sh validates the value, so this
# cannot reintroduce a bad `sleep` argument.
if [[ -z "${INTERVAL:-}" ]]; then
    INTERVAL=$("$PROC_SH" get INTERVAL 2>/dev/null || true)
fi
INTERVAL="${INTERVAL:-5m}"

STATE_DIR="$NIRI_SETUP_HOME/.state"
# basename of this script, used to recognise our own daemon in /proc. Set
# explicitly because $0 is not reliable for a re-execed/detached process.
SCRIPT_NAME="auto-wallpaper.sh"
PID_FILE="$STATE_DIR/auto-wallpaper.pid"
LOG_FILE="$STATE_DIR/auto-wallpaper.log"
HISTORY_FILE="$STATE_DIR/auto-wallpaper.history"
QUEUE_FILE="$STATE_DIR/auto-wallpaper.queue"

SLEEP_PID=""

# --- Helpers ---
# Logs go to the log file + stderr (never stdout): init_queue/pop_next_wallpaper
# run inside command substitutions, so stdout noise would corrupt the popped path.
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

die() {
    log "[ERROR] $*"
    exit 1
}

ensure_dir() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1"
    fi
}

cleanup() {
    rm -f "$PID_FILE"
}

# Is $1 actually one of our daemons?
#
# `kill -0` alone is NOT enough, and that is not a theoretical concern: a stale
# PID file pointed at 993, the kernel handed 993 to at-spi-bus-launcher, and
# `kill -0 993` succeeded happily. --status then reported "Daemon running" and
# --stop would have killed an accessibility service. So the PID is only
# believed when the process it now names still looks like this script.
pid_is_daemon() {
    local pid="$1" cmdline
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ -d "/proc/$pid" ]] || return 1
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    [[ "$cmdline" == *"$SCRIPT_NAME"* ]]
}

check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if pid_is_daemon "$pid"; then
            echo "$pid"
            return 0
        fi
        # Either the daemon died or the PID was recycled. Either way the file is
        # a lie, and clearing it is what lets --stop/--status/start do the right
        # thing on their own.
        rm -f "$PID_FILE"
    fi
    return 1
}

# --- Queue Management ---
get_wallpapers() {
    find "$WALL_DIR" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o \
        -iname "*.jpeg" -o \
        -iname "*.png" -o \
        -iname "*.webp" -o \
        -iname "*.avif" \
    \) | sort
}

init_queue() {
    local wallpapers
    mapfile -t wallpapers < <(get_wallpapers)

    if [[ ${#wallpapers[@]} -eq 0 ]]; then
        die "No wallpapers found in $WALL_DIR"
    fi

    # Random permutation via shuf (coreutils). Every wallpaper appears exactly
    # once per cycle; the queue is rebuilt when exhausted.
    printf "%s\n" "${wallpapers[@]}" | shuf > "$QUEUE_FILE"
    log "[INFO] Initialized queue with ${#wallpapers[@]} wallpapers"
}

pop_next_wallpaper() {
    if [[ ! -f "$QUEUE_FILE" ]] || [[ ! -s "$QUEUE_FILE" ]]; then
        init_queue
    fi

    local line
    line=$(head -n 1 "$QUEUE_FILE")

    if [[ -z "$line" ]]; then
        init_queue
        line=$(head -n 1 "$QUEUE_FILE")
    fi

    # Remove the line we just read
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
    echo "$line"
}

# --- Core ---
set_next_wallpaper() {
    local wallpaper
    wallpaper=$(pop_next_wallpaper)

    if [[ ! -f "$wallpaper" ]]; then
        log "[WARN] Wallpaper vanished: $wallpaper. Reinitializing queue..."
        init_queue
        wallpaper=$(pop_next_wallpaper)
    fi

    if bash "$WALLPAPER_SH" "$wallpaper"; then
        log "[OK] Set wallpaper: $wallpaper"
        echo "$wallpaper" >> "$HISTORY_FILE"
        # Keep history bounded (last 200 entries)
        tail -n 200 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    else
        log "[ERROR] Failed to set wallpaper: $wallpaper"
    fi
}

do_sleep() {
    sleep "$1" &
    SLEEP_PID=$!
    wait $SLEEP_PID 2>/dev/null || true
}

run_daemon() {
    local existing_pid
    if existing_pid=$(check_running); then
        die "Already running (PID: $existing_pid). Use --stop to kill it."
    fi

    ensure_dir "$STATE_DIR"

    # Validate INTERVAL before daemonizing: an invalid value would make
    # `sleep` fail instantly and spin the loop (rapid wallpaper churn).
    if ! [[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]] || [[ "$INTERVAL" =~ ^0+(\.0+)?[smhd]?$ ]]; then
        die "Invalid INTERVAL: $INTERVAL (expected a positive sleep duration like 5m, 1h, 30s)"
    fi

    init_queue

    # Write PID
    echo $$ > "$PID_FILE"

    # Trap signals for clean shutdown and early rotation.
    # The TERM/INT/HUP trap also kills the in-progress sleep so no orphan
    # `sleep` lingers after the daemon stops.
    trap 'kill "$SLEEP_PID" 2>/dev/null || true; log "[INFO] Caught signal, exiting..."; cleanup; exit 0' INT TERM HUP
    trap 'kill $SLEEP_PID 2>/dev/null || true' USR1

    log "[INFO] Daemon started (PID: $$, Interval: $INTERVAL)"

    # Initial wallpaper set
    set_next_wallpaper

    while true; do
        do_sleep "$INTERVAL"
        # If woken by USR1, sleep will exit early and we rotate immediately
        set_next_wallpaper
    done
}

# --- CLI ---
case "${1:-}" in
    --stop)
        if existing_pid=$(check_running); then
            kill "$existing_pid" && log "[INFO] Stopped daemon (PID: $existing_pid)"
            rm -f "$PID_FILE"
        else
            echo "No running daemon found."
        fi
        ;;
    --status)
        if existing_pid=$(check_running); then
            echo "Daemon running (PID: $existing_pid)"
            echo "Log: $LOG_FILE"
            echo "Last wallpapers:"
            if [[ -f "$HISTORY_FILE" ]]; then
                tail -n 5 "$HISTORY_FILE"
            else
                echo "  (no history)"
            fi
        else
            echo "Daemon not running."
        fi
        ;;
    --oneshot)
        ensure_dir "$STATE_DIR"
        # NOTE: no init_queue here — pop_next_wallpaper rebuilds the queue
        # only when it is missing/empty, so the remaining cycle is preserved.
        set_next_wallpaper
        ;;
    --next)
        if existing_pid=$(check_running); then
            kill -USR1 "$existing_pid"
            echo "Triggered wallpaper change for daemon PID $existing_pid"
        else
            ensure_dir "$STATE_DIR"
            set_next_wallpaper
        fi
        ;;
    *)
        run_daemon
        ;;
esac
