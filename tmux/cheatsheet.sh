#!/usr/bin/env bash
# tmux cheat sheet — themed like the rest of the desktop.
# Opened with prefix + ? (default prefix C-b). Standalone preview:
#   bash ~/niri-setup/tmux/cheatsheet.sh
# Two columns, 24 rows, so it fits a popup on a small terminal.
#
# Colours come from scripts/palette.sh, which reads the palette quickshell has
# active — the same source tmux/theme.conf is generated from. They used to be
# hardcoded 24-bit SGR triplets of the sunset palette, so this sheet stayed
# orange while the bar next to it was blue.

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"

# palette.sh prints key=RRGGBB. Turn those into truecolour SGR in one read, and
# fall back to the sunset defaults only if it cannot be reached (this runs from
# inside a display-popup, so it must never block on a missing dependency).
declare -A PALETTE=(
  [accent]=232,93,47 [accentHover]=255,139,74 [text]=247,199,161 [dim]=85,85,85
)
if [[ -x "$NIKI_HOME/scripts/palette.sh" ]]; then
  while IFS='=' read -r key hex; do
    case "$key" in
      accent | accentHover | text | muted | dim)
        [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]] || continue
        r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
        PALETTE[$key]="$r,$g,$b"
        ;;
    esac
  done < <("$NIKI_HOME/scripts/palette.sh" get)
fi

# dim falls back to muted, which is a readable secondary text colour where the
# per-theme dim is too faint to read inside a popup.
dim_rgb="${PALETTE[dim]:-${PALETTE[muted]:-85,85,85}}"

accent=$'\033[1;38;2;'${PALETTE[accent]}'m'
hover=$'\033[38;2;'${PALETTE[accentHover]}'m'
text=$'\033[38;2;'${PALETTE[text]}'m'
dim=$'\033[38;2;'${dim_rgb}'m'
reset=$'\033[0m'
bs='\'                            # a literal backslash

sect() { printf '\n%s%s%s\n' "$hover" "$1" "$reset"; }
pair() { printf '  %s%-10s%s %s%-27s%s %s%-10s%s %s%s%s\n' \
  "$accent" "$1" "$reset" "$text" "$2" "$reset" \
  "$accent" "$3" "$reset" "$text" "$4" "$reset"; }

printf '%s\n' "${accent}▌${text} TMUX CHEAT SHEET${dim}  ·  every key is C-b then…  ·  any key closes this${reset}"

sect "WINDOWS                            PANES"
pair "n / p"  "next / previous window"  "| or %"  "split left / right"
pair "1 - 9"  "jump to window"          "- or \"" "split up / down"
pair "c"      "new window, same folder" "arrows" "move between panes"
pair ","      "rename this window"       ";"      "jump to last pane"
pair "w"      "pick a window"            "z"      "zoom the pane, again to undo"
pair "_"      "close window (asks first)" "X"    "swap the two panes"
pair "s"      "pick a session or window" "x"     "close a pane (asks first)"
pair "C"      "new session, asks name"   "C+arrow" "resize by 5 cells"
pair "Space"  "next layout"              "C-o"    "rotate the layout"

sect "COPY / CLIPBOARD                  SESSIONS"
pair "["      "copy mode"                "$bs"     "rename this session"
pair "space"  "start a selection"        "d"      "detach, tmux attach to return"
pair "v  y"   "select, copy to clipboard" "&"     "kill the server (asks first)"
pair "P"      "paste system clipboard"   "C-c"    "new window (same session)"
pair "wheel"  "scroll the pane"          "C-b C-c" "stop a frozen program"
pair "q / Esc" "leave copy mode"         "C-a"    "also works as the prefix"

sect "UNSTUCK                            (config: ~/niri-setup/tmux/tmux.conf)"
pair "?"  "this sheet"                    "r"      "reload the config"
pair "F1" "every binding tmux knows"       "C-b C-b" "send a real C-b to a program"
