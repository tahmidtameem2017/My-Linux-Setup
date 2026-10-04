#!/usr/bin/env bash
# session.sh — saved workspace sessions (study, entertainment, …).
# Applies a JSON profile by spawning its apps on the CURRENT workspace —
# never switches workspaces. Workspace groups in the profile become
# columns laid out left-to-right where you already are. No niri config
# edits — profiles live in ~/.local/share/niri-setup/sessions/*.json
# and are edited via the sunset Sessions popup
# (`qs -c sunset ipc call sessions toggle`) or `session.sh edit`.
#
# Usage:
#   session.sh list              # one profile name per line
#   session.sh apply <name>      # open the session's apps here
#   session.sh pick              # gum picker -> apply (needs gum)
#   session.sh edit [name]       # gum picker (or arg) -> $EDITOR + JSON check
#   session.sh capture <name>    # snapshot current workspaces to a skeleton
#   session.sh dir               # print the sessions directory
#
# Profile format:
#   { "name": "study",
#     "workspaces": [ { "name": "read", "apps": ["brave", "zathura"] } ] }
# `apps` entries are plain shell command strings (run via `niri msg
# action spawn-sh`). Groups apply in order as columns on the current
# workspace; group names are organizational only.

set -euo pipefail

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
SESSIONS_DIR="$HOME/.local/share/niri-setup/sessions"
EXAMPLES_DIR="$NIKI_HOME/sessions"
SETTLE_APP="${SESSION_SETTLE_APP:-0.4}"

seed_examples() {
    if [[ ! -d "$SESSIONS_DIR" ]] || [[ -z "$(ls -A "$SESSIONS_DIR" 2>/dev/null)" ]]; then
        if [[ -d "$EXAMPLES_DIR" ]] && compgen -G "$EXAMPLES_DIR/*.json" > /dev/null; then
            mkdir -p "$SESSIONS_DIR"
            cp -n "$EXAMPLES_DIR"/*.json "$SESSIONS_DIR"/ 2>/dev/null || true
        fi
    fi
}

profile_path() {
    local name="$1"
    # Keep names filesystem-safe (letters, digits, dash, underscore).
    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "[ERROR] Bad session name: $name (use letters/digits/-/_)" >&2
        return 1
    fi
    printf '%s/%s.json' "$SESSIONS_DIR" "$name"
}

cmd_list() {
    seed_examples
    [[ -d "$SESSIONS_DIR" ]] || return 0
    local f
    for f in "$SESSIONS_DIR"/*.json; do
        [[ -e "$f" ]] || continue
        basename "$f" .json
    done | sort
}

cmd_apply() {
    local name="${1:-}"
    [[ -n "$name" ]] || { echo "[ERROR] Usage: $0 apply <name>" >&2; return 1; }
    seed_examples
    local prof
    prof="$(profile_path "$name")"
    [[ -f "$prof" ]] || { echo "[ERROR] No such session: $name (see: $0 list)" >&2; return 1; }
    command -v niri >/dev/null || { echo "[ERROR] niri not on PATH" >&2; return 1; }

    # Flatten to app commands in group order. Python does the JSON so
    # app strings keep their quoting intact (jq not required). Everything
    # spawns on the CURRENT workspace — no focus-workspace calls, the
    # user stays exactly where they are; groups become columns
    # left-to-right in niri's scrolling layout.
    local plan
    plan="$(python3 - "$prof" <<'EOF'
import json, sys
with open(sys.argv[1]) as fh:
    prof = json.load(fh)
ws = prof.get("workspaces", [])
if not isinstance(ws, list) or not ws:
    sys.exit("profile has no workspaces array")
for w in ws:
    apps = (w or {}).get("apps", []) or []
    for app in apps:
        if isinstance(app, str) and app.strip():
            print(app.strip())
EOF
)" || { echo "[ERROR] Invalid profile JSON: $prof" >&2; return 1; }
    [[ -n "$plan" ]] || { echo "[ERROR] Session '$name' has no apps" >&2; return 1; }

    local first=1 app
    while IFS= read -r app; do
        if [[ "$first" -eq 1 ]]; then
            first=0
        else
            sleep "$SETTLE_APP"
        fi
        niri msg action spawn-sh -- "$app" >/dev/null
    done <<< "$plan"

    notify-send -a Sessions "Session '$name' applied" "Apps opened here — give slow apps a moment to land." 2>/dev/null || true
    echo "[OK] Session '$name' applied"
}

cmd_pick() {
    command -v gum >/dev/null || { echo "[ERROR] gum not installed" >&2; return 1; }
    local name
    name="$(cmd_list | gum choose --header "Apply session")" || return 0
    [[ -n "$name" ]] || return 0
    cmd_apply "$name"
}

cmd_edit() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        command -v gum >/dev/null || { echo "[ERROR] gum not installed (or pass a name)" >&2; return 1; }
        name="$(cmd_list | gum choose --header "Edit session")" || return 0
        [[ -n "$name" ]] || return 0
    fi
    local prof
    prof="$(profile_path "$name")" || return 1
    if [[ ! -f "$prof" ]]; then
        printf '{\n  "name": "%s",\n  "workspaces": [\n    { "name": "main", "apps": [] }\n  ]\n}\n' "$name" > "$prof"
    fi
    while true; do
        "${EDITOR:-nano}" "$prof"
        if python3 -c "import json; json.load(open('$prof'))" 2>/dev/null; then
            echo "[OK] Saved $prof"
            return 0
        fi
        echo "[WARN] Invalid JSON — keeping editor open (Ctrl+C aborts, file kept as-is)." >&2
        sleep 1
    done
}

# Snapshot current niri workspaces into a skeleton profile. App *launch
# commands* can't be recovered from running windows, so each window's
# app_id is stored as a suggested command for you to fix up in the editor.
cmd_capture() {
    local name="${1:-}"
    [[ -n "$name" ]] || { echo "[ERROR] Usage: $0 capture <name>" >&2; return 1; }
    local prof
    prof="$(profile_path "$name")" || return 1
    [[ -e "$prof" ]] && { echo "[ERROR] $prof exists — edit it instead" >&2; return 1; }
    python3 - "$prof" "$name" <<'EOF'
import json, subprocess, sys
prof_path, name = sys.argv[1], sys.argv[2]
wins = json.loads(subprocess.run(
    ["niri", "msg", "-j", "windows"], capture_output=True,
    text=True, check=True).stdout)
# app_id -> launch command for common apps (app_ids are not binaries:
# case and reverse-DNS names would fail at spawn time).
LAUNCH = {
    "Alacritty": "alacritty --config-file /home/me/niri-setup/alacritty/default.toml",
    "brave-browser": "brave",
    "org.kde.okular": "okular",
    "org.gnome.Nautilus": "nautilus",
    "code": "code",
}
by_ws = {}
for w in wins:
    ws = w.get("workspace_id")
    app = w.get("app_id") or ""
    if ws is None or not app:
        continue
    cmd = LAUNCH.get(app, app)
    by_ws.setdefault(ws, [])
    if cmd not in by_ws[ws]:
        by_ws[ws].append(cmd)
ordered = [by_ws[k] for k in sorted(by_ws)]
workspaces = [
    {"name": "ws%d" % (i + 1), "apps": apps}
    for i, apps in enumerate(ordered)
] or [{"name": "main", "apps": []}]
with open(prof_path, "w") as fh:
    json.dump({"name": name, "workspaces": workspaces}, fh, indent=2)
    fh.write("\n")
print("[OK] Captured %d workspace(s) -> %s (fix up app commands in the editor)" % (len(workspaces), prof_path))
EOF
}

# Backend for the GUI editor (argv-safe: JSON travels base64-encoded).
cmd_save() {
    local name="${1:-}" b64="${2:-}"
    [[ -n "$name" && -n "$b64" ]] || { echo "[ERROR] Usage: $0 save <name> <b64json>" >&2; return 1; }
    local prof
    prof="$(profile_path "$name")" || return 1
    seed_examples
    local tmp="$prof.$$"
    if ! printf '%s' "$b64" | base64 -d > "$tmp" 2>/dev/null; then
        echo "[ERROR] save: bad base64" >&2
        rm -f "$tmp"
        return 1
    fi
    if ! python3 - "$tmp" "$name" <<'EOF' 2>/dev/null; then
import json, sys
prof = json.load(open(sys.argv[1]))
assert prof.get("name") == sys.argv[2], "name mismatch"
ws = prof.get("workspaces")
assert isinstance(ws, list) and ws, "needs a workspaces array"
for w in ws:
    assert isinstance(w, dict) and isinstance(w.get("apps", []), list), "bad workspace entry"
EOF
        echo "[ERROR] save: invalid profile JSON" >&2
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$prof"
    echo "[OK] Saved $prof"
}

cmd_remove() {
    local name="${1:-}"
    [[ -n "$name" ]] || { echo "[ERROR] Usage: $0 remove <name>" >&2; return 1; }
    local prof
    prof="$(profile_path "$name")" || return 1
    [[ -f "$prof" ]] || { echo "[ERROR] No such session: $name" >&2; return 1; }
    rm -f "$prof"
    echo "[OK] Removed $name"
}

case "${1:-list}" in
    list) cmd_list ;;
    show) prof="$(profile_path "${2:-}")" && cat "$prof" ;;
    save) cmd_save "${2:-}" "${3:-}" ;;
    remove) cmd_remove "${2:-}" ;;
    apply) cmd_apply "${2:-}" ;;
    pick) cmd_pick ;;
    edit) cmd_edit "${2:-}" ;;
    capture) cmd_capture "${2:-}" ;;
    dir) seed_examples; printf '%s\n' "$SESSIONS_DIR" ;;
    *) echo "Usage: $0 {list|show <name>|save <name> <b64json>|remove <name>|apply <name>|pick|edit [name]|capture <name>|dir}" >&2; exit 1 ;;
esac
