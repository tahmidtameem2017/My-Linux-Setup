#!/usr/bin/env bash
# record-screen.sh — toggle a lightweight screen recording (gpu-screen-recorder).
#
#   record-screen.sh            start when idle, stop when recording (toggle)
#   record-screen.sh start      start recording (portal picker on first run)
#   record-screen.sh stop       stop, save MP4, pop the video action pill
#   record-screen.sh cancel     stop, throw the file away
#   record-screen.sh --status   recording | idle (+ path)
#
# Output: ~/Videos/rec-YYYYMMDD-HHMMSS.mp4 (h264 via Intel VAAPI, 60fps,
# aac audio from the default PipeWire output). State lives in .state/.
set -euo pipefail

NIRI_SETUP_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
STATE_DIR="$NIRI_SETUP_HOME/.state"
OUT_DIR="${REC_OUT_DIR:-$HOME/Videos}"
SCRIPT_NAME="gpu-screen-recorder"
PID_FILE="$STATE_DIR/record-screen.pid"
PATH_FILE="$STATE_DIR/record-screen.path"
LOG_FILE="$STATE_DIR/record-screen.log"

mkdir -p "$STATE_DIR" "$OUT_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

notify() { notify-send -a niri -t "${2:-3000}" "Screen Recording" "$1" 2>/dev/null || true; }

qs_call() { qs -c sunset ipc call "$@" 2>/dev/null || true; }

ensure() { command -v "$1" >/dev/null 2>&1 || { notify "missing dependency: $1" 5000; exit 1; }; }

# /proc/<pid>/cmdline must name gpu-screen-recorder itself — a PID file is not
# proof of a process (kernel recycles PIDs; kill -0 alone is a lie).
recorder_pid() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid cmdline
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    [[ "$pid" =~ ^[0-9]+$ ]] || { rm -f "$PID_FILE"; return 1; }
    [[ -d "/proc/$pid" ]] || { rm -f "$PID_FILE"; return 1; }
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmdline" in
        *gpu-screen-recorder*) echo "$pid"; return 0 ;;
        *) rm -f "$PID_FILE"; return 1 ;;
    esac
}

start() {
    ensure gpu-screen-recorder
    if recorder_pid >/dev/null; then
        notify "Already recording — fire the bind again to stop" 2500
        exit 0
    fi

    local out="$OUT_DIR/rec-$(date +%Y%m%d-%H%M%S).mp4"
    # First launch shows the portal source picker; -restore-portal-session yes
    # makes every launch after that skip it. Fresh log per run: the settle
    # check below greps this file, so last run's "pipewire setup finished"
    # must not match.
    : > "$LOG_FILE"
    gpu-screen-recorder \
        -w portal -restore-portal-session yes \
        -f 60 -c mp4 -k h264 -ac aac -a default_output \
        -o "$out" >> "$LOG_FILE" 2>&1 &
    local pid=$!

    # The portal pick can take a moment (or be cancelled, in which case the
    # recorder exits on its own). Only call it "started" once the PipeWire
    # stream is actually up — "alive but stuck at the picker" is NOT started,
    # and "alive" alone lets the pill lie.
    local settled=0
    for _ in $(seq 1 30); do
        if grep -qa "pipewire setup finished" "$LOG_FILE" 2>/dev/null; then
            settled=1; break
        fi
        [[ -d "/proc/$pid" ]] || break
        sleep 0.5
    done
    if [[ "$settled" == 1 ]] && [[ -d "/proc/$pid" ]]; then
        echo "$pid" > "$PID_FILE"
        echo "$out" > "$PATH_FILE"
        qs_call screenshots recordStart "$out"
        notify "Recording started — Mod+Shift+R to stop" 2500
        log "started pid=$pid out=$out"
    else
        [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f "$out"
        qs_call screenshots close
        notify "Recording cancelled (no source picked?)" 3000
        log "start aborted (portal cancelled or encoder failed)"
    fi
}

stop() {
    local pid out
    pid=$(recorder_pid || true)
    [[ -n "$pid" ]] || { notify "Not recording" 2000; exit 0; }
    out=$(cat "$PATH_FILE" 2>/dev/null || true)

    # SIGINT lets gpu-screen-recorder finalize the container before exiting.
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
        [[ -d "/proc/$pid" ]] || break
        sleep 0.5
    done
    [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    rm -f "$PID_FILE" "$PATH_FILE"
    qs_call screenshots recordStop

    if [[ -n "$out" && -s "$out" ]]; then
        qs_call screenshots openVideo "$out"
        notify "Saved: $(basename "$out")" 3000
        log "stopped pid=$pid out=$out"
    else
        qs_call screenshots close
        notify "Recording produced no file" 4000
        log "stopped pid=$pid — no usable output"
    fi
}

cancel() {
    local pid out
    pid=$(recorder_pid || true)
    out=$(cat "$PATH_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 10); do [[ -d "/proc/$pid" ]] || break; sleep 0.5; done
        [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
        rm -f "$PID_FILE" "$PATH_FILE"
    fi
    [[ -n "$out" ]] && rm -f "$out"
    qs_call screenshots close
    notify "Recording discarded" 2000
    log "cancelled pid=${pid:-none} out=${out:-none}"
}

case "${1:-toggle}" in
    start) start ;;
    stop) stop ;;
    cancel) cancel ;;
    --status|status)
        if recorder_pid >/dev/null; then echo "recording: $(cat "$PATH_FILE")"; else echo "idle"; fi ;;
    toggle|*)
        if recorder_pid >/dev/null; then stop; else start; fi ;;
esac
