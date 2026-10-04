#!/usr/bin/env bash
# sushi-preview.sh — Sushi (GNOME Quick Look) frontend for the launcher's
# hybrid preview (Ctrl+Space on a file the native pane cannot render:
# audio, office docs, HTML, fonts, …).
#
# Verified against the running sushi 50.0-1 service (do not "fix" this):
#   bus name   org.gnome.NautilusPreviewer
#   object     /org/gnome/NautilusPreviewer
#   INTERFACE  org.gnome.NautilusPreviewer2   <- the "2" lives here, NOT in
#              the bus name; the old Previewer(1) interface is gone.
#   methods    ShowFile(s uri, s windowHandle, b closeIfAlreadyShown, s activationToken)
#              Close()
# The window is a normal toplevel; niri/rules.kdl keeps it floating and
# open-focused false so the launcher overlay never loses the keyboard.
#
# Verbs:
#   show <path>   open Sushi on <path>, or switch the existing window to it
#   close         close the Sushi window (a no-op when it is not running)
#   status        print "active"/"inactive" for the D-Bus SERVICE. NOTE: the
#                 service outlives its window (sushi is a persistent
#                 GApplication — verified: Close() removed the window while
#                 NameHasOwner stayed true), so window presence must come from
#                 niri's live window list, never from this verb.
#
# Exit codes: 0 ok · 1 usage/no such file · 2 no gdbus/session bus · 3 sushi missing.
# All process arguments ride as argv ($1, "$@"), never interpolated into sh -c.
set -u

BUS=org.gnome.NautilusPreviewer
OBJ=/org/gnome/NautilusPreviewer
IFACE=org.gnome.NautilusPreviewer2

die() {
    printf '%s\n' "$2" >&2
    exit "$1"
}

gdbus_call() {
    gdbus call --session --dest "$BUS" --object-path "$OBJ" --method "$1" "${@:2}"
}

case "${1:-}" in
    show)
        [ "$#" -eq 2 ] || die 1 "usage: sushi-preview.sh show <path>"
        command -v gdbus >/dev/null 2>&1 || die 2 "gdbus not found"
        command -v sushi >/dev/null 2>&1 || die 3 "sushi is not installed (pacman -S sushi)"
        [ -e "$2" ] || die 1 "no such file: $2"
        # as_uri() percent-encodes spaces, '#', '?' and non-ASCII for us.
        uri=$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$2") \
            || die 1 "cannot resolve path: $2"
        # Empty windowHandle/activationToken: never request activation focus
        # (the launcher overlay keeps the keyboard); closeIfAlreadyShown false
        # so switching files replaces the content instead of closing.
        err=$(gdbus_call "$IFACE.ShowFile" "$uri" "" false "" 2>&1) \
            || die 2 "sushi ShowFile failed: $err"
        ;;
    close)
        [ "$#" -eq 1 ] || die 1 "usage: sushi-preview.sh close"
        command -v gdbus >/dev/null 2>&1 || die 2 "gdbus not found"
        # Ignore errors: closing an already-closed window is a no-op.
        gdbus_call "$IFACE.Close" >/dev/null 2>&1 || true
        ;;
    status)
        [ "$#" -eq 1 ] || die 1 "usage: sushi-preview.sh status"
        command -v gdbus >/dev/null 2>&1 || die 2 "gdbus not found"
        if gdbus call --session --dest org.freedesktop.DBus \
            --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.NameHasOwner "$BUS" 2>/dev/null | grep -q 'true'; then
            echo active
            exit 0
        fi
        echo inactive
        exit 1
        ;;
    *)
        die 1 "usage: sushi-preview.sh show <path> | close | status"
        ;;
esac
