#!/usr/bin/env bash
# dictation-reset.sh — the "get me out of this" button for dictation.
#
# Usage:
#   dictation-reset.sh          Escalate until dictation is stopped (default)
#   dictation-reset.sh stop     Same thing, named for the bind
#   dictation-reset.sh status   Report what is running, changing nothing
#   dictation-reset.sh mic      Report which processes hold the microphone
#
# WHY THIS IS NOT JUST `whisrs cancel`
# -----------------------------------
# Two different things go wrong, and only one of them is polite:
#
#   1. Recording stuck in the "recording" state — the daemon is alive and will
#      answer, so `whisrs cancel` is correct and enough.
#   2. The daemon is WEDGED — mid-transcription on a pathological buffer, or
#      blocked on a device. It stops answering its socket entirely, so cancel,
#      toggle and status all silently do nothing and the microphone stays open
#      for as long as it likes. Only a restart or a signal reaches it.
#
# So this walks an escalation ladder and STOPS at the first rung that works:
#   1  whisper cancel via the socket   (polite: keeps the daemon warm)
#   2  restart the systemd service    (frees the mic even if wedged)
#   3  SIGTERM the daemon             (in case systemd is not managing it)
#   4  SIGKILL the daemon             (last resort, still cmdline-matched)
#   5  report anything still holding the mic, naming the process
#
# Matching, never blind pkill
# ---------------------------
# `pkill whisrsd` would also match any unrelated process that inherited the
# name, and a bare `kill $pid` trusts a pid file that may be stale — the exact
# bug that shipped once in auto-wallpaper.sh, where a stale PID file named 993
# and 993 had been handed to at-spi-bus-launcher's child, so `--stop` cheerfully
# killed an accessibility service. Every signal below is gated on matching
# /proc/<pid>/cmdline against the daemon's own name.
#
# Deliberately does NOT restart the shell or touch niri config. It is bound to a
# panic key and must be safe to mash.

set -uo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/whisrs.sock"
SERVICE="whisrs.service"

# Prefer the installed binary, fall back to the absolute path (systemd's PATH
# lacks ~/.local/bin, and a panic key must work from any environment).
WHISRS=""
for c in whisrs "$HOME/.local/bin/whisrs"; do
    if command -v "$c" >/dev/null 2>&1; then WHISRS="$(command -v "$c")"; break; fi
done

log() { printf '%s\n' "$*"; }
step() { log "  -> $*"; }

# Is the daemon answering its control socket right now?
daemon_answers() {
    [[ -n "$WHISRS" && -S "$SOCK" ]] || return 1
    timeout 5 "$WHISRS" status >/dev/null 2>&1
}

daemon_state() {
    [[ -n "$WHISRS" && -S "$SOCK" ]] || { echo "unreachable"; return; }
    timeout 5 "$WHISRS" status 2>/dev/null || echo "unreachable"
}

# PIDs that really are the whisrs daemon.
#
# Matched on the BASENAME OF argv[0], not on the whole command line. A substring
# search over the full cmdline is a false-positive generator: a process invoked
# as `some-other-service --whisrsd-flag` matches `*whisrsd*` and would collect a
# SIGKILL aimed at a healthy daemon — verified, this exact decoy was picked up
# before the check was tightened. Equality on argv[0]'s basename cannot match a
# process that merely mentions the daemon.
daemon_pids() {
    local p argv0
    for p in /proc/[0-9]*; do
        p="${p#/proc/}"
        [[ -r "/proc/$p/cmdline" ]] || continue
        # argv[0] is the first NUL-separated field.
        argv0="$(tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | head -1)" || continue
        [[ -n "$argv0" ]] || continue
        case "${argv0##*/}" in
        whisrsd | whisrs) printf '%s\n' "$p" ;;
        esac
    done
}

# What is currently holding the microphone? Read from PipeWire rather than
# guessing, because the answer the user actually wants is "is anything still
# recording", not "did my pids die".
mic_holders() {
    command -v pw-dump >/dev/null 2>&1 || { echo "(pw-dump unavailable)"; return; }
    pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    objs = json.load(sys.stdin)
except Exception:
    print("  (pw-dump returned nothing)")
    sys.exit(0)
found = False
for o in objs:
    if not str(o.get("type", "")).startswith("PipeWire:Interface:Node"):
        continue
    p = (o.get("info") or {}).get("props") or {}
    if "Stream/Input" not in p.get("media.class", ""):
        continue
    name = p.get("node.name", "?")
    if name == "quickshell":
        continue  # the mic indicator level meter in quickshell, always present
    found = True
    print("  %s  (app: %s)" % (name, p.get("application.name", "?")))
if not found:
    print("  nothing — microphone is free")
' 2>/dev/null
}

do_status() {
    log "whisrs daemon: $(daemon_state)"
    local pids
    pids="$(daemon_pids | tr '\n' ' ')"
    log "daemon pids   : ${pids:-none}"
    log "microphone    :"
    mic_holders
}

do_stop() {
    log "dictation reset:"

    # ---- rung 1: ask nicely over the socket -------------------------------
    if daemon_answers; then
        step "whisrs cancel (daemon is $(daemon_state))"
        timeout 5 "$WHISRS" cancel >/dev/null 2>&1
        sleep 0.4
        local st; st="$(daemon_state)"
        if [[ "$st" != "recording" && "$st" != "transcribing" ]]; then
            step "stopped cleanly; daemon left warm (model still resident)"
            return 0
        fi
        step "still '$st' after cancel, escalating"
    else
        step "daemon not answering on $SOCK (wedged or not running)"
    fi

    # ---- rung 2: restart via systemd --------------------------------------
    # Chosen over a bare signal because it is the only rung that also reaps a
    # wedged transcription thread and remaps the overlay surface.
    if systemctl --user list-unit-files "$SERVICE" >/dev/null 2>&1; then
        step "systemctl --user restart $SERVICE"
        systemctl --user restart "$SERVICE" >/dev/null 2>&1
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            sleep 0.5
            if systemctl --user is-active --quiet "$SERVICE"; then
                step "service back up; microphone released"
                return 0
            fi
        done
        step "service did not come back, escalating"
    fi

    # ---- rung 3/4: signals, still cmdline-matched ------------------------
    local pids
    pids="$(daemon_pids)"
    if [[ -z "$pids" ]]; then
        step "no daemon process found — nothing left to kill"
    else
        step "SIGTERM to: $(echo "$pids" | tr '\n' ' ')"
        # shellcheck disable=SC2086
        kill -TERM $pids 2>/dev/null
        local i
        for i in $(seq 1 20); do
            [[ -z "$(daemon_pids)" ]] && { step "terminated"; return 0; }
            sleep 0.25
        done
        pids="$(daemon_pids)"
        if [[ -n "$pids" ]]; then
            step "SIGKILL to: $(echo "$pids" | tr '\n' ' ')"
            # shellcheck disable=SC2086
            kill -KILL $pids 2>/dev/null
            sleep 0.5
            [[ -z "$(daemon_pids)" ]] && step "killed" || step "WARNING: pids survived SIGKILL: $(daemon_pids | tr '\n' ' ')"
        fi
    fi

    # ---- rung 5: is the mic actually free? -------------------------------
    log "  microphone now:"
    mic_holders
}

case "${1:-stop}" in
stop) do_stop ;;
status) do_status ;;
mic) mic_holders ;;
*)
    cat >&2 <<'USAGE'
usage: dictation-reset.sh [stop|status|mic]
USAGE
    exit 2
    ;;
esac