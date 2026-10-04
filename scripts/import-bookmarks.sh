#!/usr/bin/env bash
# Import bookmarks from an installed browser into the launcher's % list.
# Wrapper around scripts/import-browser-bookmarks.py, run from the launcher's
# "Import Bookmarks" control row (cmd) or from a terminal.
#
# The wrapper exists because the importer PRINTS its report, and the launcher
# row runs it with no terminal attached -- so stdout would go nowhere and the
# user would get silence. Everything is relayed through notify-send instead:
# a toast saying what arrived, or why nothing did.

set -uo pipefail

REPO_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
IMPORTER="$REPO_HOME/scripts/import-browser-bookmarks.py"

if [[ ! -f "$IMPORTER" ]]; then
    notify-send "Import Bookmarks" "import-browser-bookmarks.py not found in $REPO_HOME" 2>/dev/null || true
    echo "[ERROR] $IMPORTER not found" >&2
    exit 1
fi

output=$(python3 "$IMPORTER" "$@" 2>&1)
status=$?

# summarise: first "N new" line if there is one, else the first real line.
summary=$(printf '%s\n' "$output" | grep -m1 'new' || true)
if [[ -z "$summary" ]]; then
    summary=$(printf '%s\n' "$output" | grep -v '^[[:space:]]*$' | head -n1 || true)
fi
summary=${summary:-"Done"}

if command -v notify-send >/dev/null 2>&1; then
    if [[ $status -eq 0 ]]; then
        notify-send "Import Bookmarks" "$summary" --icon=bookmark 2>/dev/null || true
    else
        notify-send "Import Bookmarks" "Failed — see a terminal for details" 2>/dev/null || true
    fi
fi

printf '%s\n' "$output"
exit $status