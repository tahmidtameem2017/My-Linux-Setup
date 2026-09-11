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
#   INTERVAL         Rotation interval, any `sleep` duration (default: 15m)
#   NIRI_SETUP_HOME  Path to niri-setup repo (default: $HOME/niri-setup)

set -euo pipefail

# --- Configuration ---
WALL_DIR="${WALL_DIR:-$HOME/Pictures/Wallpapers}"
INTERVAL="${INTERVAL:-5m}"
NIRI_SETUP_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
WALLPAPER_SH="$NIRI_SETUP_HOME/scripts/wallpaper.sh"

STATE_DIR="$NIRI_SETUP_HOME/.state"
PID_FILE="$STATE_DIR/auto-wallpaper.pid"
LOG_FILE="$STATE_DIR/auto-wallpaper.log"
HISTORY_FILE="$STATE_DIR/auto-wallpaper.history"
QUEUE_FILE="$STATE_DIR/auto-wallpaper.queue"

SLEEP_PID=""

# --- Helpers ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
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

check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            rm -f "$PID_FILE"
        fi
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

# Largest 6-digit prime: 999983
readonly HASH_PRIME=999983

init_queue() {
    local wallpapers
    mapfile -t wallpapers < <(get_wallpapers)

    if [[ ${#wallpapers[@]} -eq 0 ]]; then
        die "No wallpapers found in $WALL_DIR"
    fi

    # Deterministic permutation via 999983 multiplicative hash
    local count=${#wallpapers[@]}
    local seed
    seed=$(date +%s%N)
    local -a shuffled=()
    local -a used=()
    local idx hash
    for (( i = 0; i < count; i++ )); do
        hash=$(( (seed + i) * HASH_PRIME ))
        idx=$(( hash % count ))
        while [[ -n "${used[$idx]}" ]]; do
            idx=$(( (idx + 1) % count ))
        done
        used[$idx]=1
        shuffled+=("${wallpapers[$idx]}")
    done
    printf "%s\n" "${shuffled[@]}" > "$QUEUE_FILE"
    log "[INFO] Initialized queue with ${#wallpapers[@]} wallpapers (999983-hashed)"
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
    init_queue

    # Write PID
    echo $$ > "$PID_FILE"

    # Trap signals for clean shutdown and early rotation
    trap 'log "[INFO] Caught signal, exiting..."; cleanup; exit 0' INT TERM HUP
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
        init_queue
        set_next_wallpaper
        ;;
    --next)
        if existing_pid=$(check_running); then
            kill -USR1 "$existing_pid"
            echo "Triggered wallpaper change for daemon PID $existing_pid"
        else
            ensure_dir "$STATE_DIR"
            init_queue
            set_next_wallpaper
        fi
        ;;
    *)
        run_daemon
        ;;
esac
